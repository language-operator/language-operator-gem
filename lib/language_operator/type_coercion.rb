# frozen_string_literal: true

require 'lru_redux'

module LanguageOperator
  # Type coercion system for task inputs and outputs
  #
  # Provides smart type coercion with automatic conversion for common cases
  # and clear error messages when coercion is not possible. This enables
  # flexible type handling while maintaining type safety.
  #
  # Performance optimizations:
  # - Fast-path checks for already-correct types
  # - Bounded LRU memoization cache for expensive string coercions (prevents memory leaks)
  # - Pre-compiled regexes for boolean parsing
  # - Thread-safe cache operations with mutex protection
  #
  # Supported types:
  # - integer: Coerces String, Integer, Float to Integer
  # - number: Coerces String, Integer, Float to Float
  # - string: Coerces any value to String via to_s
  # - boolean: Coerces String, Boolean to Boolean (explicit values only)
  # - array: Strict validation (no coercion)
  # - hash: Strict validation (no coercion)
  # - any: No coercion, passes through any value
  #
  # @example Integer coercion
  #   TypeCoercion.coerce("123", "integer")  # => 123
  #   TypeCoercion.coerce(123, "integer")    # => 123
  #   TypeCoercion.coerce("abc", "integer")  # raises ArgumentError
  #
  # @example Boolean coercion
  #   TypeCoercion.coerce("true", "boolean")   # => true
  #   TypeCoercion.coerce("1", "boolean")      # => true
  #   TypeCoercion.coerce("false", "boolean")  # => false
  #   TypeCoercion.coerce("maybe", "boolean")  # raises ArgumentError
  #
  # @example String coercion (never fails)
  #   TypeCoercion.coerce(:symbol, "string")  # => "symbol"
  #   TypeCoercion.coerce(123, "string")      # => "123"
  #
  # @example Strict validation
  #   TypeCoercion.coerce([1, 2], "array")    # => [1, 2]
  #   TypeCoercion.coerce({a: 1}, "array")    # raises ArgumentError
  module TypeCoercion
    # Memory-safe LRU cache for expensive coercions with bounded size to prevent memory leaks
    # - Cache automatically evicts least recently used entries when limit is reached
    # - Default cache size: 1000 entries (configurable via TYPE_COERCION_CACHE_SIZE environment variable)
    # - Thread-safe operations protected by mutex
    # - Caches both successful and failed coercion attempts to avoid repeated expensive operations
    DEFAULT_CACHE_SIZE = 1000
    @cache_size = ENV.fetch('TYPE_COERCION_CACHE_SIZE', DEFAULT_CACHE_SIZE).to_i
    @coercion_cache = LruRedux::Cache.new(@cache_size)
    @cache_mutex = Mutex.new
    @cache_hits = 0
    @cache_misses = 0

    # Boolean patterns - pre-compiled for performance
    TRUTHY_PATTERNS = %w[true 1 yes t y].freeze
    FALSY_PATTERNS = %w[false 0 no f n].freeze

    class << self
      # Get current cache size limit
      attr_reader :cache_size

      # Coerce a value to the specified type
      #
      # @param value [Object] Value to coerce
      # @param type [String] Target type (see COERCION_RULES for valid types)
      # @return [Object] Coerced value
      # @raise [ArgumentError] If coercion fails or type is unknown
      #
      # @example
      #   TypeCoercion.coerce("345", "integer")  # => 345
      #   TypeCoercion.coerce("true", "boolean") # => true
      def coerce(value, type)
        # Fast path - check cache first for expensive string coercions
        if value.is_a?(String) && %w[integer number boolean].include?(type)
          cache_key = [value, type]
          cached = @cache_mutex.synchronize { @coercion_cache[cache_key] }
          if cached
            @cache_hits += 1
            return cached[:result] if cached[:success]

            raise ArgumentError, cached[:error_message]
          end
          @cache_misses += 1
        end

        # Perform coercion
        result = case type
                 when 'integer'
                   coerce_integer(value)
                 when 'number'
                   coerce_number(value)
                 when 'string'
                   coerce_string(value)
                 when 'boolean'
                   coerce_boolean(value)
                 when 'array'
                   validate_array(value)
                 when 'hash'
                   validate_hash(value)
                 when 'any'
                   value
                 else
                   raise ArgumentError, "Unknown type: #{type}"
                 end

        # Cache successful string coercion results
        if value.is_a?(String) && %w[integer number boolean].include?(type)
          cache_entry = { success: true, result: result }
          @cache_mutex.synchronize { @coercion_cache[[value, type]] = cache_entry }
        end

        result
      rescue ArgumentError => e
        # Cache failed coercion attempts to avoid repeating expensive failures
        if value.is_a?(String) && %w[integer number boolean].include?(type)
          cache_entry = { success: false, error_message: e.message }
          @cache_mutex.synchronize { @coercion_cache[[value, type]] = cache_entry }
        end
        raise
      end

      # Get cache statistics for monitoring
      def cache_stats
        @cache_mutex.synchronize do
          {
            size: @coercion_cache.count,
            max_size: @cache_size,
            hits: @cache_hits,
            misses: @cache_misses,
            hit_rate: @cache_hits.zero? ? 0.0 : @cache_hits.to_f / (@cache_hits + @cache_misses)
          }
        end
      end

      # Clear the cache (for testing or memory management)
      def clear_cache
        @cache_mutex.synchronize do
          @coercion_cache.clear
          @cache_hits = 0
          @cache_misses = 0
        end
      end
    end

    # Coerce value to Integer
    #
    # Accepts: String, Integer, Float
    # Coercion: Uses Ruby's Integer() method with fast-path optimization
    # Errors: Cannot parse as integer
    #
    # @param value [Object] Value to coerce
    # @return [Integer] Coerced integer
    # @raise [ArgumentError] If coercion fails
    #
    # @example
    #   coerce_integer("123")   # => 123
    #   coerce_integer(123)     # => 123
    #   coerce_integer(123.0)   # => 123
    #   coerce_integer("abc")   # raises ArgumentError
    def self.coerce_integer(value)
      # Fast path for already-correct types
      return value if value.is_a?(Integer)

      Integer(value)
    rescue ArgumentError, TypeError => e
      raise ArgumentError, "Cannot coerce #{value.inspect} to integer: #{e.message}"
    end

    # Coerce value to Float (number)
    #
    # Accepts: String, Integer, Float
    # Coercion: Uses Ruby's Float() method with fast-path optimization
    # Errors: Cannot parse as number
    #
    # @param value [Object] Value to coerce
    # @return [Float] Coerced number
    # @raise [ArgumentError] If coercion fails
    #
    # @example
    #   coerce_number("3.14")      # => 3.14
    #   coerce_number(3)           # => 3.0
    #   coerce_number(3.14)        # => 3.14
    #   coerce_number("not a num") # raises ArgumentError
    def self.coerce_number(value)
      # Fast path for already-correct types
      return value.to_f if value.is_a?(Numeric)

      Float(value)
    rescue ArgumentError, TypeError => e
      raise ArgumentError, "Cannot coerce #{value.inspect} to number: #{e.message}"
    end

    # Coerce value to String
    #
    # Accepts: Any object with to_s method (all Ruby objects)
    # Coercion: Uses to_s method
    # Errors: Never (everything has to_s)
    #
    # @param value [Object] Value to coerce
    # @return [String] Coerced string
    #
    # @example
    #   coerce_string(:symbol)  # => "symbol"
    #   coerce_string(123)      # => "123"
    #   coerce_string(nil)      # => ""
    def self.coerce_string(value)
      value.to_s
    end

    # Coerce value to Boolean
    #
    # Accepts: Boolean, String (explicit values only)
    # Coercion: Case-insensitive string matching with optimized pattern lookup
    # Truthy: "true", "1", "yes", "t", "y"
    # Falsy: "false", "0", "no", "f", "n"
    # Errors: Ambiguous values (e.g., "maybe", "unknown")
    #
    # @param value [Object] Value to coerce
    # @return [Boolean] Coerced boolean
    # @raise [ArgumentError] If coercion is ambiguous
    #
    # @example
    #   coerce_boolean(true)      # => true
    #   coerce_boolean("true")    # => true
    #   coerce_boolean("1")       # => true
    #   coerce_boolean("yes")     # => true
    #   coerce_boolean(false)     # => false
    #   coerce_boolean("false")   # => false
    #   coerce_boolean("0")       # => false
    #   coerce_boolean("no")      # => false
    #   coerce_boolean("maybe")   # raises ArgumentError
    def self.coerce_boolean(value)
      # Fast path for already-correct types
      return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

      # Only allow string values for coercion (not integers or other types)
      raise ArgumentError, "Cannot coerce #{value.inspect} to boolean" unless value.is_a?(String)

      # Optimized pattern matching using pre-compiled arrays
      str = value.strip.downcase
      return true if TRUTHY_PATTERNS.include?(str)
      return false if FALSY_PATTERNS.include?(str)

      raise ArgumentError, "Cannot coerce #{value.inspect} to boolean"
    end

    # Validate value is an Array (no coercion)
    #
    # Accepts: Array
    # Coercion: None (strict validation)
    # Errors: Not an array
    #
    # @param value [Object] Value to validate
    # @return [Array] Validated array
    # @raise [ArgumentError] If not an array
    #
    # @example
    #   validate_array([1, 2, 3])  # => [1, 2, 3]
    #   validate_array({a: 1})     # raises ArgumentError
    def self.validate_array(value)
      raise ArgumentError, "Expected array, got #{value.class}" unless value.is_a?(Array)

      value
    end

    # Validate value is a Hash (no coercion)
    #
    # Accepts: Hash
    # Coercion: None (strict validation)
    # Errors: Not a hash
    #
    # @param value [Object] Value to validate
    # @return [Hash] Validated hash
    # @raise [ArgumentError] If not a hash
    #
    # @example
    #   validate_hash({a: 1, b: 2})  # => {a: 1, b: 2}
    #   validate_hash([1, 2])         # raises ArgumentError
    def self.validate_hash(value)
      raise ArgumentError, "Expected hash, got #{value.class}" unless value.is_a?(Hash)

      value
    end

    # Coercion rules table
    #
    # @return [Hash] Mapping of types to their coercion behavior
    # rubocop:disable Metrics/MethodLength
    def self.coercion_rules
      {
        'integer' => {
          accepts: 'String, Integer, Float',
          method: 'Integer(value)',
          errors: 'Cannot parse as integer'
        },
        'number' => {
          accepts: 'String, Integer, Float',
          method: 'Float(value)',
          errors: 'Cannot parse as number'
        },
        'string' => {
          accepts: 'Any object',
          method: 'value.to_s',
          errors: 'Never (everything has to_s)'
        },
        'boolean' => {
          accepts: 'Boolean, String (explicit values)',
          method: 'Pattern matching (true/1/yes/t/y or false/0/no/f/n)',
          errors: 'Ambiguous values'
        },
        'array' => {
          accepts: 'Array only',
          method: 'No coercion (strict)',
          errors: 'Not an array'
        },
        'hash' => {
          accepts: 'Hash only',
          method: 'No coercion (strict)',
          errors: 'Not a hash'
        },
        'any' => {
          accepts: 'Any value',
          method: 'No coercion (pass-through)',
          errors: 'Never'
        }
      }
    end
    # rubocop:enable Metrics/MethodLength
  end
end
