# frozen_string_literal: true

require 'rack'
require 'rackup'

module LanguageOperator
  module Agent
    # Web Server for Reactive Agents
    #
    # Enables agents to receive HTTP requests (webhooks, API calls) and respond
    # to them. Agents in :reactive mode run an HTTP server that listens for
    # incoming requests and triggers agent execution.
    #
    # @example Starting a web server for an agent
    #   server = LanguageOperator::Agent::WebServer.new(agent)
    #   server.start
    class WebServer
      attr_reader :agent, :port

      # Initialize the web server
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      # @param port [Integer] Port to listen on (default: ENV['PORT'] || 8080)
      def initialize(agent, port: nil)
        @agent = agent
        @port = port || ENV.fetch('PORT', '8080').to_i
        @routes = {}
        @executor = Executor.new(agent)

        setup_default_routes
      end

      # Start the HTTP server
      #
      # @return [void]
      def start
        puts "Starting Agent HTTP server on http://0.0.0.0:#{@port}"
        puts "Agent: #{@agent.class.name}"
        puts 'Mode: reactive'

        # Start the server with Puma
        Rackup::Handler.get('puma').run(rack_app, Port: @port, Host: '0.0.0.0')
      end

      # Register a webhook route
      #
      # @param path [String] The URL path
      # @param method [Symbol] HTTP method (:get, :post, :put, :delete, :patch)
      # @param handler [Proc] Request handler block
      # @return [void]
      def register_route(path, method: :post, &handler)
        @routes[normalize_route_key(path, method)] = handler
      end

      # Check if a route exists
      #
      # @param path [String] The URL path
      # @param method [Symbol] HTTP method
      # @return [Boolean]
      def route_exists?(path, method)
        @routes.key?(normalize_route_key(path, method))
      end

      # Handle incoming HTTP request
      #
      # @param env [Hash] Rack environment
      # @return [Array] Rack response [status, headers, body]
      def handle_request(env)
        request = Rack::Request.new(env)
        path = request.path
        method = request.request_method.downcase.to_sym

        # Try to find a matching route
        route_key = normalize_route_key(path, method)
        handler = @routes[route_key]

        if handler
          execute_handler(handler, request)
        else
          not_found_response(path, method)
        end
      rescue StandardError => e
        error_response(e)
      end

      private

      # Build the Rack application
      #
      # @return [Rack::Builder]
      def rack_app
        server = self

        Rack::Builder.new do
          use Rack::CommonLogger
          use Rack::ShowExceptions
          use Rack::ContentLength

          run ->(env) { server.handle_request(env) }
        end
      end

      # Execute a route handler
      #
      # @param handler [Proc] The handler block
      # @param request [Rack::Request] The request
      # @return [Array] Rack response
      def execute_handler(handler, request)
        # Build request context
        context = build_request_context(request)

        # Execute handler (could be async)
        result = handler.call(context)

        # Build response
        success_response(result)
      end

      # Build request context for handlers
      #
      # @param request [Rack::Request] The request
      # @return [Hash] Request context
      def build_request_context(request)
        # Read body, handling nil case
        body_content = if request.body
                         request.body.read
                       else
                         ''
                       end

        {
          path: request.path,
          method: request.request_method,
          headers: extract_headers(request),
          params: request.params,
          body: body_content,
          request: request
        }
      end

      # Extract relevant headers from request
      #
      # @param request [Rack::Request] The request
      # @return [Hash] Headers hash
      def extract_headers(request)
        headers = {}
        request.each_header do |key, value|
          # Convert HTTP_HEADER_NAME to Header-Name
          if key.start_with?('HTTP_')
            header_name = key[5..].split('_').map(&:capitalize).join('-')
            headers[header_name] = value
          end
        end
        headers
      end

      # Setup default routes
      #
      # @return [void]
      def setup_default_routes
        # Health check endpoint
        register_route('/health', method: :get) do |_context|
          { status: 'healthy', agent: @agent.class.name }
        end

        # Ready check endpoint
        register_route('/ready', method: :get) do |_context|
          {
            status: @agent.workspace_available? ? 'ready' : 'not_ready',
            workspace: @agent.workspace_path
          }
        end

        # Default webhook endpoint (fallback)
        register_route('/webhook', method: :post) do |context|
          handle_webhook(context)
        end
      end

      # Handle webhook request by executing agent
      #
      # @param context [Hash] Request context
      # @return [Hash] Response data
      def handle_webhook(context)
        # Execute agent with webhook context
        result = @executor.execute_with_context(
          instruction: 'Process incoming webhook request',
          context: context
        )

        {
          status: 'processed',
          result: result,
          timestamp: Time.now.iso8601
        }
      end

      # Build success response
      #
      # @param data [Hash, String] Response data
      # @return [Array] Rack response
      def success_response(data)
        body = data.is_a?(Hash) ? JSON.generate(data) : data.to_s

        [
          200,
          { 'Content-Type' => 'application/json' },
          [body]
        ]
      end

      # Build not found response
      #
      # @param path [String] Request path
      # @param method [Symbol] HTTP method
      # @return [Array] Rack response
      def not_found_response(path, method)
        [
          404,
          { 'Content-Type' => 'application/json' },
          [JSON.generate({
                           error: 'Not Found',
                           message: "No route for #{method.upcase} #{path}",
                           available_routes: @routes.keys
                         })]
        ]
      end

      # Build error response
      #
      # @param error [Exception] The error
      # @return [Array] Rack response
      def error_response(error)
        [
          500,
          { 'Content-Type' => 'application/json' },
          [JSON.generate({
                           error: error.class.name,
                           message: error.message,
                           backtrace: error.backtrace&.first(5)
                         })]
        ]
      end

      # Normalize route key for storage/lookup
      #
      # @param path [String] URL path
      # @param method [Symbol] HTTP method
      # @return [String] Normalized key
      def normalize_route_key(path, method)
        "#{method.to_s.upcase} #{path}"
      end
    end
  end
end
