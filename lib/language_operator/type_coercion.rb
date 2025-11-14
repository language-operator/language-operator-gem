# frozen_string_literal: true

module LanguageOperator
  # Type coercion system for task inputs and outputs
  #
  # Provides smart type coercion with automatic conversion for common cases
  # and clear error messages when coercion is not possible. This enables
  # flexible type handling while maintaining type safety.
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
    def self.coerce(value, type)
      case type
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
    end

    # Coerce value to Integer
    #
    # Accepts: String, Integer, Float
    # Coercion: Uses Ruby's Integer() method
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
      return value if value.is_a?(Integer)

      Integer(value)
    rescue ArgumentError, TypeError => e
      raise ArgumentError, "Cannot coerce #{value.inspect} to integer: #{e.message}"
    end

    # Coerce value to Float (number)
    #
    # Accepts: String, Integer, Float
    # Coercion: Uses Ruby's Float() method
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
      return value if value.is_a?(Numeric)

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
    # Coercion: Case-insensitive string matching
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
      return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

      # Only allow string values for coercion (not integers or other types)
      raise ArgumentError, "Cannot coerce #{value.inspect} to boolean" unless value.is_a?(String)

      str = value.strip.downcase
      return true if %w[true 1 yes t y].include?(str)
      return false if %w[false 0 no f n].include?(str)

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
