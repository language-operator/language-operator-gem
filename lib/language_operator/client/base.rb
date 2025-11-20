# frozen_string_literal: true

require 'ruby_llm'
require 'ruby_llm/mcp'
require 'json'
require_relative 'config'
require_relative 'cost_calculator'
require_relative 'mcp_connector'
require_relative '../logger'
require_relative '../loggable'
require_relative '../retryable'
require_relative '../agent/instrumentation'

module LanguageOperator
  module Client
    # Core MCP client that connects to multiple servers and manages LLM chat
    #
    # This class handles all the backend logic for connecting to MCP servers,
    # configuring the LLM, and managing chat sessions. It's designed to be
    # UI-agnostic and reusable across different interfaces (CLI, web, headless).
    #
    # @example Basic usage
    #   config = Config.load('config.yaml')
    #   client = Base.new(config)
    #   client.connect!
    #   response = client.send_message("What tools are available?")
    #
    # @example Streaming responses
    #   client.stream_message("Search for Ruby news") do |chunk|
    #     print chunk
    #   end
    class Base
      include LanguageOperator::Loggable
      include LanguageOperator::Retryable
      include LanguageOperator::Agent::Instrumentation
      include CostCalculator
      include MCPConnector

      attr_reader :config, :clients, :chat

      # Initialize the client with configuration
      #
      # @param config [Hash, String] Configuration hash or path to YAML file
      def initialize(config)
        @config = config.is_a?(String) ? Config.load(config) : config
        @clients = []
        @chat = nil
        @debug = @config['debug'] || false

        logger.debug('Client initialized',
                     debug: @debug,
                     llm_provider: @config.dig('llm', 'provider'),
                     llm_model: @config.dig('llm', 'model'))
      end

      # Connect to all enabled MCP servers and configure LLM
      #
      # @return [Hash] Connection results with status and tool counts
      # @raise [RuntimeError] If LLM configuration fails
      def connect!
        configure_llm
        connect_mcp_servers
      end

      # Send a message and get the full response
      #
      # @param message [String] User message
      # @return [String] Assistant response
      # @raise [StandardError] If message fails
      def send_message(message)
        raise 'Not connected. Call #connect! first.' unless @chat

        model = @config.dig('llm', 'model')
        provider = @config.dig('llm', 'provider')

        with_span('agent.llm.request', attributes: {
                    'llm.model' => model,
                    'llm.provider' => provider,
                    'llm.message_count' => @chat.respond_to?(:messages) ? @chat.messages.length : nil
                  }) do |span|
          result = @chat.ask(message)

          # Add token usage and cost attributes if available
          if result.respond_to?(:input_tokens)
            input_tokens = result.input_tokens || 0
            output_tokens = result.output_tokens || 0
            cost = calculate_cost(model, input_tokens, output_tokens)

            span.set_attribute('llm.input_tokens', input_tokens)
            span.set_attribute('llm.output_tokens', output_tokens)
            span.set_attribute('llm.cost_usd', cost.round(6)) if cost
          end

          result
        end
      end

      # Stream a message and yield each chunk
      #
      # @param message [String] User message
      # @yield [String] Each chunk of the response
      # @raise [StandardError] If streaming fails
      def stream_message(message, &block)
        raise 'Not connected. Call #connect! first.' unless @chat

        # NOTE: RubyLLM may not support streaming yet, so we'll call ask and yield the full response
        response = @chat.ask(message)

        # Convert response to string if it's a RubyLLM::Message object
        response_text = response.respond_to?(:content) ? response.content : response.to_s

        block.call(response_text) if block_given?
        response_text
      end

      # Get all available tools from connected servers
      #
      # Wraps MCP tools with OpenTelemetry instrumentation to trace tool executions.
      #
      # @return [Array] Array of instrumented tool objects
      def tools
        raw_tools = @clients.flat_map(&:tools)

        # Wrap each tool with instrumentation if telemetry is enabled
        if ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', nil)
          raw_tools.map { |tool| wrap_tool_with_instrumentation(tool) }
        else
          raw_tools
        end
      end

      # Get information about connected servers
      #
      # @return [Array<Hash>] Server information (name, url, tool_count)
      def servers_info
        @clients.map do |client|
          {
            name: client.name,
            tool_count: client.tools.length,
            tools: client.tools.map(&:name)
          }
        end
      end

      # Clear chat history while keeping MCP connections
      #
      # @return [void]
      def clear_history!
        llm_config = @config['llm']
        chat_params = build_chat_params(llm_config)
        @chat = RubyLLM.chat(**chat_params)

        all_tools = tools
        @chat.with_tools(*all_tools) unless all_tools.empty?
      end

      # Check if the client is connected
      #
      # @return [Boolean] True if connected to at least one server
      def connected?
        !@clients.empty? && !@chat.nil?
      end

      # Get debug mode status
      #
      # @return [Boolean] True if debug mode is enabled
      def debug?
        @debug
      end

      private

      def logger_component
        'Client'
      end

      # Wrap an MCP tool with OpenTelemetry instrumentation
      #
      # Creates a wrapper that traces tool executions with proper semantic conventions.
      # The wrapper preserves the original tool's interface while adding telemetry.
      #
      # @param tool [Object] Original MCP tool object
      # @return [Object] Instrumented tool wrapper
      def wrap_tool_with_instrumentation(tool)
        # Create a new tool object that wraps the original
        tool_wrapper = Object.new
        tool_wrapper.define_singleton_method(:name) { tool.name }
        tool_wrapper.define_singleton_method(:description) { tool.description }
        tool_wrapper.define_singleton_method(:parameters) { tool.parameters }
        tool_wrapper.define_singleton_method(:params_schema) { tool.params_schema }
        tool_wrapper.define_singleton_method(:provider_params) { tool.provider_params }

        # Wrap the call method with instrumentation
        original_tool = tool
        tool_wrapper.define_singleton_method(:call) do |arguments|
          tracer = OpenTelemetry.tracer_provider.tracer('language-operator')

          tool_name = original_tool.name

          tracer.in_span("execute_tool.#{tool_name}", attributes: {
                           'gen_ai.operation.name' => 'execute_tool',
                           'gen_ai.tool.name' => tool_name,
                           'gen_ai.tool.call.arguments.size' => arguments.to_json.bytesize
                         }) do |span|
            # Execute the original tool
            result = original_tool.call(arguments)

            # Record the result size
            result_str = result.is_a?(String) ? result : result.to_json
            span.set_attribute('gen_ai.tool.call.result.size', result_str.bytesize)

            result
          rescue StandardError => e
            span.record_exception(e)
            span.status = OpenTelemetry::Trace::Status.error("Tool execution failed: #{e.message}")
            raise
          end
        end

        tool_wrapper
      end

      # Configure RubyLLM with provider settings
      #
      # @raise [RuntimeError] If provider is unknown
      def configure_llm
        llm_config = @config['llm']
        provider = llm_config['provider']
        model = llm_config['model']
        timeout = llm_config['timeout'] || 300

        logger.info('Configuring LLM',
                    provider: provider,
                    model: model,
                    timeout: timeout)

        logger.debug('Using custom endpoint', endpoint: llm_config['endpoint']) if provider == 'openai_compatible' && llm_config['endpoint']

        RubyLLM.configure do |config|
          case provider
          when 'openai'
            config.openai_api_key = llm_config['api_key']
          when 'openai_compatible'
            config.openai_api_key = llm_config['api_key'] || 'not-needed'
            config.openai_api_base = llm_config['endpoint']
          when 'anthropic'
            config.anthropic_api_key = llm_config['api_key']
          else
            logger.error('Unknown LLM provider', provider: provider)
            raise "Unknown provider: #{provider}"
          end

          # Set timeout for LLM inference (default 300 seconds for slow local models)
          # RubyLLM uses request_timeout to control HTTP request timeouts
          config.request_timeout = timeout if config.respond_to?(:request_timeout=)
        end

        # Configure MCP timeout separately (MCP has its own timeout setting)
        # MCP request_timeout is in milliseconds, default is 300000ms (5 minutes)
        RubyLLM::MCP.configure do |config|
          mcp_timeout_ms = timeout * 1000
          config.request_timeout = mcp_timeout_ms if config.respond_to?(:request_timeout=)
        end

        logger.info('LLM configuration complete')
      end
    end
  end
end
