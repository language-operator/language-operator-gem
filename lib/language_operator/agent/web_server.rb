# frozen_string_literal: true

require 'rack'
require 'rackup'
require 'mcp'

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
        @mcp_server = nil
        @mcp_transport = nil

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
      # @param authentication [LanguageOperator::Dsl::WebhookAuthentication, nil] Authentication configuration
      # @param validations [Array<Hash>, nil] Validation rules
      # @param handler [Proc] Request handler block
      # @return [void]
      def register_route(path, method: :post, authentication: nil, validations: nil, &handler)
        @routes[normalize_route_key(path, method)] = {
          handler: handler,
          authentication: authentication,
          validations: validations || []
        }
      end

      # Check if a route exists
      #
      # @param path [String] The URL path
      # @param method [Symbol] HTTP method
      # @return [Boolean]
      def route_exists?(path, method)
        @routes.key?(normalize_route_key(path, method))
      end

      # Register MCP tools
      #
      # Sets up MCP protocol endpoints for tool discovery and execution.
      # Tools defined in the agent will be exposed via MCP protocol.
      #
      # @param mcp_server_def [LanguageOperator::Dsl::McpServerDefinition] MCP server definition
      # @return [void]
      def register_mcp_tools(mcp_server_def)
        require_relative '../dsl/adapter'

        # Convert tool definitions to MCP::Tool classes
        mcp_tools = mcp_server_def.all_tools.map do |tool_def|
          Dsl::Adapter.tool_definition_to_mcp_tool(tool_def)
        end

        # Create MCP server
        @mcp_server = MCP::Server.new(
          name: mcp_server_def.server_name,
          version: LanguageOperator::VERSION,
          tools: mcp_tools
        )

        # Create the Streamable HTTP transport
        @mcp_transport = MCP::Server::Transports::StreamableHTTPTransport.new(@mcp_server)
        @mcp_server.transport = @mcp_transport

        # Register MCP endpoint
        register_route('/mcp', method: :post) do |context|
          handle_mcp_request(context[:request])
        end

        puts "Registered #{mcp_tools.size} MCP tools"
      end

      # Register chat completion endpoint
      #
      # Sets up OpenAI-compatible chat completion endpoint.
      # Agents can be used as drop-in LLM replacements.
      #
      # @param chat_endpoint_def [LanguageOperator::Dsl::ChatEndpointDefinition] Chat endpoint definition
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      # @return [void]
      def register_chat_endpoint(chat_endpoint_def, agent)
        @chat_endpoint = chat_endpoint_def
        @chat_agent = agent

        # Register OpenAI-compatible endpoint
        register_route('/v1/chat/completions', method: :post) do |context|
          handle_chat_completion(context)
        end

        # Also register models endpoint for compatibility
        register_route('/v1/models', method: :get) do |_context|
          {
            object: 'list',
            data: [
              {
                id: chat_endpoint_def.model_name,
                object: 'model',
                created: Time.now.to_i,
                owned_by: 'language-operator',
                permission: [],
                root: chat_endpoint_def.model_name,
                parent: nil
              }
            ]
          }
        end

        puts "Registered chat completion endpoint as model: #{chat_endpoint_def.model_name}"
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
        route_config = @routes[route_key]

        if route_config
          execute_handler(route_config, request)
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
      # @param route_config [Hash, Proc] Route configuration or legacy handler proc
      # @param request [Rack::Request] The request
      # @return [Array] Rack response
      def execute_handler(route_config, request)
        require_relative 'webhook_authenticator'

        # Support legacy handler-only format
        if route_config.is_a?(Proc)
          route_config = { handler: route_config, authentication: nil, validations: [] }
        end

        handler = route_config[:handler]
        authentication = route_config[:authentication]
        validations = route_config[:validations]

        # Build request context
        context = build_request_context(request)

        # Perform authentication
        if authentication
          authenticated = WebhookAuthenticator.authenticate(authentication, context)
          unless authenticated
            return [
              401,
              { 'Content-Type' => 'application/json' },
              [JSON.generate({ error: 'Unauthorized', message: 'Authentication failed' })]
            ]
          end
        end

        # Perform validations
        unless validations.empty?
          validation_errors = WebhookAuthenticator.validate(validations, context)
          unless validation_errors.empty?
            return [
              400,
              { 'Content-Type' => 'application/json' },
              [JSON.generate({ error: 'Bad Request', message: 'Validation failed', errors: validation_errors })]
            ]
          end
        end

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
            # Strip HTTP_ prefix and normalize
            header_name = key[5..].split('_').map(&:capitalize).join('-')
            headers[header_name] = value
          # Also include standard CGI headers like CONTENT_TYPE, CONTENT_LENGTH
          # But only if not already set by HTTP_ version (HTTP_CONTENT_TYPE takes precedence)
          elsif %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
            header_name = key.split('_').map(&:capitalize).join('-')
            headers[header_name] ||= value # Only set if not already present
          # In test environment (Rack::Test), headers may come through as-is
          elsif key.include?('-') || key.start_with?('X-', 'Authorization')
            headers[key] = value
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

      # Handle MCP protocol request
      #
      # @param request [Rack::Request] The request
      # @return [Hash] Response data (will be converted to Rack response by transport)
      def handle_mcp_request(request)
        return { error: 'MCP server not initialized' } unless @mcp_transport

        # The transport handles the MCP protocol
        @mcp_transport.handle_request(request)
      end

      # Handle chat completion request
      #
      # @param context [Hash] Request context
      # @return [Array, Hash] Rack response or hash for streaming
      def handle_chat_completion(context)
        return error_response(StandardError.new('Chat endpoint not configured')) unless @chat_endpoint

        # Parse request body
        request_data = JSON.parse(context[:body])

        # Check if streaming is requested
        if request_data['stream']
          handle_streaming_chat(request_data, context[:request])
        else
          handle_non_streaming_chat(request_data)
        end
      rescue JSON::ParserError => e
        error_response(StandardError.new("Invalid JSON: #{e.message}"))
      rescue StandardError => e
        error_response(e)
      end

      # Handle non-streaming chat completion
      #
      # @param request_data [Hash] Parsed request data
      # @return [Hash] Chat completion response
      def handle_non_streaming_chat(request_data)
        messages = request_data['messages'] || []

        # Build prompt from messages
        prompt = build_prompt_from_messages(messages)

        # Execute agent
        result = @chat_agent.execute(prompt)

        # Build OpenAI-compatible response
        {
          id: "chatcmpl-#{SecureRandom.hex(12)}",
          object: 'chat.completion',
          created: Time.now.to_i,
          model: @chat_endpoint.model_name,
          choices: [
            {
              index: 0,
              message: {
                role: 'assistant',
                content: result
              },
              finish_reason: 'stop'
            }
          ],
          usage: {
            prompt_tokens: estimate_tokens(prompt),
            completion_tokens: estimate_tokens(result),
            total_tokens: estimate_tokens(prompt) + estimate_tokens(result)
          }
        }
      end

      # Handle streaming chat completion
      #
      # @param request_data [Hash] Parsed request data
      # @param request [Rack::Request] The Rack request
      # @return [Array] Rack streaming response
      def handle_streaming_chat(request_data, _request)
        messages = request_data['messages'] || []
        prompt = build_prompt_from_messages(messages)

        # Return a streaming response
        [
          200,
          {
            'Content-Type' => 'text/event-stream',
            'Cache-Control' => 'no-cache',
            'Connection' => 'keep-alive'
          },
          StreamingBody.new(@chat_agent, prompt, @chat_endpoint.model_name)
        ]
      end

      # Build prompt from OpenAI message format
      #
      # @param messages [Array<Hash>] Array of message objects
      # @return [String] Combined prompt
      def build_prompt_from_messages(messages)
        # Combine all messages into a single prompt
        # System messages become instructions
        # User/assistant messages become conversation
        prompt_parts = []

        # Add system prompt if configured
        prompt_parts << "System: #{@chat_endpoint.system_prompt}" if @chat_endpoint.system_prompt

        # Add conversation history
        messages.each do |msg|
          role = msg['role']
          content = msg['content']

          case role
          when 'system'
            prompt_parts << "System: #{content}"
          when 'user'
            prompt_parts << "User: #{content}"
          when 'assistant'
            prompt_parts << "Assistant: #{content}"
          end
        end

        prompt_parts.join("\n\n")
      end

      # Estimate token count (rough approximation)
      #
      # @param text [String] Text to estimate
      # @return [Integer] Estimated token count
      def estimate_tokens(text)
        # Rough approximation: 1 token ≈ 4 characters
        (text.length / 4.0).ceil
      end

      # Build success response
      #
      # @param data [Hash, String] Response data
      # @return [Array] Rack response
      def success_response(data)
        # If data is already a Rack response tuple, return as-is
        return data if data.is_a?(Array) && data.length == 3 && data[0].is_a?(Integer)

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

    # Streaming body for Server-Sent Events (SSE)
    #
    # Implements the Rack streaming protocol for chat completion responses.
    # Streams agent output as it's generated.
    class StreamingBody
      def initialize(agent, prompt, model_name)
        @agent = agent
        @prompt = prompt
        @model_name = model_name
        @id = "chatcmpl-#{SecureRandom.hex(12)}"
      end

      # Implement each for Rack::Test compatibility
      #
      # @yield [String] Each chunk of data
      # @return [void]
      def each
        buffer = StringIO.new
        stream = MockStream.new(buffer)
        call(stream)
        yield buffer.string
      end

      # Mock stream for testing
      class MockStream
        def initialize(buffer)
          @buffer = buffer
        end

        def write(data)
          @buffer.write(data)
        end

        def close
          # No-op
        end
      end

      # Called by Rack to stream the response
      #
      # @param stream [Object] The stream object
      # @return [void]
      def call(stream)
        # Execute agent and stream response
        result = @agent.execute(@prompt)

        # Send the result as a single chunk (for simplicity)
        # In a real implementation, this could stream token-by-token
        chunk = {
          id: @id,
          object: 'chat.completion.chunk',
          created: Time.now.to_i,
          model: @model_name,
          choices: [
            {
              index: 0,
              delta: {
                role: 'assistant',
                content: result
              },
              finish_reason: nil
            }
          ]
        }

        stream.write("data: #{JSON.generate(chunk)}\n\n")

        # Send final chunk with finish_reason
        final_chunk = {
          id: @id,
          object: 'chat.completion.chunk',
          created: Time.now.to_i,
          model: @model_name,
          choices: [
            {
              index: 0,
              delta: {},
              finish_reason: 'stop'
            }
          ]
        }

        stream.write("data: #{JSON.generate(final_chunk)}\n\n")
        stream.write("data: [DONE]\n\n")
      rescue StandardError => e
        error_chunk = {
          error: {
            message: e.message,
            type: 'server_error',
            code: nil
          }
        }
        stream.write("data: #{JSON.generate(error_chunk)}\n\n")
      ensure
        stream.close
      end
    end
  end
end
