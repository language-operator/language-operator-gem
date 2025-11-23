# frozen_string_literal: true

require_relative '../logger'
require_relative '../loggable'
require_relative 'metrics_tracker'
require_relative 'safety/manager'
require_relative 'instrumentation'

module LanguageOperator
  module Agent
    # Task Executor
    #
    # Handles autonomous task execution with retry logic and error handling.
    #
    # @example
    #   executor = Executor.new(agent)
    #   executor.execute("Complete the task")
    class Executor
      include LanguageOperator::Loggable
      include Instrumentation

      attr_reader :agent, :iteration_count, :metrics_tracker

      # Initialize the executor
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      # @param agent_definition [LanguageOperator::Dsl::AgentDefinition, nil] Optional agent definition
      def initialize(agent, agent_definition: nil)
        @agent = agent
        @agent_definition = agent_definition
        @iteration_count = 0
        @max_iterations = 100
        @show_full_responses = ENV.fetch('SHOW_FULL_RESPONSES', 'false') == 'true'
        @metrics_tracker = MetricsTracker.new

        # Initialize safety manager from agent definition or environment
        @safety_manager = initialize_safety_manager(agent_definition)

        logger.debug('Executor initialized',
                     max_iterations: @max_iterations,
                     show_full_responses: @show_full_responses,
                     workspace: @agent.workspace_path,
                     safety_enabled: @safety_manager&.enabled?)
      end

      # Execute a task with additional context (for webhooks/HTTP requests)
      #
      # @param instruction [String] The instruction to execute
      # @param context [Hash] Additional context (webhook payload, request data, etc.)
      # @return [String] The result
      def execute_with_context(instruction:, context: {})
        # Build enriched instruction with context
        enriched_instruction = build_instruction_with_context(instruction, context)

        # Execute with standard logic
        execute(enriched_instruction)
      end

      # Execute a single task
      #
      # @param task [String] The task to execute
      # @param agent_definition [LanguageOperator::Dsl::AgentDefinition, nil] Optional agent definition (unused in DSL v1)
      # @return [String] The result
      def execute(task, agent_definition: nil)
        with_span('agent.execute_goal', attributes: {
                    'agent.goal_description' => task[0...500]
                  }) do
          @iteration_count += 1

          # Standard instruction-based execution
          logger.info('Starting iteration',
                      iteration: @iteration_count,
                      max_iterations: @max_iterations)
          logger.debug('Prompt', prompt: task[0..200])

          # Safety check before request
          if @safety_manager&.enabled?
            # Estimate cost and tokens (rough estimate)
            estimated_tokens = estimate_tokens(task)
            estimated_cost = estimate_cost(estimated_tokens)

            @safety_manager.check_request!(
              message: task,
              estimated_cost: estimated_cost,
              estimated_tokens: estimated_tokens
            )
          end

          logger.info('LLM request')
          result = logger.timed('LLM response received') do
            @agent.send_message(task)
          end

          # Record metrics
          model_id = @agent.config.dig('llm', 'model')
          @metrics_tracker.record_request(result, model_id) if model_id

          # Safety check after response and record spending
          result_text = result.is_a?(String) ? result : result.content
          metrics = @metrics_tracker.cumulative_stats

          if @safety_manager&.enabled?
            @safety_manager.check_response!(result_text)
            @safety_manager.record_request(
              cost: metrics[:estimatedCost],
              tokens: metrics[:totalTokens]
            )
          end

          # Capture thinking blocks before stripping (for observability)
          thinking_blocks = result_text.scan(%r{\[THINK\](.*?)\[/THINK\]}m).flatten
          if thinking_blocks.any?
            logger.info('LLM thinking captured',
                        event: 'llm_thinking',
                        iteration: @iteration_count,
                        thinking_steps: thinking_blocks.length,
                        thinking: thinking_blocks,
                        thinking_preview: thinking_blocks.first&.[](0..500))
          end

          # Log the actual LLM response content (strip [THINK] blocks)
          cleaned_response = result_text.gsub(%r{\[THINK\].*?\[/THINK\]}m, '').strip
          response_preview = cleaned_response.length > 500 ? "#{cleaned_response[0..500]}..." : cleaned_response
          puts "\e[1;35m·\e[0m #{response_preview}" unless response_preview.empty?

          # Log iteration completion with green dot
          puts "\e[1;32m·\e[0m Iteration completed (iteration=#{@iteration_count}, response_length=#{result_text.length}, total_tokens=#{metrics[:totalTokens]}, estimated_cost=$#{metrics[:estimatedCost]})"

          result
        rescue StandardError => e
          handle_error(e)
        end
      end
      # rubocop:enable Metrics/BlockLength

      # Run continuous execution loop
      #
      # @return [void]
      def run_loop
        start_time = Time.now

        logger.info('Starting execution')
        logger.info('Configuration',
                    workspace: @agent.workspace_path,
                    mcp_servers: @agent.servers_info.length,
                    max_iterations: @max_iterations)

        # Log persona loading
        persona = @agent.config.dig('agent', 'persona') || 'default'
        logger.info("👤 Loading persona: #{persona}")

        # Log MCP server details
        if @agent.servers_info.any?
          @agent.servers_info.each do |server|
            logger.info('◆ MCP server connected', name: server[:name], tool_count: server[:tool_count])
          end
        end

        # Get initial instructions from config or environment
        instructions = @agent.config.dig('agent', 'instructions') ||
                       ENV['AGENT_INSTRUCTIONS'] ||
                       'Monitor workspace and respond to changes'

        # Log instructions with bold white formatting
        instructions_preview = instructions[0..200]
        puts "\e[1;37m·\e[0m \e[1;37m#{instructions_preview}\e[0m"
        logger.info('Starting autonomous execution loop')

        loop do
          break if @iteration_count >= @max_iterations

          progress_pct = ((@iteration_count.to_f / @max_iterations) * 100).round(1)
          logger.debug('Loop progress',
                       iteration: @iteration_count,
                       max: @max_iterations,
                       progress: "#{progress_pct}%")

          result = execute(instructions)
          result_text = result.is_a?(String) ? result : result.content

          # Log result based on verbosity settings
          if @show_full_responses
            logger.info('Full iteration result',
                        iteration: @iteration_count,
                        result: result_text)
          else
            preview = result_text[0..200]
            preview += '...' if result_text.length > 200
            logger.info('Iteration result',
                        iteration: @iteration_count,
                        preview: preview)
          end

          # Rate limiting
          logger.debug('Rate limit pause', duration: 5)
          sleep 5
        end

        # Log execution summary
        total_duration = Time.now - start_time
        metrics = @metrics_tracker.cumulative_stats
        logger.info('Execution complete',
                    iterations: @iteration_count,
                    duration_s: total_duration.round(2),
                    total_requests: metrics[:requestCount],
                    total_tokens: metrics[:totalTokens],
                    estimated_cost: "$#{metrics[:estimatedCost]}",
                    reason: @iteration_count >= @max_iterations ? 'max_iterations' : 'completed')

        return unless @iteration_count >= @max_iterations

        logger.warn('Maximum iterations reached',
                    iterations: @max_iterations,
                    reason: 'Hit max_iterations limit')
      end

      private

      def logger_component
        'Agent::Executor'
      end

      # Build instruction enriched with request context
      #
      # @param instruction [String] Base instruction
      # @param context [Hash] Request context
      # @return [String] Enriched instruction
      def build_instruction_with_context(instruction, context)
        enriched = instruction.dup
        enriched += "\n\n## Request Context\n"
        enriched += "- Method: #{context[:method]}\n" if context[:method]
        enriched += "- Path: #{context[:path]}\n" if context[:path]

        if context[:params] && !context[:params].empty?
          enriched += "\n### Parameters:\n"
          enriched += "```json\n#{JSON.pretty_generate(context[:params])}\n```\n"
        end

        if context[:body] && !context[:body].empty?
          enriched += "\n### Request Body:\n"
          enriched += "```\n#{context[:body][0..1000]}\n```\n"
        end

        if context[:headers] && !context[:headers].empty?
          enriched += "\n### Headers:\n"
          context[:headers].each do |key, value|
            enriched += "- #{key}: #{value}\n"
          end
        end

        enriched
      end

      def initialize_safety_manager(agent_definition)
        # Get safety config from agent definition constraints
        config = agent_definition&.constraints || {}

        # Merge with environment variables
        config = {
          enabled: ENV.fetch('SAFETY_ENABLED', 'true') != 'false',
          daily_budget: config[:daily_budget] || parse_float_env('DAILY_BUDGET'),
          hourly_budget: config[:hourly_budget] || parse_float_env('HOURLY_BUDGET'),
          token_budget: config[:token_budget] || parse_int_env('TOKEN_BUDGET'),
          requests_per_minute: config[:requests_per_minute] || parse_int_env('REQUESTS_PER_MINUTE'),
          requests_per_hour: config[:requests_per_hour] || parse_int_env('REQUESTS_PER_HOUR'),
          requests_per_day: config[:requests_per_day] || parse_int_env('REQUESTS_PER_DAY'),
          blocked_patterns: config[:blocked_patterns] || parse_array_env('BLOCKED_PATTERNS'),
          blocked_topics: config[:blocked_topics] || parse_array_env('BLOCKED_TOPICS'),
          case_sensitive: config[:case_sensitive] || ENV.fetch('CASE_SENSITIVE', 'false') == 'true',
          audit_logging: config[:audit_logging] != false
        }.compact

        return nil if config[:enabled] == false

        Safety::Manager.new(config)
      rescue StandardError => e
        logger.warn('Failed to initialize safety manager',
                    error: e.message,
                    fallback: 'Safety features disabled')
        nil
      end

      def parse_float_env(key)
        val = ENV.fetch(key, nil)
        return nil unless val && !val.strip.empty?

        Float(val.strip)
      rescue ArgumentError
        logger.warn("Invalid float value for #{key}: #{val}. Ignoring.")
        nil
      end

      def parse_int_env(key)
        val = ENV.fetch(key, nil)
        return nil unless val && !val.strip.empty?

        Integer(val.strip)
      rescue ArgumentError
        logger.warn("Invalid integer value for #{key}: #{val}. Ignoring.")
        nil
      end

      def parse_array_env(key)
        val = ENV.fetch(key, nil)
        return nil unless val

        val.split(',').map(&:strip)
      end

      def estimate_tokens(text)
        # Rough estimate: ~1.3 tokens per word
        (text.split.length * 1.3).to_i
      end

      def estimate_cost(tokens)
        # Estimate based on common model pricing
        # Average of ~$3-15 per 1M tokens (using $10 as middle ground)
        # This is a rough estimate; actual cost varies by model
        (tokens / 1_000_000.0) * 10.0
      end

      def handle_error(error)
        case error
        when Timeout::Error, /timeout/i.match?(error.message)
          logger.error('Request timeout',
                       error: error.class.name,
                       message: error.message,
                       iteration: @iteration_count)
        when /connection refused|operation not permitted/i.match?(error.message)
          logger.error('Connection failed',
                       error: error.class.name,
                       message: error.message,
                       hint: 'Check if model service is healthy and accessible')
        else
          logger.error('Task execution failed',
                       error: error.class.name,
                       message: error.message)
          logger.debug('Backtrace', trace: error.backtrace[0..5].join("\n")) if error.backtrace
        end

        "Error executing task: #{error.message}"
      end
    end
  end
end
