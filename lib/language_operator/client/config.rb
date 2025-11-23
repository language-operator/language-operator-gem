# frozen_string_literal: true

require 'yaml'

module LanguageOperator
  module Client
    # Configuration management for Langop MCP Client
    #
    # Handles loading configuration from YAML files or environment variables,
    # with automatic provider detection and sensible defaults.
    #
    # @example Load from YAML file
    #   config = Config.load('/path/to/config.yaml')
    #
    # @example Load from environment variables
    #   config = Config.from_env
    #
    # @example Load with fallback
    #   config = Config.load_with_fallback('/path/to/config.yaml')
    class Config
      # Load configuration from a YAML file
      #
      # @param path [String] Path to YAML configuration file
      # @return [Hash] Configuration hash
      # @raise [Errno::ENOENT] If file doesn't exist
      def self.load(path)
        config = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
        # Normalize structure to ensure defaults
        config['mcp_servers'] ||= []
        config
      end

      # Load configuration from environment variables
      #
      # @return [Hash] Configuration hash built from ENV
      def self.from_env
        {
          'llm' => {
            'provider' => detect_provider_from_env,
            'model' => LanguageOperator::Config.get('LLM_MODEL', default: default_model_from_env),
            'endpoint' => parse_model_endpoint_from_env,
            'api_key' => LanguageOperator::Config.get('OPENAI_API_KEY', 'ANTHROPIC_API_KEY',
                                                      default: 'dummy-key-for-local-proxy')
          },
          'mcp_servers' => parse_mcp_servers_from_env,
          'debug' => LanguageOperator::Config.get_bool('DEBUG', default: false)
        }
      end

      # Parse model endpoint from environment variable
      #
      # Supports both MODEL_ENDPOINTS (comma-separated, uses first) and OPENAI_ENDPOINT
      #
      # @return [String, nil] Model endpoint URL
      def self.parse_model_endpoint_from_env
        # Support MODEL_ENDPOINTS (operator sets this) - take first from comma-separated list
        endpoints = LanguageOperator::Config.get_array('MODEL_ENDPOINTS')
        return endpoints.first unless endpoints.empty?

        # Fallback to legacy OPENAI_ENDPOINT
        LanguageOperator::Config.get('OPENAI_ENDPOINT')
      end

      # Load configuration with automatic fallback to environment variables
      #
      # @param path [String] Path to YAML configuration file
      # @return [Hash] Configuration hash
      def self.load_with_fallback(path)
        return from_env unless File.exist?(path)

        load(path)
      rescue StandardError => e
        warn "⚠️  Error loading config from #{path}: #{e.message}"
        warn 'Using environment variable fallback mode...'
        from_env
      end

      # Detect LLM provider from environment variables
      #
      # @return [String] Provider name (openai_compatible, openai, or anthropic)
      # @raise [RuntimeError] If no API key or endpoint is found
      def self.detect_provider_from_env
        if LanguageOperator::Config.set?('OPENAI_ENDPOINT', 'MODEL_ENDPOINTS')
          'openai_compatible'
        elsif LanguageOperator::Config.set?('OPENAI_API_KEY')
          'openai'
        elsif LanguageOperator::Config.set?('ANTHROPIC_API_KEY')
          'anthropic'
        else
          raise 'No API key or endpoint found. Set OPENAI_ENDPOINT or MODEL_ENDPOINTS for local LLM, ' \
                'or OPENAI_API_KEY/ANTHROPIC_API_KEY for cloud providers.'
        end
      end

      # Get default model for detected provider
      #
      # @return [String] Default model name
      def self.default_model_from_env
        {
          'openai' => 'gpt-4',
          'openai_compatible' => 'gpt-3.5-turbo',
          'anthropic' => 'claude-3-5-sonnet-20241022'
        }[detect_provider_from_env]
      end

      # Parse MCP servers from environment variables
      #
      # Supports MCP_SERVERS env var as comma-separated URLs or single MCP_URL
      #
      # @return [Array<Hash>] Array of MCP server configurations
      def self.parse_mcp_servers_from_env
        # Support both MCP_SERVERS (comma-separated) and legacy MCP_URL
        servers = LanguageOperator::Config.get_array('MCP_SERVERS')

        if !servers.empty?
          # Parse comma-separated URLs
          servers.map.with_index do |url, index|
            {
              'name' => "default-tools-#{index}",
              'url' => url,
              'transport' => 'streamable',
              'enabled' => true
            }
          end
        elsif (url = LanguageOperator::Config.get('MCP_URL'))
          [{
            'name' => 'default-tools',
            'url' => url,
            'transport' => 'streamable',
            'enabled' => true
          }]
        else
          []
        end
      end
    end
  end
end
