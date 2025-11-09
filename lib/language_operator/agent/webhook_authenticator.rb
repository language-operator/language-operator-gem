# frozen_string_literal: true

require 'openssl'
require 'base64'

module LanguageOperator
  module Agent
    # Executes webhook authentication checks
    class WebhookAuthenticator
      # Authenticate a webhook request
      #
      # @param authentication [LanguageOperator::Dsl::WebhookAuthentication] Authentication definition
      # @param context [Hash] Request context with :headers, :body, etc.
      # @return [Boolean] true if authenticated, false otherwise
      def self.authenticate(authentication, context)
        return true unless authentication # No authentication required

        case authentication.type
        when :signature
          verify_signature(authentication.config, context)
        when :api_key
          verify_api_key(authentication.config, context)
        when :bearer_token
          verify_bearer_token(authentication.config, context)
        when :basic_auth
          verify_basic_auth(authentication.config, context)
        when :custom
          verify_custom(authentication.config, context)
        when :any_of
          verify_any_of(authentication.config, context)
        when :all_of
          verify_all_of(authentication.config, context)
        else
          false
        end
      end

      # Verify HMAC signature
      def self.verify_signature(config, context)
        header = config[:header]
        secret = config[:secret]
        algorithm = config[:algorithm] || :sha256
        prefix = config[:prefix]

        signature = get_header(context, header)
        return false unless signature

        # Remove prefix if specified (e.g., "sha256=")
        signature = signature.sub(/^#{Regexp.escape(prefix)}/, '') if prefix

        # Compute expected signature
        body = context[:body] || ''
        expected = OpenSSL::HMAC.hexdigest(algorithm.to_s, secret, body)

        # Constant-time comparison to prevent timing attacks
        secure_compare(signature, expected)
      end

      # Verify API key from header
      def self.verify_api_key(config, context)
        header = config[:header]
        expected_key = config[:key]

        actual_key = get_header(context, header)
        return false unless actual_key

        secure_compare(actual_key, expected_key)
      end

      # Verify bearer token
      def self.verify_bearer_token(config, context)
        expected_token = config[:token]

        auth_header = get_header(context, 'Authorization')
        return false unless auth_header

        # Extract token from "Bearer <token>"
        match = auth_header.match(/^Bearer\s+(.+)$/i)
        return false unless match

        actual_token = match[1]
        secure_compare(actual_token, expected_token)
      end

      # Verify basic auth credentials
      def self.verify_basic_auth(config, context)
        expected_username = config[:username]
        expected_password = config[:password]

        auth_header = get_header(context, 'Authorization')
        return false unless auth_header

        # Extract credentials from "Basic <base64>"
        match = auth_header.match(/^Basic\s+(.+)$/i)
        return false unless match

        begin
          credentials = Base64.decode64(match[1])
          username, password = credentials.split(':', 2)

          secure_compare(username, expected_username) &&
            secure_compare(password, expected_password)
        rescue StandardError
          false
        end
      end

      # Verify using custom callback
      def self.verify_custom(config, context)
        callback = config[:callback]
        return false unless callback

        begin
          result = callback.call(context)
          result == true # Explicit true check
        rescue StandardError
          # Silently fail on callback errors for security
          false
        end
      end

      # Verify any of multiple authentication methods
      def self.verify_any_of(config, context)
        methods = config[:methods] || []
        return false if methods.empty?

        methods.any? { |auth| authenticate(auth, context) }
      end

      # Verify all of multiple authentication methods
      def self.verify_all_of(config, context)
        methods = config[:methods] || []
        return false if methods.empty?

        methods.all? { |auth| authenticate(auth, context) }
      end

      # Execute validations
      #
      # @param validations [Array<Hash>] Validation definitions
      # @param context [Hash] Request context
      # @return [Array<String>] Validation errors (empty if valid)
      def self.validate(validations, context)
        errors = []

        validations.each do |validation|
          case validation[:type]
          when :headers
            errors.concat(validate_headers(validation[:config], context))
          when :content_type
            errors.concat(validate_content_type(validation[:config], context))
          when :custom
            result = validation[:config].call(context)
            errors << result unless result == true
          end
        end

        errors.compact
      end

      # Validate required headers
      def self.validate_headers(required_headers, context)
        errors = []
        context[:headers] || {}

        required_headers.each do |header_name, expected_value|
          actual_value = get_header(context, header_name)

          if actual_value.nil?
            errors << "Missing required header: #{header_name}"
          elsif expected_value && actual_value != expected_value
            errors << "Invalid value for header #{header_name}"
          end
        end

        errors
      end

      # Validate content type
      def self.validate_content_type(allowed_types, context)
        content_type = get_header(context, 'Content-Type')
        return ['Missing Content-Type header'] unless content_type

        # Extract media type (ignore charset, boundary, etc.)
        media_type = content_type.split(';').first.strip.downcase

        return [] if allowed_types.any? { |type| media_type == type.downcase }

        ["Invalid Content-Type: expected #{allowed_types.join(' or ')}, got #{media_type}"]
      end

      # Get header value (case-insensitive)
      def self.get_header(context, name)
        headers = context[:headers] || {}
        name_lower = name.downcase

        # Try exact match first
        return headers[name] if headers.key?(name)

        # Try case-insensitive match
        headers.each do |key, value|
          return value if key.downcase == name_lower
        end

        nil
      end

      # Constant-time string comparison to prevent timing attacks
      def self.secure_compare(a, b)
        return false if a.nil? || b.nil?
        return false unless a.bytesize == b.bytesize

        l = a.unpack('C*')
        r = b.unpack('C*')

        res = 0
        l.zip(r) { |x, y| res |= x ^ y }
        res.zero?
      end

      private_class_method :verify_signature, :verify_api_key, :verify_bearer_token,
                           :verify_basic_auth, :verify_custom, :verify_any_of, :verify_all_of,
                           :validate_headers, :validate_content_type, :get_header, :secure_compare
    end
  end
end
