# frozen_string_literal: true

require_relative 'webhook_authentication'

module LanguageOperator
  module Dsl
    # Webhook Definition
    #
    # Defines webhook endpoints for reactive agents.
    #
    # @example Define a webhook with authentication
    #   webhook "/github/pr-opened" do
    #     method :post
    #     authenticate do
    #       verify_signature header: "X-Hub-Signature-256",
    #                        secret: ENV['GITHUB_WEBHOOK_SECRET'],
    #                        algorithm: :sha256,
    #                        prefix: "sha256="
    #     end
    #     on_request do |context|
    #       # Handle the webhook
    #     end
    #   end
    class WebhookDefinition
      attr_reader :path, :http_method, :handler, :authentication, :validations

      # Initialize webhook definition
      #
      # @param path [String] URL path for the webhook
      def initialize(path)
        @path = path
        @http_method = :post
        @handler = nil
        @authentication = nil
        @validations = []
      end

      # Set HTTP method
      #
      # @param method_name [Symbol] HTTP method (:get, :post, :put, :delete, :patch)
      # @return [void]
      def method(method_name)
        @http_method = method_name
      end

      # Define authentication for this webhook
      #
      # @yield Authentication configuration block
      # @return [void]
      def authenticate(&block)
        @authentication = WebhookAuthentication.new
        @authentication.instance_eval(&block) if block
      end

      # Require specific headers
      #
      # @param headers [Hash] Required headers and their expected values (nil = just check presence)
      # @return [void]
      def require_headers(headers)
        @validations << { type: :headers, config: headers }
      end

      # Require specific content type
      #
      # @param content_type [String, Array<String>] Allowed content type(s)
      # @return [void]
      def require_content_type(*content_types)
        @validations << { type: :content_type, config: content_types.flatten }
      end

      # Add custom validation
      #
      # @yield [context] Validation block
      # @yieldreturn [Boolean, String] true if valid, or error message string if invalid
      # @return [void]
      def validate(&block)
        @validations << { type: :custom, config: block }
      end

      # Define the request handler
      #
      # @yield [context] Request handler block
      # @yieldparam context [Hash] Request context with :path, :method, :headers, :params, :body
      # @return [void]
      def on_request(&block)
        @handler = block
      end

      # Register this webhook with a web server
      #
      # @param web_server [LanguageOperator::Agent::WebServer] Web server instance
      # @return [void]
      def register(web_server)
        return unless @handler

        web_server.register_route(
          @path,
          method: @http_method,
          authentication: @authentication,
          validations: @validations,
          &@handler
        )
      end
    end
  end
end
