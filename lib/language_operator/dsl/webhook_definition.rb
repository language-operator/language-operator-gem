# frozen_string_literal: true

module LanguageOperator
  module Dsl
    # Webhook Definition
    #
    # Defines webhook endpoints for reactive agents.
    #
    # @example Define a webhook
    #   webhook "/github/pr-opened" do
    #     method :post
    #     on_request do |context|
    #       # Handle the webhook
    #     end
    #   end
    class WebhookDefinition
      attr_reader :path, :http_method, :handler

      # Initialize webhook definition
      #
      # @param path [String] URL path for the webhook
      def initialize(path)
        @path = path
        @http_method = :post
        @handler = nil
      end

      # Set HTTP method
      #
      # @param method_name [Symbol] HTTP method (:get, :post, :put, :delete, :patch)
      # @return [void]
      def method(method_name)
        @http_method = method_name
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

        web_server.register_route(@path, method: @http_method, &@handler)
      end
    end
  end
end
