# frozen_string_literal: true

module LanguageOperator
  # Configuration loading helpers for environment variables
  #
  # Provides utilities for loading, validating, and type-converting
  # configuration from environment variables with support for:
  # - Key-to-env-var mappings
  # - Prefixes (e.g., SMTP_HOST from prefix: 'SMTP')
  # - Default values
  # - Type conversion (string, integer, boolean, float, array)
  # - Required config validation
  # - Multiple fallback keys
  #
  # @example Load SMTP configuration
  #   config = LanguageOperator::Config.load(
  #     { host: 'HOST', port: 'PORT', user: 'USER', password: 'PASSWORD' },
  #     prefix: 'SMTP',
  #     required: [:host, :user, :password],
  #     defaults: { port: '587', tls: 'true' },
  #     types: { port: :integer, tls: :boolean }
  #   )
  #   # => { host: "smtp.example.com", port: 587, user: "user@example.com",
  #   #      password: "secret", tls: true }
  module Config
    # Load configuration from environment variables
    #
    # @param mappings [Hash{Symbol => String}] Map of config keys to env var names
    # @param prefix [String, nil] Optional prefix to prepend to env var names
    # @param defaults [Hash{Symbol => Object}] Default values for optional config
    # @param types [Hash{Symbol => Symbol}] Type conversion (:string, :integer, :boolean, :float)
    # @return [Hash{Symbol => Object}] Configuration hash with values from env vars or defaults
    #
    # @example Basic usage
    #   config = Config.from_env(
    #     { database_url: 'DATABASE_URL' },
    #     defaults: { database_url: 'sqlite://localhost/db.sqlite3' }
    #   )
    #
    # @example With prefix and types
    #   config = Config.from_env(
    #     { host: 'HOST', port: 'PORT' },
    #     prefix: 'REDIS',
    #     defaults: { port: '6379' },
    #     types: { port: :integer }
    #   )
    #   # Reads REDIS_HOST and REDIS_PORT env vars
    def self.from_env(mappings, prefix: nil, defaults: {}, types: {})
      config = {}

      mappings.each do |key, env_var|
        full_var = prefix ? "#{prefix}_#{env_var}" : env_var
        raw_value = ENV[full_var] || defaults[key]

        config[key] = convert_type(raw_value, types[key] || :string)
      end

      config
    end

    # Validate that required configuration keys are present and non-empty
    #
    # @param config [Hash] Configuration hash
    # @param required_keys [Array<Symbol>] Keys that must be present
    # @raise [RuntimeError] If any required keys are missing or empty
    #
    # @example
    #   Config.validate_required!(config, [:host, :user, :password])
    def self.validate_required!(config, required_keys)
      missing = required_keys.select { |key| config[key].nil? || config[key].to_s.strip.empty? }
      return if missing.empty?

      raise LanguageOperator::Errors.missing_config(missing.map(&:to_s).map(&:upcase))
    end

    # Convert a string value to the specified type
    #
    # For integer and float types, uses strict conversion that raises ArgumentError
    # for invalid input (e.g., non-numeric strings).
    #
    # @param value [String, nil] Raw string value from environment
    # @param type [Symbol] Target type (:string, :integer, :boolean, :float, :array)
    # @param separator [String] Separator for array type (default: ',')
    # @return [Object] Converted value
    # @raise [ArgumentError] When integer/float conversion fails
    #
    # @example String conversion
    #   Config.convert_type('hello', :string) # => "hello"
    #
    # @example Integer conversion
    #   Config.convert_type('42', :integer) # => 42
    #   Config.convert_type('abc', :integer) # raises ArgumentError
    #
    # @example Boolean conversion
    #   Config.convert_type('true', :boolean) # => true
    #   Config.convert_type('1', :boolean) # => true
    #   Config.convert_type('yes', :boolean) # => true
    #   Config.convert_type('false', :boolean) # => false
    #
    # @example Float conversion
    #   Config.convert_type('3.14', :float) # => 3.14
    #   Config.convert_type('xyz', :float) # raises ArgumentError
    #
    # @example Array conversion
    #   Config.convert_type('a,b,c', :array) # => ["a", "b", "c"]
    def self.convert_type(value, type, separator: ',')
      return nil if value.nil?

      case type
      when :string
        value.to_s
      when :integer
        Integer(value)
      when :float
        Float(value)
      when :boolean
        %w[true 1 yes on].include?(value.to_s.downcase)
      when :array
        return [] if value.to_s.empty?

        value.to_s.split(separator).map(&:strip).reject(&:empty?)
      else
        value
      end
    end

    # Load configuration with validation in one call
    #
    # Combines from_env and validate_required! for convenience.
    #
    # @param mappings [Hash] Config key to env var mappings
    # @param required [Array<Symbol>] Required config keys
    # @param defaults [Hash] Default values
    # @param types [Hash] Type conversions
    # @param prefix [String, nil] Env var prefix
    # @return [Hash] Validated configuration
    # @raise [RuntimeError] If required keys are missing
    #
    # @example Complete configuration loading
    #   config = Config.load(
    #     { host: 'HOST', port: 'PORT', user: 'USER', password: 'PASSWORD' },
    #     prefix: 'SMTP',
    #     required: [:host, :user, :password],
    #     defaults: { port: '587' },
    #     types: { port: :integer }
    #   )
    def self.load(mappings, required: [], defaults: {}, types: {}, prefix: nil)
      config = from_env(mappings, prefix: prefix, defaults: defaults, types: types)
      validate_required!(config, required) unless required.empty?
      config
    end

    # Get environment variable with multiple fallback keys
    #
    # @param keys [Array<String>] Environment variable names to try
    # @param default [Object, nil] Default value if none found
    # @return [String, nil] The first non-nil value or default
    #
    # @example
    #   Config.get('SMTP_HOST', 'MAIL_HOST', default: 'localhost')
    def self.get(*keys, default: nil)
      keys.each do |key|
        value = ENV.fetch(key.to_s, nil)
        return value if value
      end
      default
    end

    # Get required environment variable with fallback keys
    #
    # @param keys [Array<String>] Environment variable names to try
    # @return [String] The first non-nil value
    # @raise [ArgumentError] If none of the keys are set
    #
    # @example
    #   Config.require('DATABASE_URL', 'DB_URL')
    def self.require(*keys)
      value = get(*keys)
      raise ArgumentError, "Missing required configuration: #{keys.join(' or ')}" unless value

      value
    end

    # Get environment variable as integer
    #
    # @param keys [Array<String>] Environment variable names to try
    # @param default [Integer, nil] Default value if none found
    # @return [Integer, nil] The value converted to integer, or default
    #
    # @example
    #   Config.get_int('MAX_WORKERS', default: 4)
    def self.get_int(*keys, default: nil)
      keys.each do |key|
        value = ENV[key.to_s]
        next unless value

        begin
          return Integer(value)
        rescue ArgumentError, TypeError => e
          suggestion = "Please set #{key} to a valid integer (e.g., export #{key}=4)"
          raise ArgumentError, "Invalid integer value '#{value}' in environment variable '#{key}'. #{suggestion}. Error: #{e.message}"
        end
      end

      return default if default

      # No variables found
      raise ArgumentError, "Missing required integer configuration. Checked environment variables: #{keys.join(', ')}. Please set one of these variables."
    end

    # Get environment variable as boolean
    #
    # Treats 'true', '1', 'yes', 'on' as true (case insensitive).
    #
    # @param keys [Array<String>] Environment variable names to try
    # @param default [Boolean] Default value if none found
    # @return [Boolean] The value as boolean
    #
    # @example
    #   Config.get_bool('USE_TLS', 'ENABLE_TLS', default: true)
    def self.get_bool(*keys, default: false)
      keys.each do |key|
        value = ENV[key.to_s]
        next unless value

        return %w[true 1 yes on].include?(value.to_s.downcase)
      end

      default
    end

    # Get environment variable as array (split by separator)
    #
    # @param keys [Array<String>] Environment variable names to try
    # @param default [Array] Default value if none found
    # @param separator [String] Character to split on (default: ',')
    # @return [Array<String>] The value split into array
    #
    # @example
    #   Config.get_array('ALLOWED_HOSTS', separator: ',')
    def self.get_array(*keys, default: [], separator: ',')
      keys.each do |key|
        value = ENV[key.to_s]
        next unless value
        next if value.empty?

        return value.split(separator).map(&:strip).reject(&:empty?)
      end

      default
    end

    # Check if environment variable is set (even if empty string)
    #
    # @param keys [Array<String>] Environment variable names to check
    # @return [Boolean] True if any key is set
    #
    # @example
    #   Config.set?('DEBUG', 'VERBOSE')
    def self.set?(*keys)
      keys.any? { |key| ENV.key?(key.to_s) }
    end

    # Get all environment variables matching a prefix
    #
    # @param prefix [String] Prefix to match
    # @return [Hash<String, String>] Hash with prefix removed from keys
    #
    # @example
    #   Config.with_prefix('DATABASE_')
    #   # Returns { 'URL' => '...', 'POOL_SIZE' => '5' } for DATABASE_URL and DATABASE_POOL_SIZE
    def self.with_prefix(prefix)
      ENV.select { |key, _| key.start_with?(prefix) }
         .transform_keys { |key| key.sub(prefix, '') }
    end
  end
end
