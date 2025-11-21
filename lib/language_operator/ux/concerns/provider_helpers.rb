# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module LanguageOperator
  module Ux
    module Concerns
      # Mixin for common LLM provider operations
      #
      # Provides helpers for testing provider connections, fetching available models,
      # and handling provider-specific configuration.
      #
      # @example
      #   class MyFlow < Base
      #     include Concerns::ProviderHelpers
      #
      #     def setup
      #       result = test_provider_connection(:anthropic, api_key: 'sk-...')
      #       models = fetch_provider_models(:openai, api_key: 'sk-...')
      #     end
      #   end
      module ProviderHelpers
        # Test connection to an LLM provider
        #
        # @param provider [Symbol] Provider type (:anthropic, :openai, :openai_compatible)
        # @param api_key [String, nil] API key for authentication
        # @param endpoint [String, nil] Custom endpoint URL (for openai_compatible)
        # @return [Hash] Result with :success and optional :error keys
        def test_provider_connection(provider, api_key: nil, endpoint: nil)
          require 'ruby_llm'

          case provider
          when :anthropic
            test_anthropic(api_key)
          when :openai
            test_openai(api_key)
          when :openai_compatible
            test_openai_compatible(endpoint, api_key)
          else
            { success: false, error: "Unknown provider: #{provider}" }
          end
        end

        # Fetch available models from a provider
        #
        # @param provider [Symbol] Provider type
        # @param api_key [String, nil] API key for authentication
        # @param endpoint [String, nil] Custom endpoint URL
        # @return [Array<String>, nil] List of model IDs or nil if unavailable
        def fetch_provider_models(provider, api_key: nil, endpoint: nil)
          case provider
          when :anthropic
            # Anthropic doesn't have a public /v1/models endpoint
            [
              'claude-3-5-sonnet-20241022',
              'claude-3-opus-20240229',
              'claude-3-sonnet-20240229',
              'claude-3-haiku-20240307'
            ]
          when :openai
            fetch_openai_models(api_key)
          when :openai_compatible
            fetch_openai_compatible_models(endpoint, api_key)
          end
        rescue StandardError => e
          CLI::Formatters::ProgressFormatter.warn("Could not fetch models: #{e.message}")
          nil
        end

        # Get provider display information
        #
        # @param provider [Symbol] Provider type
        # @return [Hash] Hash with :name, :docs_url keys
        def provider_info(provider)
          case provider
          when :anthropic
            { name: 'Anthropic', docs_url: 'https://console.anthropic.com' }
          when :openai
            { name: 'OpenAI', docs_url: 'https://platform.openai.com/api-keys' }
          when :openai_compatible
            { name: 'OpenAI-Compatible', docs_url: nil }
          else
            { name: provider.to_s.capitalize, docs_url: nil }
          end
        end

        private

        def test_anthropic(api_key)
          client = RubyLLM.new(provider: :anthropic, api_key: api_key)
          client.chat(
            [{ role: 'user', content: 'Test' }],
            model: 'claude-3-5-sonnet-20241022',
            max_tokens: 10
          )
          { success: true }
        rescue StandardError => e
          { success: false, error: e.message }
        end

        def test_openai(api_key)
          client = RubyLLM.new(provider: :openai, api_key: api_key)
          client.chat(
            [{ role: 'user', content: 'Test' }],
            model: 'gpt-4-turbo',
            max_tokens: 10
          )
          { success: true }
        rescue StandardError => e
          { success: false, error: e.message }
        end

        def test_openai_compatible(endpoint, api_key = nil)
          # For OpenAI-compatible endpoints, we don't make a test request
          # as we can't know what model to use. Just verify the endpoint is reachable.
          fetch_openai_compatible_models(endpoint, api_key)
          { success: true }
        rescue StandardError => e
          { success: false, error: e.message }
        end

        def fetch_openai_models(api_key)
          fetch_models_from_endpoint('https://api.openai.com', api_key)
        end

        def fetch_openai_compatible_models(endpoint, api_key)
          return nil unless endpoint

          fetch_models_from_endpoint(endpoint, api_key)
        end

        def fetch_models_from_endpoint(base_url, api_key)
          models_url = URI.join(
            base_url.end_with?('/') ? base_url : "#{base_url}/",
            'v1/models'
          ).to_s

          uri = URI(models_url)
          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Bearer #{api_key}" if api_key
          request['Content-Type'] = 'application/json'

          response = Net::HTTP.start(
            uri.hostname,
            uri.port,
            use_ssl: uri.scheme == 'https',
            read_timeout: 10
          ) do |http|
            http.request(request)
          end

          return nil unless response.is_a?(Net::HTTPSuccess)

          data = JSON.parse(response.body)
          models = data['data']&.map { |m| m['id'] } || []

          # Filter out fine-tuned models for better UX
          models.reject { |m| m.include?('ft-') }
        rescue StandardError
          nil
        end
      end
    end
  end
end
