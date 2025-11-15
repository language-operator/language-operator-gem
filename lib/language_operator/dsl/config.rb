# frozen_string_literal: true

module LanguageOperator
  module Dsl
    # Configuration helper for managing environment variables
    #
    # This class delegates to LanguageOperator::Config for all functionality.
    # It exists for backwards compatibility with existing code that uses
    # Dsl::Config.
    #
    # @deprecated Use LanguageOperator::Config directly instead
    #
    # @example Basic usage
    #   Config.get('SMTP_HOST', 'MAIL_HOST', default: 'localhost')
    #   Config.require('DATABASE_URL')
    #   Config.get_bool('USE_TLS', default: true)
    class Config
      # Get environment variable with multiple fallback keys
      # Delegates to LanguageOperator::Config.get
      def self.get(*keys, default: nil)
        LanguageOperator::Config.get(*keys, default: default)
      end

      # Get required environment variable with fallback keys
      # Delegates to LanguageOperator::Config.require
      def self.require(*keys)
        LanguageOperator::Config.require(*keys)
      end

      # Get environment variable as integer
      # Delegates to LanguageOperator::Config.get_int
      def self.get_int(*keys, default: nil)
        LanguageOperator::Config.get_int(*keys, default: default)
      end

      # Get environment variable as boolean
      # Delegates to LanguageOperator::Config.get_bool
      def self.get_bool(*keys, default: false)
        LanguageOperator::Config.get_bool(*keys, default: default)
      end

      # Get environment variable as array
      # Delegates to LanguageOperator::Config.get_array
      def self.get_array(*keys, default: [], separator: ',')
        LanguageOperator::Config.get_array(*keys, default: default, separator: separator)
      end

      # Check if environment variable is set
      # Delegates to LanguageOperator::Config.set?
      def self.set?(*keys)
        LanguageOperator::Config.set?(*keys)
      end

      # Get all environment variables matching a prefix
      # Delegates to LanguageOperator::Config.with_prefix
      def self.with_prefix(prefix)
        LanguageOperator::Config.with_prefix(prefix)
      end

      # Build a configuration hash from environment variables
      #
      # @param mappings [Hash{Symbol => Array<String>, String}] Config key to env var(s) mapping
      # @return [Hash{Symbol => String}] Configuration hash with values found
      def self.build(mappings)
        config = {}
        mappings.each do |config_key, env_keys|
          env_keys = [env_keys] unless env_keys.is_a?(Array)
          value = LanguageOperator::Config.get(*env_keys)
          config[config_key] = value if value
        end
        config
      end

      # Check if all required keys are present
      #
      # @param keys [Array<String>] Environment variable names to check
      # @return [Array<String>] Array of missing keys (empty if all present)
      def self.check_required(*keys)
        keys.reject { |key| ENV.fetch(key.to_s, nil) }
      end
    end
  end
end
