# frozen_string_literal: true

require 'yaml'
require 'net/http'
require 'uri'

module LanguageOperator
  module Config
    # Fetches and caches tool registry from remote URL
    class ToolRegistry
      REGISTRY_URL = 'https://git.theryans.io/language-operator/language-tools/raw/branch/main/index.yaml'
      CACHE_TTL = 3600 # 1 hour

      def initialize(registry_url: REGISTRY_URL, api_token: nil)
        @registry_url = registry_url
        @api_token = api_token || ENV.fetch('FORGEJO_API_TOKEN', nil)
        @cache = nil
        @cache_time = nil
      end

      # Fetch tools from registry with caching
      #
      # @return [Hash] Tool configurations keyed by tool name
      def fetch
        # Return cached data if still valid
        return @cache if @cache && @cache_time && (Time.now - @cache_time) < CACHE_TTL

        # Fetch from remote
        begin
          tools = fetch_remote
          @cache = tools
          @cache_time = Time.now
          tools
        rescue StandardError => e
          # Fall back to local file if remote fetch fails
          warn "Failed to fetch remote registry: #{e.message}"
          warn 'Falling back to local registry'
          fetch_local
        end
      end

      # Clear the cache to force a fresh fetch
      def clear_cache
        @cache = nil
        @cache_time = nil
      end

      private

      def fetch_remote
        uri = URI(@registry_url)
        response = fetch_with_redirects(uri, limit: 5)

        raise "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        # Parse YAML response
        data = YAML.safe_load(response.body)

        # Extract tools from nested structure
        data['tools'] || {}
      end

      def fetch_with_redirects(uri, limit: 5)
        raise 'Too many HTTP redirects' if limit.zero?

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "token #{@api_token}" if @api_token

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request)
        end

        case response
        when Net::HTTPSuccess
          response
        when Net::HTTPRedirection
          location = response['location']
          new_uri = URI(location)
          # Preserve authorization for same host
          fetch_with_redirects(new_uri, limit: limit - 1)
        else
          response
        end
      end

      def fetch_local
        # Fall back to bundled local registry
        patterns_path = File.join(__dir__, 'tool_patterns.yaml')
        return {} unless File.exist?(patterns_path)

        YAML.load_file(patterns_path)
      end
    end
  end
end
