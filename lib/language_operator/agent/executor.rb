# frozen_string_literal: true

require_relative '../logger'
require_relative '../loggable'
require_relative 'metrics_tracker'
require_relative 'safety/manager'

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

      # Execute a single task or workflow
      #
      # @param task [String] The task to execute
      # @param agent_definition [LanguageOperator::Dsl::AgentDefinition, nil] Optional agent definition with workflow
      # @return [String] The result
      def execute(task, agent_definition: nil)
        @iteration_count += 1

        # Route to workflow execution if agent has a workflow defined
        return execute_workflow(agent_definition) if agent_definition&.workflow

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

        logger.info('🤖 LLM request')
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
        logger.info('✓ Iteration completed',
                    iteration: @iteration_count,
                    response_length: result_text.length,
                    total_tokens: metrics[:totalTokens],
                    estimated_cost: "$#{metrics[:estimatedCost]}")
        logger.debug('Response preview', response: result_text[0..200])

        result
      rescue StandardError => e
        handle_error(e)
      end

      # Run continuous execution loop
      #
      # @return [void]
      def run_loop
        start_time = Time.now

        logger.info('▶ Starting execution')
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

        logger.info('Instructions', instructions: instructions[0..200])
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
        logger.info('✅ Execution complete',
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

      # Execute a workflow-based agent
      #
      # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition
      # @return [RubyLLM::Message] The final response
      def execute_workflow(agent_def)
        start_time = Time.now

        logger.info("▶ Starting workflow execution: #{agent_def.name}")

        # Log persona if defined
        logger.info("👤 Loading persona: #{agent_def.persona}") if agent_def.persona

        # Build orchestration prompt from agent definition
        prompt = build_workflow_prompt(agent_def)
        logger.debug('Workflow prompt', prompt: prompt[0..300])

        # Register workflow steps as tools (placeholder - will implement after tool converter)
        # For now, just execute with instructions
        result = logger.timed('🤖 LLM request') do
          @agent.send_message(prompt)
        end

        # Record metrics
        model_id = @agent.config.dig('llm', 'model')
        @metrics_tracker.record_request(result, model_id) if model_id

        # Write output if configured
        write_output(agent_def, result) if agent_def.output_config && result

        # Log execution summary
        total_duration = Time.now - start_time
        metrics = @metrics_tracker.cumulative_stats
        logger.info('✅ Workflow execution completed',
                    duration_s: total_duration.round(2),
                    total_tokens: metrics[:totalTokens],
                    estimated_cost: "$#{metrics[:estimatedCost]}")
        result
      rescue StandardError => e
        logger.error('❌ Workflow execution failed', error: e.message)
        handle_error(e)
      end

      # Build orchestration prompt from agent definition
      #
      # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition
      # @return [String] The prompt
      def build_workflow_prompt(agent_def)
        prompt = "# Task: #{agent_def.description}\n\n"

        if agent_def.objectives&.any?
          prompt += "## Objectives:\n"
          agent_def.objectives.each { |obj| prompt += "- #{obj}\n" }
          prompt += "\n"
        end

        if agent_def.workflow&.steps&.any?
          prompt += "## Workflow Steps:\n"
          agent_def.workflow.step_order.each do |step_name|
            step = agent_def.workflow.steps[step_name]
            prompt += step_name.to_s.tr('_', ' ').capitalize.to_s
            prompt += " (using tool: #{step.tool_name})" if step.tool_name
            prompt += " - depends on: #{step.dependencies.join(', ')}" if step.dependencies&.any?
            prompt += "\n"
          end
          prompt += "\n"
        end

        if agent_def.constraints
          prompt += "## Constraints:\n"
          prompt += "- Maximum iterations: #{agent_def.constraints[:max_iterations]}\n" if agent_def.constraints[:max_iterations]
          prompt += "- Timeout: #{agent_def.constraints[:timeout]}\n" if agent_def.constraints[:timeout]
          prompt += "\n"
        end

        prompt += 'Please complete this task following the workflow steps.'
        prompt
      end

      # Write output to configured destinations
      #
      # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition
      # @param result [RubyLLM::Message] The result to write
      def write_output(agent_def, result)
        return unless agent_def.output_config

        content = result.is_a?(String) ? result : result.content

        if (workspace_path = agent_def.output_config[:workspace])
          full_path = File.join(@agent.workspace_path, workspace_path)

          begin
            FileUtils.mkdir_p(File.dirname(full_path))
            File.write(full_path, content)
            logger.info("📝 Wrote output to #{workspace_path}")
          rescue Errno::EACCES, Errno::EPERM
            # Permission denied - try writing to workspace root
            fallback_path = File.join(@agent.workspace_path, 'output.txt')
            begin
              File.write(fallback_path, content)
              logger.warn("⚠️  Could not write to #{workspace_path}, wrote to output.txt instead")
            rescue StandardError => e2
              logger.warn("⚠️  Could not write output to workspace: #{e2.message}")
              logger.info("📄 Output (first 500 chars): #{content[0..500]}")
            end
          end
        end

        # Future: Handle Slack, email outputs
      rescue StandardError => e
        logger.warn('Output writing failed', error: e.message)
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
        return nil unless val

        val.to_f
      end

      def parse_int_env(key)
        val = ENV.fetch(key, nil)
        return nil unless val

        val.to_i
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
