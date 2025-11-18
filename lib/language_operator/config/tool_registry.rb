# frozen_string_literal: true

require 'yaml'
require 'net/http'
require 'uri'

module LanguageOperator
  module Config
    # Fetches and caches tool registry from remote URL
    class ToolRegistry
      REGISTRY_URL = 'https://raw.githubusercontent.com/language-operator/language-tools/main/index.yaml'
      CACHE_TTL = 3600 # 1 hour

      def initialize(registry_url: REGISTRY_URL, api_token: nil)
        @registry_url = registry_url
        @api_token = api_token || ENV.fetch('GITHUB_TOKEN', nil)
        @cache = nil
        @cache_time = nil
      end

      # Fetch tools from registry with caching
      #
      # @return [Hash] Tool configurations keyed by tool name
      def fetch
        # Return cached data if still valid
        return @cache if @cache && @cache_time && (Time.now - @cache_time) < CACHE_TTL

        # Fetch from remote (no fallback)
        tools = fetch_remote
        @cache = tools
        @cache_time = Time.now
        tools
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
          # Handle relative redirects by merging with current URI
          new_uri = uri.merge(location)
          # Preserve authorization for same host
          fetch_with_redirects(new_uri, limit: limit - 1)
        else
          response
        end
      end

    end
  end
end
