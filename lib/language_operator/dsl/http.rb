# frozen_string_literal: true

require 'English'
require 'net/http'
require 'uri'
require 'json'
require 'ipaddr'
require 'socket'

module LanguageOperator
  module Dsl
    # HTTP client helper for MCP tools
    #
    # Provides convenient methods for making HTTP requests from within tools.
    # Supports GET, POST, PUT, DELETE, HEAD with automatic JSON parsing.
    #
    # @example Making a GET request
    #   result = HTTP.get('https://api.example.com/users')
    #   if result[:success]
    #     users = result[:json]
    #   end
    class HTTP
      # Perform a GET request
      def self.get(url, headers: {}, follow_redirects: true, timeout: 30)
        validation_result = validate_url(url)
        return validation_result unless validation_result[:success]

        uri = validation_result[:uri]

        http = build_http(uri, timeout: timeout)
        request = Net::HTTP::Get.new(uri)
        add_headers(request, headers)

        execute_request(http, request, follow_redirects: follow_redirects)
      end

      # Perform a POST request
      def self.post(url, body: nil, json: nil, headers: {}, auth: nil, timeout: 30)
        validation_result = validate_url(url)
        return validation_result unless validation_result[:success]

        uri = validation_result[:uri]

        http = build_http(uri, timeout: timeout)
        request = Net::HTTP::Post.new(uri)

        # Set body
        if json
          request.body = json.to_json
          request['Content-Type'] = 'application/json'
        elsif body
          request.body = body
        end

        add_headers(request, headers)
        add_auth(request, auth) if auth

        execute_request(http, request)
      end

      # Perform a PUT request
      def self.put(url, body: nil, json: nil, headers: {}, auth: nil, timeout: 30)
        validation_result = validate_url(url)
        return validation_result unless validation_result[:success]

        uri = validation_result[:uri]

        http = build_http(uri, timeout: timeout)
        request = Net::HTTP::Put.new(uri)

        if json
          request.body = json.to_json
          request['Content-Type'] = 'application/json'
        elsif body
          request.body = body
        end

        add_headers(request, headers)
        add_auth(request, auth) if auth

        execute_request(http, request)
      end

      # Perform a DELETE request
      def self.delete(url, headers: {}, auth: nil, timeout: 30)
        validation_result = validate_url(url)
        return validation_result unless validation_result[:success]

        uri = validation_result[:uri]

        http = build_http(uri, timeout: timeout)
        request = Net::HTTP::Delete.new(uri)

        add_headers(request, headers)
        add_auth(request, auth) if auth

        execute_request(http, request)
      end

      # Get just the headers from a URL
      def self.head(url, headers: {}, timeout: 30)
        validation_result = validate_url(url)
        return validation_result unless validation_result[:success]

        uri = validation_result[:uri]

        http = build_http(uri, timeout: timeout)
        request = Net::HTTP::Head.new(uri)
        add_headers(request, headers)

        execute_request(http, request)
      end

      # Wrapper for curl commands (REMOVED FOR SECURITY)
      # This method has been removed as it executes shell commands via backticks
      # which is a security risk in synthesized code.
      # @deprecated This method has been removed for security reasons
      # @raise [SecurityError] Always raises an error
      def self.curl(_url, options: [])
        raise SecurityError, 'HTTP.curl has been removed for security reasons. Use HTTP.get, HTTP.post, etc. instead.'
      end

      class << self
        private

        def validate_url(url)
          return { error: 'URL cannot be nil', success: false } if url.nil?

          begin
            uri = URI.parse(url)
          rescue URI::InvalidURIError
            return { error: 'Invalid URL format', success: false }
          end

          return { error: 'URL cannot be empty', success: false } if uri.nil?

          # Validate URL scheme
          unless %w[http https].include?(uri.scheme&.downcase)
            return {
              error: "URL scheme '#{uri.scheme}' not allowed. Only HTTP and HTTPS are permitted for security reasons.",
              success: false
            }
          end

          # Validate host
          host_validation = validate_host(uri.host)
          return host_validation unless host_validation[:success]

          { success: true, uri: uri }
        end

        def parse_uri(url)
          URI.parse(url)
        rescue URI::InvalidURIError
          nil
        end

        def validate_host(host)
          return { error: 'Host cannot be empty', success: false } if host.nil? || host.empty?

          # Resolve hostname to IP if needed
          begin
            ip_addr = IPAddr.new(host)
          rescue IPAddr::InvalidAddressError
            # If it's a hostname, resolve it to IP
            begin
              resolved_ips = Addrinfo.getaddrinfo(host, nil, nil, :STREAM)
              # Check all resolved IPs - if any are blocked, reject the request
              resolved_ips.each do |addr_info|
                ip_addr = IPAddr.new(addr_info.ip_address)
                safe_result = safe_ip(ip_addr)
                unless safe_result[:success]
                  return {
                    error: "Host '#{host}' resolves to blocked IP address #{ip_addr}: #{safe_result[:error]}",
                    success: false
                  }
                end
              end
              return { success: true }
            rescue SocketError
              return { error: "Unable to resolve hostname: #{host}", success: false }
            end
          end

          safe_result = safe_ip(ip_addr)
          unless safe_result[:success]
            return {
              error: "IP address #{ip_addr} is blocked: #{safe_result[:error]}",
              success: false
            }
          end

          { success: true }
        end

        def safe_ip(ip_addr)
          # Block private IP ranges (RFC 1918)
          private_ranges = [
            { range: IPAddr.new('10.0.0.0/8'), description: 'private IP range (RFC 1918)' },
            { range: IPAddr.new('172.16.0.0/12'), description: 'private IP range (RFC 1918)' },
            { range: IPAddr.new('192.168.0.0/16'), description: 'private IP range (RFC 1918)' }
          ]

          # Block loopback addresses
          loopback_ranges = [
            { range: IPAddr.new('127.0.0.0/8'), description: 'loopback address' },
            { range: IPAddr.new('::1/128'), description: 'IPv6 loopback address' }
          ]

          # Block link-local addresses
          link_local_ranges = [
            { range: IPAddr.new('169.254.0.0/16'), description: 'link-local address (AWS metadata endpoint)' },
            { range: IPAddr.new('fe80::/10'), description: 'IPv6 link-local address' }
          ]

          # Block broadcast address
          broadcast_ranges = [
            { range: IPAddr.new('255.255.255.255/32'), description: 'broadcast address' }
          ]

          # Check if IP is in any blocked range
          all_blocked_ranges = private_ranges + loopback_ranges + link_local_ranges + broadcast_ranges
          all_blocked_ranges.each do |blocked_range|
            if blocked_range[:range].include?(ip_addr)
              return {
                error: "access to #{blocked_range[:description]} not allowed for security reasons",
                success: false
              }
            end
          end

          { success: true }
        rescue IPAddr::InvalidAddressError
          { error: 'invalid IP address format', success: false }
        end

        def build_http(uri, timeout: 30)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.open_timeout = timeout
          http.read_timeout = timeout
          http
        end

        def add_headers(request, headers)
          # Add default user agent if not provided
          request['User-Agent'] ||= 'Langop-SDK/1.0'

          headers.each do |key, value|
            request[key] = value
          end
        end

        def add_auth(request, auth)
          case auth[:type]
          when :basic
            request.basic_auth(auth[:username], auth[:password])
          when :bearer
            request['Authorization'] = "Bearer #{auth[:token]}"
          when :token
            request['Authorization'] = "Token #{auth[:token]}"
          end
        end

        def execute_request(http, request, follow_redirects: false)
          response = http.request(request)

          # Handle redirects
          if follow_redirects && response.is_a?(Net::HTTPRedirection)
            location = response['location']
            return get(location, headers: request.to_hash, follow_redirects: true)
          end

          # Parse response
          result = {
            status: response.code.to_i,
            headers: response.to_hash,
            body: response.body,
            success: response.is_a?(Net::HTTPSuccess)
          }

          # Try to parse JSON if content-type indicates JSON
          if response['content-type']&.include?('application/json')
            begin
              result[:json] = JSON.parse(response.body)
            rescue JSON::ParserError
              # Body is not valid JSON, leave as string
            end
          end

          result
        rescue StandardError => e
          {
            error: e.message,
            success: false
          }
        end
      end
    end
  end
end
