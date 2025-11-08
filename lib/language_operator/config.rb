# frozen_string_literal: true

module LanguageOperator
  # Configuration loading helpers for environment variables
  #
  # Provides utilities for loading, validating, and type-converting
  # configuration from environment variables with support for:
  # - Key-to-env-var mappings
  # - Prefixes (e.g., SMTP_HOST from prefix: 'SMTP')
  # - Default values
  # - Type conversion (string, integer, boolean, float)
  # - Required config validation
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
    # @param value [String, nil] Raw string value from environment
    # @param type [Symbol] Target type (:string, :integer, :boolean, :float)
    # @return [Object] Converted value
    #
    # @example String conversion
    #   Config.convert_type('hello', :string) # => "hello"
    #
    # @example Integer conversion
    #   Config.convert_type('42', :integer) # => 42
    #
    # @example Boolean conversion
    #   Config.convert_type('true', :boolean) # => true
    #   Config.convert_type('1', :boolean) # => true
    #   Config.convert_type('yes', :boolean) # => true
    #   Config.convert_type('false', :boolean) # => false
    #
    # @example Float conversion
    #   Config.convert_type('3.14', :float) # => 3.14
    def self.convert_type(value, type)
      return nil if value.nil?

      case type
      when :string
        value.to_s
      when :integer
        value.to_i
      when :float
        value.to_f
      when :boolean
        %w[true 1 yes on].include?(value.to_s.downcase)
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
  end
end
