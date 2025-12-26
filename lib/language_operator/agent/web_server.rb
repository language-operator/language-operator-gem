# frozen_string_literal: true

require 'rack'
require 'rackup'
require 'mcp'
require 'fileutils'
require 'securerandom'
require_relative 'executor'
require_relative 'prompt_builder'

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
        @mcp_server = nil
        @mcp_transport = nil
        @execution_state = nil # Initialized when register_execute_endpoint called

        # Initialize executor pool to prevent MCP connection leaks
        @executor_pool_size = ENV.fetch('EXECUTOR_POOL_SIZE', '4').to_i
        @executor_pool = setup_executor_pool

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
      # Sets up OpenAI-compatible chat completion endpoint for all agents.
      # Every agent automatically gets identity-aware chat capabilities.
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      # @return [void]
      def register_chat_endpoint(agent)
        @chat_agent = agent

        # Create simple chat configuration (identity awareness always enabled)
        @chat_config = {
          model_name: ENV.fetch('AGENT_NAME', agent.config&.dig('agent', 'name') || 'agent'),
          system_prompt: build_default_system_prompt(agent),
          temperature: 0.7,
          max_tokens: 2000
        }

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
                id: @chat_config[:model_name],
                object: 'model',
                created: Time.now.to_i,
                owned_by: 'language-operator',
                permission: [],
                root: @chat_config[:model_name],
                parent: nil
              }
            ]
          }
        end

        puts "Registered identity-aware chat endpoint as model: #{@chat_config[:model_name]}"
      end

      # Register execution trigger endpoint
      #
      # Enables scheduled/reactive agents to execute tasks via HTTP POST.
      # Prevents concurrent executions via ExecutionState.
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      # @param agent_def [LanguageOperator::Dsl::AgentDefinition, nil] Optional agent definition
      # @return [void]
      def register_execute_endpoint(agent, agent_def = nil)
        require_relative 'execution_state'

        @execute_agent = agent
        @execute_agent_def = agent_def
        @execution_state = LanguageOperator::Agent::ExecutionState.new

        register_route('/api/v1/execute', method: :post) do |context|
          handle_execute_request(context)
        end

        puts 'Registered /api/v1/execute endpoint for triggered execution'
      end

      # Register workspace file management endpoints
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      def register_workspace_endpoints(agent)
        return unless agent.workspace_available?

        @workspace_agent = agent
        @workspace_path = agent.workspace_path

        # List directory contents
        register_route('/api/v1/workspace/files', method: :get) do |context|
          handle_workspace_list(context)
        end

        # View file contents
        register_route('/api/v1/workspace/files/view', method: :get) do |context|
          handle_workspace_view(context)
        end

        # Upload file
        register_route('/api/v1/workspace/files', method: :post) do |context|
          handle_workspace_upload(context)
        end

        # Delete file
        register_route('/api/v1/workspace/files', method: :delete) do |context|
          handle_workspace_delete(context)
        end

        # Download file/directory
        register_route('/api/v1/workspace/files/download', method: :get) do |context|
          handle_workspace_download(context)
        end

        puts 'Registered /api/v1/workspace/* endpoints for file management'
      end

      # Workspace file management handlers

      # Handle GET /api/v1/workspace/files - list directory contents
      def handle_workspace_list(context)
        request = context[:request]
        path = request.params['path'] || '/'

        # Sanitize path to prevent directory traversal
        safe_path = sanitize_workspace_path(path)
        full_path = File.join(@workspace_path, safe_path)

        return workspace_error_response(404, 'NotFound', "Path not found: #{path}") unless File.exist?(full_path)

        if File.directory?(full_path)
          list_directory_contents(full_path, path)
        else
          # If it's a file, return file info
          get_file_info(full_path, path)
        end
      rescue StandardError => e
        workspace_error_response(500, 'InternalError', e.message)
      end

      # Handle GET /api/v1/workspace/files/view - view file contents
      def handle_workspace_view(context)
        request = context[:request]
        path = request.params['path']

        return workspace_error_response(400, 'BadRequest', 'path parameter required') unless path

        # Sanitize path to prevent directory traversal
        safe_path = sanitize_workspace_path(path)
        full_path = File.join(@workspace_path, safe_path)

        return workspace_error_response(404, 'NotFound', "File not found: #{path}") unless File.exist?(full_path)

        return workspace_error_response(400, 'BadRequest', "Path is not a file: #{path}") unless File.file?(full_path)

        # Check file size (limit to 10MB for API responses)
        file_size = File.size(full_path)
        return workspace_error_response(413, 'FileTooLarge', 'File too large for viewing (max 10MB)') if file_size > 10 * 1024 * 1024

        # Read file contents
        contents = File.read(full_path)

        {
          status: 200,
          body: {
            path: path,
            size: file_size,
            contents: contents
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      rescue StandardError => e
        workspace_error_response(500, 'InternalError', e.message)
      end

      # Handle POST /api/v1/workspace/files - upload file
      def handle_workspace_upload(context)
        request = context[:request]
        
        # Parse multipart form data
        if request.content_type&.start_with?('multipart/form-data')
          boundary = request.content_type.split('boundary=')[1]
          return workspace_error_response(400, 'BadRequest', 'Missing boundary in multipart data') unless boundary

          # Parse the multipart data
          body = request.body.read
          parts = parse_multipart(body, boundary)
          
          file_part = parts.find { |part| part[:name] == 'file' }
          path_param = parts.find { |part| part[:name] == 'path' }&.dig(:content)
          
          return workspace_error_response(400, 'BadRequest', 'file parameter required') unless file_part
          return workspace_error_response(400, 'BadRequest', 'path parameter required') unless path_param

          # Sanitize path to prevent directory traversal
          safe_path = sanitize_workspace_path(path_param)
          full_path = File.join(@workspace_path, safe_path)

          # Check file size (limit to 100MB)
          content = file_part[:content]
          return workspace_error_response(413, 'FileTooLarge', 'File too large (max 100MB)') if content.bytesize > 100 * 1024 * 1024

          # Create directory if it doesn't exist
          FileUtils.mkdir_p(File.dirname(full_path))

          # Write file
          File.binwrite(full_path, content)

          {
            status: 201,
            body: {
              message: 'File uploaded successfully',
              path: path_param,
              size: content.bytesize
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          }
        else
          workspace_error_response(400, 'BadRequest', 'Expected multipart/form-data')
        end
      rescue StandardError => e
        workspace_error_response(500, 'UploadError', "Upload failed: #{e.message}")
      end

      # Handle DELETE /api/v1/workspace/files - delete file
      def handle_workspace_delete(context)
        request = context[:request]
        path = request.params['path']

        return workspace_error_response(400, 'BadRequest', 'path parameter required') unless path

        # Sanitize path to prevent directory traversal
        safe_path = sanitize_workspace_path(path)
        full_path = File.join(@workspace_path, safe_path)

        return workspace_error_response(404, 'NotFound', "File not found: #{path}") unless File.exist?(full_path)

        # Delete file or directory
        if File.directory?(full_path)
          FileUtils.rm_rf(full_path)
        else
          File.delete(full_path)
        end

        {
          status: 200,
          body: {
            message: 'File deleted successfully',
            path: path
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      rescue StandardError => e
        workspace_error_response(500, 'DeleteError', "Deletion failed: #{e.message}")
      end

      # Handle GET /api/v1/workspace/files/download - download file or directory as tar.gz
      def handle_workspace_download(context)
        request = context[:request]
        path = request.params['path']

        return workspace_error_response(400, 'BadRequest', 'path parameter required') unless path

        # Sanitize path to prevent directory traversal
        safe_path = sanitize_workspace_path(path)
        full_path = File.join(@workspace_path, safe_path)

        return workspace_error_response(404, 'NotFound', "Path not found: #{path}") unless File.exist?(full_path)

        if File.file?(full_path)
          # Single file download
          content = File.binread(full_path)
          filename = File.basename(full_path)
          
          {
            status: 200,
            body: content,
            headers: {
              'Content-Type' => 'application/octet-stream',
              'Content-Disposition' => "attachment; filename=\"#{filename}\""
            }
          }
        else
          # Directory download as tar.gz
          require 'tempfile'
          require 'zlib'
          require 'rubygems/package'

          Tempfile.create(['workspace', '.tar.gz']) do |temp_file|
            Zlib::GzipWriter.open(temp_file.path) do |gz|
              Gem::Package::TarWriter.new(gz) do |tar|
                add_directory_to_tar(tar, full_path, safe_path)
              end
            end

            content = File.binread(temp_file.path)
            filename = "#{File.basename(path)}.tar.gz"

            {
              status: 200,
              body: content,
              headers: {
                'Content-Type' => 'application/gzip',
                'Content-Disposition' => "attachment; filename=\"#{filename}\""
              }
            }
          end
        end
      rescue StandardError => e
        workspace_error_response(500, 'DownloadError', "Download failed: #{e.message}")
      end

      # Workspace helper methods

      # Sanitize workspace path to prevent directory traversal attacks
      def sanitize_workspace_path(path)
        # Remove leading slash and resolve relative paths
        clean_path = path.sub(%r{^/+}, '')

        # Resolve and normalize the path
        normalized = File.expand_path(clean_path, '/')

        # Ensure it doesn't escape the root
        return '' if normalized == '/' || !normalized.start_with?('/')

        # Remove leading slash for joining with workspace_path
        normalized[1..]
      end

      # List directory contents
      def list_directory_contents(full_path, requested_path)
        entries = Dir.entries(full_path).reject { |entry| entry.start_with?('.') }

        files = entries.map do |entry|
          entry_path = File.join(full_path, entry)
          {
            name: entry,
            type: File.directory?(entry_path) ? 'directory' : 'file',
            size: File.file?(entry_path) ? File.size(entry_path) : nil,
            path: File.join(requested_path, entry).sub(%r{^/+}, '')
          }
        end

        {
          status: 200,
          body: {
            path: requested_path,
            files: files
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      end

      # Get file information
      def get_file_info(full_path, requested_path)
        {
          status: 200,
          body: {
            path: requested_path,
            size: File.size(full_path),
            type: 'file'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      end

      # Parse multipart form data
      def parse_multipart(body, boundary)
        parts = []
        boundary = "--#{boundary}"
        sections = body.split(boundary)
        
        sections[1..-2]&.each do |section|
          next if section.strip.empty?
          
          lines = section.split("\r\n")
          content_disposition = lines.find { |line| line.include?('Content-Disposition') }
          next unless content_disposition
          
          name_match = content_disposition.match(/name="([^"]+)"/)
          next unless name_match
          
          name = name_match[1]
          
          # Find empty line separating headers from content
          content_start = lines.index('') 
          next unless content_start
          
          content = lines[(content_start + 1)..-1].join("\r\n")
          content = content[0..-3] if content.end_with?("\r\n") # Remove trailing CRLF
          
          parts << { name: name, content: content }
        end
        
        parts
      end

      # Add directory to tar archive recursively
      def add_directory_to_tar(tar, source_path, archive_path)
        Dir.entries(source_path).each do |entry|
          next if entry.start_with?('.')
          
          full_path = File.join(source_path, entry)
          tar_path = File.join(archive_path, entry)
          
          if File.directory?(full_path)
            tar.mkdir(tar_path, 0755)
            add_directory_to_tar(tar, full_path, tar_path)
          else
            tar.add_file(tar_path, 0644) do |io|
              io.write(File.binread(full_path))
            end
          end
        end
      end

      # Generate workspace error response
      def workspace_error_response(status, error_type, message)
        {
          status: status,
          body: {
            error: error_type,
            message: message
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
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

      # Cleanup executor pool and connections
      #
      # Properly closes all executors in the pool and their MCP connections
      # to prevent resource leaks during server shutdown.
      #
      # @return [void]
      def cleanup
        return unless @executor_pool

        # Drain and cleanup all executors in the pool
        executors_cleaned = 0

        until @executor_pool.empty?
          executor = @executor_pool.pop unless @executor_pool.empty?
          if executor
            executor.cleanup_connections
            executors_cleaned += 1
          end
        end

        puts "Cleaned up #{executors_cleaned} executors from pool"
      end

      private

      # Build default system prompt for agent
      #
      # Creates a basic system prompt based on agent description
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      # @return [String] Default system prompt
      def build_default_system_prompt(agent)
        description = agent.config&.dig('agent', 'instructions') ||
                      agent.config&.dig('agent', 'description') ||
                      'AI assistant'

        if description.downcase.start_with?('you are')
          description
        else
          "You are #{description.downcase}. Provide helpful assistance based on your capabilities."
        end
      end

      # Handle POST /api/v1/execute request
      #
      # @param context [Hash] Request context with :body, :headers, :request
      # @return [Hash] Response data
      def handle_execute_request(context)
        puts "Received execute request: #{context[:body]}"

        # Check for concurrent execution
        if @execution_state.running?
          info = @execution_state.current_info
          puts "Execution already running: #{info}"
          return {
            status: 409,
            body: {
              error: 'ExecutionInProgress',
              message: 'Agent is currently executing a task',
              current_execution: info
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          }
        end

        # Parse request
        request_data = JSON.parse(context[:body] || '{}')
        puts "Parsed request data: #{request_data.inspect}"

        execution_id = "exec-#{SecureRandom.hex(8)}"
        puts "Generated execution ID: #{execution_id}"

        wait_for_completion = request_data.fetch('wait', true)
        puts "Execution details - ID: #{execution_id}, wait: #{wait_for_completion}"

        # Start execution
        puts 'About to start execution state...'
        @execution_state.start_execution(execution_id)
        puts "Started execution state for #{execution_id}"

        if wait_for_completion
          execute_sync(execution_id, request_data['context'])
        else
          execute_async(execution_id, request_data['context'])
        end
      rescue JSON::ParserError
        execute_error_response(400, 'InvalidJSON', 'Request body must be valid JSON')
      rescue LanguageOperator::Agent::ExecutionInProgressError => e
        execute_error_response(409, 'ExecutionInProgress', e.message)
      rescue StandardError => e
        puts "Exception in handle_execute_request: #{e.class}: #{e.message}"
        puts "Exception backtrace: #{e.backtrace.first(5).join('\n')}"
        @execution_state&.fail_execution(e)
        execute_error_response(500, 'ExecutionError', e.message)
      end

      # Execute task synchronously
      #
      # @param execution_id [String] Execution identifier
      # @param context_data [Hash] Additional context data
      # @return [Hash] Response data
      def execute_sync(execution_id, _context_data)
        start_time = Time.now
        puts "Starting execution #{execution_id}"

        # Execute agent main block (convention: all DSL agents have main blocks)
        puts 'About to execute main block...'
        $stdout.flush

        # Test logging capture during execution
        original_stdout = $stdout
        original_stderr = $stderr
        puts "Original stdout: #{original_stdout.class}"
        puts "Original stderr: #{original_stderr.class}"
        $stdout.flush

        result = LanguageOperator::Agent.execute_main_block(@execute_agent, @execute_agent_def)

        puts "Main block execution returned: #{result.inspect}"
        puts "Stdout after execution: #{$stdout.class}"
        puts "Stderr after execution: #{$stderr.class}"
        $stdout.flush

        puts "Execution #{execution_id} completed with result: #{result.inspect}"
        @execution_state.complete_execution(result)

        {
          status: 200,
          body: {
            status: 'completed',
            result: result,
            execution_id: execution_id,
            started_at: start_time.iso8601,
            completed_at: Time.now.iso8601,
            duration_seconds: (Time.now - start_time).round(2)
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      end

      # Execute task asynchronously
      #
      # @param execution_id [String] Execution identifier
      # @param context_data [Hash] Additional context data
      # @return [Hash] Response data
      def execute_async(execution_id, _context_data)
        Thread.new do
          result = LanguageOperator::Agent.execute_main_block(@execute_agent, @execute_agent_def)
          @execution_state.complete_execution(result)
        rescue StandardError => e
          @execution_state.fail_execution(e)
          logger.error('Async execution failed', error: e.message, execution_id: execution_id)
        end

        {
          status: 202,
          body: {
            status: 'accepted',
            execution_id: execution_id,
            message: 'Execution started asynchronously'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      end

      # Generate error response for execute endpoint
      #
      # @param status [Integer] HTTP status code
      # @param error_type [String] Error type identifier
      # @param message [String] Error message
      # @return [Hash] Error response data
      def execute_error_response(status, error_type, message)
        {
          status: status,
          body: {
            error: error_type,
            message: message
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      end

      # Setup executor pool for connection reuse
      #
      # Creates a thread-safe queue pre-populated with executor instances
      # to prevent creating new MCP connections for each webhook request.
      #
      # @return [Queue] Thread-safe executor pool
      def setup_executor_pool
        pool = Queue.new
        @executor_pool_size.times do
          pool << Executor.new(@agent)
        end
        puts "Initialized executor pool with #{@executor_pool_size} executors"
        pool
      end

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
        route_config = { handler: route_config, authentication: nil, validations: [] } if route_config.is_a?(Proc)

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
        # Read body, handling nil case and rewinding for subsequent reads
        body_content = if request.body
                         content = request.body.read
                         request.body.rewind # Reset for subsequent reads by middleware/handlers
                         content
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
      # Uses executor pooling to prevent MCP connection resource leaks.
      # Executors are reused across requests to avoid creating new
      # connections for each webhook request.
      #
      # @param context [Hash] Request context
      # @return [Hash] Response data
      def handle_webhook(context)
        executor = nil
        begin
          # Get executor from pool with timeout
          executor = @executor_pool.pop(timeout: 5)
          result = executor.execute_with_context(
            instruction: 'Process incoming webhook request',
            context: context
          )

          {
            status: 'processed',
            result: result,
            timestamp: Time.now.iso8601
          }
        rescue ThreadError
          # Pool exhausted, create temporary executor as fallback
          temp_executor = Executor.new(@agent)
          begin
            result = temp_executor.execute_with_context(
              instruction: 'Process incoming webhook request',
              context: context
            )

            {
              status: 'processed',
              result: result,
              timestamp: Time.now.iso8601
            }
          ensure
            temp_executor.cleanup_connections
          end
        ensure
          # Return executor to pool if we got one
          @executor_pool.push(executor) if executor
        end
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
        return error_response(StandardError.new('Chat endpoint not configured')) unless @chat_config

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

        # Execute agent using the correct method
        result = @chat_agent.execute_goal(prompt)

        # Extract content from result (handle both String and Message objects)
        result_content = result.is_a?(String) ? result : result.content

        # Build OpenAI-compatible response
        {
          id: "chatcmpl-#{SecureRandom.hex(12)}",
          object: 'chat.completion',
          created: Time.now.to_i,
          model: @chat_config[:model_name],
          choices: [
            {
              index: 0,
              message: {
                role: 'assistant',
                content: result_content
              },
              finish_reason: 'stop'
            }
          ],
          usage: {
            prompt_tokens: estimate_tokens(prompt),
            completion_tokens: estimate_tokens(result_content),
            total_tokens: estimate_tokens(prompt) + estimate_tokens(result_content)
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
          StreamingBody.new(@chat_agent, prompt, @chat_config[:model_name])
        ]
      end

      # Build prompt from OpenAI message format with identity awareness
      #
      # @param messages [Array<Hash>] Array of message objects
      # @return [String] Combined prompt with agent identity context
      def build_prompt_from_messages(messages)
        prompt_parts = []

        # Build identity-aware system prompt (always enabled)
        system_prompt = build_identity_aware_system_prompt
        prompt_parts << "System: #{system_prompt}" if system_prompt

        # Add conversation context (always enabled)
        conversation_context = build_conversation_context
        prompt_parts << conversation_context if conversation_context

        # Add conversation history (skip system messages from original array since we handle them above)
        messages.each do |msg|
          role = msg['role']
          content = msg['content']

          case role
          when 'user'
            prompt_parts << "User: #{content}"
          when 'assistant'
            prompt_parts << "Assistant: #{content}"
            # Skip system messages - we handle them via PromptBuilder
          end
        end

        prompt_parts.join("\n\n")
      end

      # Build identity-aware system prompt using PromptBuilder
      #
      # @return [String] Dynamic system prompt with agent identity
      def build_identity_aware_system_prompt
        # Create prompt builder with identity awareness always enabled
        builder = PromptBuilder.new(
          @chat_agent,
          nil, # No chat config needed
          template: :standard, # Good default
          enable_identity_awareness: true
        )

        builder.build_system_prompt
      rescue StandardError => e
        # Log error and fall back to static prompt
        puts "Warning: Failed to build identity-aware system prompt: #{e.message}"
        @chat_config[:system_prompt]
      end

      # Build conversation context for ongoing chats
      #
      # @return [String, nil] Conversation context
      def build_conversation_context
        builder = PromptBuilder.new(
          @chat_agent,
          nil, # No chat config needed
          enable_identity_awareness: true
        )

        context = builder.build_conversation_context
        context ? "Context: #{context}" : nil
      rescue StandardError => e
        # Log error and continue without context
        puts "Warning: Failed to build conversation context: #{e.message}"
        nil
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
          @closed = false
        end

        def write(data)
          raise IOError, 'closed stream' if @closed

          @buffer.write(data)
        end

        def flush
          @buffer.flush if @buffer.respond_to?(:flush)
        end

        def close
          @closed = true
        end

        def closed?
          @closed
        end

        def sync=(value)
          # No-op for compatibility
        end

        # rubocop:disable Naming/PredicateMethod
        def sync
          true
        end
        # rubocop:enable Naming/PredicateMethod
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
