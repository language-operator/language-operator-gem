# frozen_string_literal: true

module LanguageOperator
  module Dsl
    # Defines authentication configuration for webhooks
    class WebhookAuthentication
      attr_reader :type, :config

      def initialize
        @type = nil
        @config = {}
      end

      # Verify HMAC signature (GitHub/Stripe style)
      # @param header [String] Header name containing the signature
      # @param secret [String] Secret key for HMAC
      # @param algorithm [Symbol] Hash algorithm (:sha1, :sha256, :sha512)
      # @param prefix [String, nil] Optional prefix to strip from signature (e.g., "sha256=")
      def verify_signature(header:, secret:, algorithm: :sha256, prefix: nil)
        if @current_methods
          # Inside any_of/all_of - create child auth object
          auth = WebhookAuthentication.new
          auth.verify_signature(header: header, secret: secret, algorithm: algorithm, prefix: prefix)
          @current_methods << auth
        else
          @type = :signature
          @config[:header] = header
          @config[:secret] = secret
          @config[:algorithm] = algorithm
          @config[:prefix] = prefix
        end
      end

      # Verify API key from header
      # @param header [String] Header name containing the API key
      # @param key [String] Expected API key value
      def verify_api_key(header:, key:)
        if @current_methods
          auth = WebhookAuthentication.new
          auth.verify_api_key(header: header, key: key)
          @current_methods << auth
        else
          @type = :api_key
          @config[:header] = header
          @config[:key] = key
        end
      end

      # Verify bearer token
      # @param token [String] Expected bearer token value
      def verify_bearer_token(token:)
        if @current_methods
          auth = WebhookAuthentication.new
          auth.verify_bearer_token(token: token)
          @current_methods << auth
        else
          @type = :bearer_token
          @config[:token] = token
        end
      end

      # Verify basic auth credentials
      # @param username [String] Expected username
      # @param password [String] Expected password
      def verify_basic_auth(username:, password:)
        if @current_methods
          auth = WebhookAuthentication.new
          auth.verify_basic_auth(username: username, password: password)
          @current_methods << auth
        else
          @type = :basic_auth
          @config[:username] = username
          @config[:password] = password
        end
      end

      # Custom authentication callback
      # @yield [context] Block receives request context hash
      # @yieldreturn [Boolean] true if authenticated, false otherwise
      def verify_custom(&block)
        if @current_methods
          auth = WebhookAuthentication.new
          auth.verify_custom(&block)
          @current_methods << auth
        else
          @type = :custom
          @config[:callback] = block
        end
      end

      # Allow multiple authentication methods (any can succeed)
      def any_of(&block)
        @type = :any_of
        @config[:methods] = []
        @current_methods = @config[:methods]
        instance_eval(&block) if block
        @current_methods = nil
        # Restore type in case it was overwritten by method calls
        @type = :any_of
      end

      # Allow multiple authentication methods (all must succeed)
      def all_of(&block)
        @type = :all_of
        @config[:methods] = []
        @current_methods = @config[:methods]
        instance_eval(&block) if block
        @current_methods = nil
        # Restore type in case it was overwritten by method calls
        @type = :all_of
      end
    end
  end
end
