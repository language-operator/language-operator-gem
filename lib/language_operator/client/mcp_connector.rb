# frozen_string_literal: true

module LanguageOperator
  module Client
    # Handles MCP server connection logic
    module MCPConnector
      private

      # Connect to all enabled MCP servers
      #
      # @return [void]
      def connect_mcp_servers
        enabled_servers = (@config['mcp_servers'] || []).select { |s| s['enabled'] }

        if enabled_servers.empty?
          logger.info('No MCP servers configured, agent will run without tools')
        else
          logger.info('Connecting to MCP servers', count: enabled_servers.length)

          enabled_servers.each do |server_config|
            client = connect_with_retry(server_config)
            next unless client

            @clients << client
            tool_count = client.tools.length

            # Debug: inspect tool objects
            if @debug
              logger.debug('MCP tool objects inspection',
                           server: server_config['name'],
                           tools_inspect: client.tools.map { |t| { class: t.class.name, name: t.name, methods: t.methods.grep(/name/) } })
            end

            logger.info('MCP server connected',
                        server: server_config['name'],
                        tool_count: tool_count,
                        tools: client.tools.map(&:name))
          rescue StandardError => e
            logger.error('Error connecting to MCP server',
                         server: server_config['name'],
                         error: e.message)
            if @debug
              logger.debug('Connection error backtrace',
                           server: server_config['name'],
                           backtrace: e.backtrace.join("\n"))
            end
          end

          logger.info('MCP connection summary',
                      connected_servers: @clients.length)
        end

        # Create chat with all collected tools (even if empty)
        # Use the tools() method which applies OpenTelemetry instrumentation wrapping
        llm_config = @config['llm']
        chat_params = build_chat_params(llm_config)
        @chat = RubyLLM.chat(**chat_params)

        all_tools = tools
        @chat.with_tools(*all_tools) unless all_tools.empty?

        # Set up callbacks to log tool invocations
        setup_tool_callbacks

        logger.info('Chat session initialized', with_tools: !all_tools.empty?, total_tools: all_tools.length)
      end

      # Connect to MCP server with exponential backoff retry logic
      #
      # @param server_config [Hash] Server configuration
      # @return [RubyLLM::MCP::Client, nil] Client if successful, nil if all retries failed
      def connect_with_retry(server_config)
        logger.debug('Attempting to connect to MCP server',
                     server: server_config['name'],
                     transport: server_config['transport'],
                     url: server_config['url'])

        with_retry_or_nil(
          max_attempts: 4, # 1 initial attempt + 3 retries
          base_delay: 1.0,
          max_delay: 30.0,
          on_retry: lambda { |error, attempt, delay|
            logger.warn('MCP server connection failed, retrying',
                        server: server_config['name'],
                        attempt: attempt,
                        max_attempts: 4,
                        error: error.message,
                        retry_delay: delay)
          },
          on_failure: lambda { |error, attempts|
            logger.error('MCP server connection failed after all retries',
                         server: server_config['name'],
                         attempts: attempts,
                         error: error.message)
            if @debug
              logger.debug('Final connection error backtrace',
                           server: server_config['name'],
                           backtrace: error.backtrace.join("\n"))
            end
          }
        ) do
          client = RubyLLM::MCP.client(
            name: server_config['name'],
            transport_type: server_config['transport'].to_sym,
            config: {
              url: server_config['url']
            }
          )

          logger.info('Successfully connected to MCP server',
                      server: server_config['name'])
          client
        end
      end

      # Build chat parameters based on LLM config
      #
      # @param llm_config [Hash] LLM configuration
      # @return [Hash] Chat parameters for RubyLLM.chat
      def build_chat_params(llm_config)
        chat_params = { model: llm_config['model'] }
        if llm_config['provider'] == 'openai_compatible'
          chat_params[:provider] = :openai
          chat_params[:assume_model_exists] = true
        end

        chat_params
      end

      # Set up callbacks to log tool calls and results
      #
      # @return [void]
      def setup_tool_callbacks
        @chat.on_tool_call do |tool_call|
          logger.info('Tool call initiated by LLM',
                      event: 'tool_call_initiated',
                      tool_name: tool_call.name,
                      tool_id: tool_call.id,
                      arguments: tool_call.arguments,
                      arguments_json: tool_call.arguments.to_json)
        end

        @chat.on_tool_result do |result|
          logger.info('Tool call result received',
                      event: 'tool_result_received',
                      result: result,
                      result_preview: result.to_s[0..500])
        end
      end
    end
  end
end
