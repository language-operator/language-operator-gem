# frozen_string_literal: true

require 'timeout'
require 'socket'
require_relative '../loggable'
require_relative 'instrumentation'
require_relative '../instrumentation/task_tracer'

module LanguageOperator
  module Agent
    # Custom error classes for task execution
    class TaskExecutionError < StandardError
      attr_reader :task_name, :original_error

      def initialize(task_name, message, original_error = nil)
        @task_name = task_name
        @original_error = original_error
        super("Task '#{task_name}' execution failed: #{message}")
      end
    end

    class TaskValidationError < TaskExecutionError
    end

    class TaskTimeoutError < TaskExecutionError
    end

    class TaskNetworkError < TaskExecutionError
    end

    # Task Executor for DSL v1 organic functions
    #
    # Executes both neural (LLM-based) and symbolic (code-based) tasks.
    # Provides the `execute_task` method that MainDefinition blocks use
    # to invoke tasks transparently regardless of implementation type.
    #
    # @example Executing a task
    #   executor = TaskExecutor.new(agent, tasks_registry)
    #   result = executor.execute_task(:fetch_data, inputs: { user_id: 123 })
    #
    # @example In a main block
    #   main do |inputs|
    #     data = execute_task(:fetch_data, inputs: inputs)
    #     execute_task(:process_data, inputs: data)
    #   end
    class TaskExecutor
      include LanguageOperator::Loggable
      include Instrumentation
      include LanguageOperator::Instrumentation::TaskTracer

      # Error types that should be retried
      RETRYABLE_ERRORS = [
        Timeout::Error,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        SocketError
      ].freeze

      # Error categories for logging and operator integration
      ERROR_CATEGORIES = {
        validation: 'VALIDATION',
        execution: 'EXECUTION',
        timeout: 'TIMEOUT',
        network: 'NETWORK',
        system: 'SYSTEM'
      }.freeze

      attr_reader :agent, :tasks, :config

      # Initialize the task executor
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance (provides LLM client, tools)
      # @param tasks [Hash<Symbol, TaskDefinition>] Registry of task definitions
      # @param config [Hash] Execution configuration
      def initialize(agent, tasks = {}, config = {})
        @agent = agent
        @tasks = tasks
        @config = default_config.merge(config)

        # Pre-cache task lookup and timeout information for performance
        @task_cache = build_task_cache
        @task_timeouts = build_timeout_cache

        logger.debug('TaskExecutor initialized',
                     task_count: @tasks.size,
                     timeout_symbolic: @config[:timeout_symbolic],
                     timeout_neural: @config[:timeout_neural],
                     timeout_hybrid: @config[:timeout_hybrid],
                     max_retries: @config[:max_retries])
      end

      # Execute a task by name with given inputs
      #
      # This is the main entry point called from MainDefinition blocks.
      # Routes to neural or symbolic execution based on task implementation.
      # Includes timeout, retry logic, and comprehensive error handling.
      #
      # @param task_name [Symbol] Name of the task to execute
      # @param inputs [Hash] Input parameters for the task
      # @param timeout [Numeric] Override timeout for this task (seconds)
      # @param max_retries [Integer] Override max retries for this task
      # @return [Hash] Validated output from the task
      # @raise [ArgumentError] If task not found or inputs invalid
      # @raise [TaskExecutionError] If task execution fails after retries
      def execute_task(task_name, inputs: {}, timeout: nil, max_retries: nil)
        execution_start = Time.now
        max_retries ||= @config[:max_retries]

        # Reset JSON parsing retry flag for this task
        @parsing_retry_attempted = false

        with_span('task_executor.execute_task', attributes: build_task_execution_attributes(task_name, inputs, max_retries)) do
          # Fast task lookup using pre-built cache
          task_name_sym = task_name.to_sym
          task_info = @task_cache[task_name_sym]
          raise ArgumentError, "Task not found: #{task_name}. Available tasks: #{@tasks.keys.join(', ')}" unless task_info

          task = task_info[:definition]
          task_type = task_info[:type]

          # Use cached timeout if not explicitly provided
          timeout ||= @task_timeouts[task_name_sym]

          # Optimize logging - only log if debug level enabled or log_executions is true
          if logger.logger.level <= ::Logger::DEBUG || @config[:log_executions]
            logger.info('Executing task',
                        task: task_name,
                        type: task_type,
                        timeout: timeout,
                        max_retries: max_retries,
                        inputs: summarize_values(inputs))
          end

          # Add timeout to span attributes after it's determined
          OpenTelemetry::Trace.current_span&.set_attribute('task.timeout', timeout)

          # Execute with retry logic
          result = execute_with_retry(task, task_name, inputs, timeout, max_retries, execution_start)

          # Emit Kubernetes event for successful task completion
          emit_task_execution_event(task_name, success: true, execution_start: execution_start)

          result
        end
      rescue ArgumentError => e
        # Validation errors should not be retried - re-raise immediately
        log_task_error(task_name, e, :validation, execution_start)
        emit_task_execution_event(task_name, success: false, execution_start: execution_start, error: e, event_type: :validation)
        raise TaskValidationError.new(task_name, e.message, e)
      rescue StandardError => e
        # Catch any unexpected errors that escaped retry logic
        log_task_error(task_name, e, :system, execution_start)
        emit_task_execution_event(task_name, success: false, execution_start: execution_start, error: e)
        raise create_appropriate_error(task_name, e)
      end

      # Execute a neural task (instructions-based, LLM-driven)
      #
      # @param task [TaskDefinition] The task definition
      # @param inputs [Hash] Input parameters
      # @return [Hash] Validated outputs
      # @raise [StandardError] If LLM execution fails or output validation fails
      def execute_neural(task, inputs)
        # Validate inputs first
        validated_inputs = task.validate_inputs(inputs)

        logger.debug('Executing neural task',
                     task: task.name,
                     instructions: task.instructions_text,
                     inputs: validated_inputs)

        # Build prompt for LLM
        prompt = build_neural_prompt(task, validated_inputs)

        logger.info('Sending prompt to LLM',
                    task: task.name,
                    prompt_length: prompt.length,
                    available_tools: @agent.respond_to?(:tools) ? @agent.tools.map(&:name) : 'N/A')

        # Execute LLM call within traced span
        outputs = tracer.in_span('gen_ai.chat', attributes: neural_task_attributes(task, prompt, validated_inputs)) do |span|
          # Call LLM with full tool access
          logger.debug('Calling LLM with prompt', task: task.name, prompt_preview: prompt[0..200])
          response = @agent.send_message(prompt)

          # Check for tool calls and log details
          has_tool_calls = response.respond_to?(:tool_calls) && response.tool_calls&.any?
          tool_call_count = has_tool_calls ? response.tool_calls.length : 0

          logger.info('LLM response received, extracting content',
                      task: task.name,
                      response_class: response.class.name,
                      has_tool_calls: has_tool_calls,
                      tool_call_count: tool_call_count)

          response_text = response.is_a?(String) ? response : response.content

          logger.info('Neural task response received',
                      task: task.name,
                      response_length: response_text.length)

          # Record token usage and response metadata
          record_token_usage(response, span)

          # Record tool calls if available
          record_tool_calls(response, span)

          logger.info('Parsing neural task response',
                      task: task.name)

          # Parse response within child span with retry logic
          parsed_outputs = tracer.in_span('task_executor.parse_response') do |parse_span|
            record_parse_metadata(response_text, parse_span)

            begin
              parse_neural_response(response_text, task)
            rescue RuntimeError => e
              # If parsing fails and this is a JSON parsing error, try one more time with clarified prompt
              raise e unless e.message.include?('returned invalid JSON') && !@parsing_retry_attempted

              @parsing_retry_attempted = true

              logger.warn('JSON parsing failed, retrying with clarified prompt',
                          task: task.name,
                          original_error: e.message,
                          response_preview: response_text[0..300])

              # Build retry prompt with clearer instructions
              retry_prompt = build_parsing_retry_prompt(task, validated_inputs, response_text, e.message)

              logger.info('Retrying LLM call with clarified prompt',
                          task: task.name,
                          retry_prompt_length: retry_prompt.length)

              # Retry LLM call
              retry_response = @agent.send_message(retry_prompt)
              retry_response_text = retry_response.is_a?(String) ? retry_response : retry_response.content

              logger.info('Parsing retry response',
                          task: task.name,
                          retry_response_length: retry_response_text.length)

              # Try parsing the retry response
              parse_neural_response(retry_response_text, task)
            end
          end

          logger.info('Response parsed successfully',
                      task: task.name,
                      output_keys: parsed_outputs.keys)

          # Record output metadata
          record_output_metadata(parsed_outputs, span)

          parsed_outputs
        end

        logger.info('Validating task outputs',
                    task: task.name)

        # Validate outputs against schema
        task.validate_outputs(outputs)
      end

      # Helper method for symbolic tasks to execute tools
      #
      # Executes an MCP tool directly through the agent's MCP clients.
      #
      # @param tool_name [Symbol, String] Name of the tool to execute
      # @param params [Hash] Tool parameters
      # @return [Object] Tool response (parsed from tool result)
      def execute_tool(tool_name, params = {})
        tool_name_str = tool_name.to_s

        logger.info('Tool call initiated by symbolic task',
                    tool: tool_name_str,
                    params: summarize_values(params))

        # Find the tool across all MCP clients
        tool = @agent.tools.find { |t| t.name == tool_name_str }
        raise ArgumentError, "Tool '#{tool_name_str}' not found" unless tool

        # Execute the tool (it's a Proc/lambda wrapped by RubyLLM)
        result = tool.call(**params)

        # Extract text from MCP Content objects
        text_result = if result.is_a?(RubyLLM::MCP::Content)
                        result.text
                      elsif result.respond_to?(:map) && result.first.is_a?(RubyLLM::MCP::Content)
                        result.map(&:text).join
                      else
                        result
                      end

        logger.debug('Tool call completed',
                     tool: tool_name_str,
                     result_preview: text_result.is_a?(String) ? text_result[0..200] : text_result.class.name)

        # Try to parse JSON response if it looks like JSON
        if text_result.is_a?(String) && (text_result.strip.start_with?('{') || text_result.strip.start_with?('['))
          JSON.parse(text_result, symbolize_names: true)
        else
          text_result
        end
      rescue JSON::ParserError
        # Not JSON, return as-is
        text_result
      end

      # Helper method for symbolic tasks to call LLM directly
      #
      # @param prompt [String] Prompt to send to LLM
      # @return [String] LLM response
      def execute_llm(prompt)
        response = @agent.send_message(prompt)
        response.is_a?(String) ? response : response.content
      end

      # Execute multiple tasks in parallel
      #
      # Provides explicit parallelism for task execution. Users specify which tasks
      # should run in parallel, and this method handles the concurrent execution.
      #
      # @param tasks [Array<Hash>] Array of task specifications
      # @param in_threads [Integer] Number of threads to use (default: 4)
      # @return [Array] Results from all tasks in the same order as input
      # @raise [RuntimeError] If any task fails
      #
      # @example Execute multiple independent tasks
      #   results = execute_parallel([
      #     { name: :fetch_source1 },
      #     { name: :fetch_source2 }
      #   ])
      #   # => [result1, result2]
      #
      # @example With inputs
      #   results = execute_parallel([
      #     { name: :process, inputs: { data: data1 } },
      #     { name: :analyze, inputs: { data: data2 } }
      #   ])
      #
      def execute_parallel(tasks, in_threads: 4)
        require 'parallel'

        # Capture current OpenTelemetry context before parallel execution
        current_context = OpenTelemetry::Context.current

        logger.info('Executing tasks in parallel', count: tasks.size, threads: in_threads)

        results = Parallel.map(tasks, in_threads: in_threads) do |task_spec|
          # Restore OpenTelemetry context in worker thread
          OpenTelemetry::Context.with_current(current_context) do
            task_name = task_spec[:name]
            task_inputs = task_spec[:inputs] || {}

            execute_task(task_name, inputs: task_inputs)
          end
        end

        logger.info('Parallel execution complete', results_count: results.size)
        results
      rescue Parallel::DeadWorker => e
        logger.error('Parallel execution failed - worker died', error: e.message)
        raise "Parallel task execution failed: #{e.message}"
      rescue StandardError => e
        logger.error('Parallel execution failed', error: e.class.name, message: e.message)
        raise
      end

      private

      def logger_component
        'Agent::TaskExecutor'
      end

      # Emit Kubernetes event for task execution
      #
      # @param task_name [Symbol, String] Task name
      # @param success [Boolean] Whether task succeeded
      # @param execution_start [Time] Task execution start time
      # @param error [Exception, nil] Error if task failed
      # @param event_type [Symbol, nil] Event type override (:success, :failure, :validation)
      def emit_task_execution_event(task_name, success:, execution_start:, error: nil, event_type: nil)
        return unless @agent.respond_to?(:kubernetes_client)

        duration_ms = ((Time.now - execution_start) * 1000).round(2)

        metadata = {
          'task_type' => determine_task_type(@tasks[task_name.to_sym])
        }

        if error
          metadata['error_type'] = error.class.name
          metadata['error_category'] = categorize_error(error).to_s
        end

        @agent.kubernetes_client.emit_execution_event(
          task_name.to_s,
          success: success,
          duration_ms: duration_ms,
          metadata: metadata
        )
      rescue StandardError => e
        logger.warn('Failed to emit task execution event',
                    task: task_name,
                    error: e.message)
      end

      # Summarize hash values for logging (truncate long strings)
      # Optimized for performance with lazy computation
      #
      # @param hash [Hash] Hash to summarize
      # @return [Hash] Summarized hash with truncated values
      def summarize_values(hash)
        return {} unless hash.is_a?(Hash)

        # OPTIMIZE: only create new hash if values need summarization
        needs_summarization = false
        result = {}

        hash.each do |key, v|
          summarized_value = case v
                             when String
                               if v.length > 100
                                 needs_summarization = true
                                 "#{v[0, 97]}... (#{v.length} chars)"
                               else
                                 v
                               end
                             when Array
                               if v.length > 5
                                 needs_summarization = true
                                 "#{v.first(3).inspect}... (#{v.length} items)"
                               else
                                 v.inspect
                               end
                             else
                               v.inspect
                             end
          result[key] = summarized_value
        end

        # Return original if no summarization was needed (rare optimization)
        needs_summarization ? result : hash
      end

      # Build prompt for neural task execution
      #
      # @param task [TaskDefinition] The task definition
      # @param inputs [Hash] Validated input parameters
      # @return [String] Prompt for LLM
      def build_neural_prompt(task, inputs)
        prompt = "# Task: #{task.name}\n\n"
        prompt += "## Instructions\n#{task.instructions_text}\n\n"

        if inputs.any?
          prompt += "## Inputs\n"
          inputs.each do |key, value|
            prompt += "- #{key}: #{value.inspect}\n"
          end
          prompt += "\n"
        end

        prompt += "## Output Schema\n"
        prompt += "You must return a JSON object with the following fields:\n"
        task.outputs_schema.each do |key, type|
          prompt += "- #{key} (#{type})\n"
        end
        prompt += "\n"

        prompt += "## Response Format\n"
        prompt += "You may include your reasoning in [THINK]...[/THINK] tags if helpful.\n"
        prompt += "Use available tools as needed to complete the task.\n"
        prompt += "After using tools (if needed), return your final answer as valid JSON matching the output schema above.\n"
        prompt += "Your final JSON response should come after any tool calls and thinking.\n"
        prompt += "Do not include explanations outside of [THINK] tags - only the JSON output.\n"

        prompt
      end

      # Build retry prompt when JSON parsing fails
      #
      # @param task [TaskDefinition] The task definition
      # @param inputs [Hash] Validated input parameters
      # @param failed_response [String] The previous response that failed to parse
      # @param error_message [String] The parsing error message
      # @return [String] Prompt for LLM retry
      def build_parsing_retry_prompt(task, inputs, failed_response, error_message)
        prompt = "# Task: #{task.name} (RETRY - JSON Parsing Failed)\n\n"
        prompt += "## Instructions\n#{task.instructions_text}\n\n"

        if inputs.any?
          prompt += "## Inputs\n"
          inputs.each do |key, value|
            prompt += "- #{key}: #{value.inspect}\n"
          end
          prompt += "\n"
        end

        prompt += "## Previous Response (Failed to Parse)\n"
        prompt += "Your previous response caused a parsing error: #{error_message}\n"
        prompt += "Previous response preview:\n```\n#{failed_response[0..500]}#{'...' if failed_response.length > 500}\n```\n\n"

        prompt += "## Output Schema (CRITICAL)\n"
        prompt += "You MUST return valid JSON with exactly these fields:\n"
        task.outputs_schema.each do |key, type|
          prompt += "- #{key} (#{type})\n"
        end
        prompt += "\n"

        prompt += "## Response Format (CRITICAL)\n"
        prompt += "IMPORTANT: Your response must be ONLY valid JSON. No other text.\n"
        prompt += "Do NOT use [THINK] tags or any other text.\n"
        prompt += "Do NOT include code blocks like ```json.\n"
        prompt += "Return ONLY the JSON object, nothing else.\n"
        prompt += "The JSON must match the output schema exactly.\n\n"

        prompt += "Example correct format:\n"
        prompt += "{\n"
        task.outputs_schema.each_with_index do |(key, type), index|
          value_example = case type
                          when 'string' then '"example"'
                          when 'integer' then '42'
                          when 'number' then '3.14'
                          when 'boolean' then 'true'
                          when 'array' then '[]'
                          when 'hash' then '{}'
                          else '"value"'
                          end
          comma = index < task.outputs_schema.length - 1 ? ',' : ''
          prompt += "  \"#{key}\": #{value_example}#{comma}\n"
        end
        prompt += "}\n"

        prompt
      end

      # Parse LLM response to extract output values
      #
      # @param response_text [String] LLM response
      # @param task [TaskDefinition] Task definition for schema
      # @return [Hash] Parsed outputs
      # @raise [RuntimeError] If parsing fails
      def parse_neural_response(response_text, task)
        # Capture thinking blocks before stripping (for observability)
        thinking_blocks = response_text.scan(%r{\[THINK\](.*?)\[/THINK\]}m).flatten
        if thinking_blocks.any?
          logger.info('LLM thinking captured',
                      event: 'llm_thinking',
                      task: task.name,
                      thinking_steps: thinking_blocks.length,
                      thinking: thinking_blocks,
                      thinking_preview: thinking_blocks.first&.[](0..500))
        end

        # Strip thinking tags that some models add (e.g., [THINK]...[/THINK] or unclosed [THINK]...)
        # First try to strip matched pairs, then strip unclosed [THINK] only if there's JSON after it
        logger.debug('Parsing neural response', task: task.name, response_length: response_text.length, response_start: response_text[0..100])

        cleaned_text = response_text.gsub(%r{\[THINK\].*?\[/THINK\]}m, '')
                                    .gsub(/\[THINK\].*?(?=\{)/m, '')
                                    .strip

        # If cleaned text is empty or still contains unclosed [THINK], try more aggressive cleaning
        if cleaned_text.empty? || cleaned_text.start_with?('[THINK]')
          # Strip everything from [THINK] to end if no [/THINK] found
          cleaned_text = response_text.gsub(/\[THINK\].*$/m, '').strip

          # If still no JSON found, extract everything after the last [THINK] block
          if cleaned_text.empty? && response_text.include?('{')
            last_think = response_text.rindex('[THINK]')
            if last_think
              after_think = response_text[last_think..]
              # Find first JSON-like structure after [THINK]
              json_start = after_think.index('{')
              cleaned_text = after_think[json_start..] if json_start
            end
          end
        end

        logger.debug('After stripping THINK tags', cleaned_length: cleaned_text.length, cleaned_start: cleaned_text[0..100])

        # Try to extract JSON from response
        # Look for JSON code blocks first
        json_match = cleaned_text.match(/```json\s*\n(.*?)\n```/m)
        json_text = if json_match
                      json_match[1]
                    else
                      # Try to find raw JSON object - be more aggressive about finding JSON
                      json_object_match = cleaned_text.match(/\{.*\}/m)
                      if json_object_match
                        json_object_match[0]
                      elsif cleaned_text.include?('{')
                        # Extract from first { to end of string (handles incomplete responses)
                        json_start = cleaned_text.index('{')
                        cleaned_text[json_start..]
                      else
                        cleaned_text
                      end
                    end

        logger.debug('Extracted JSON text', json_length: json_text.length, json_start: json_text[0..100])

        # Parse JSON
        parsed = JSON.parse(json_text)

        # Deep convert all string keys to symbols (including nested hashes and arrays)
        deep_symbolize_keys(parsed)
      rescue JSON::ParserError => e
        logger.error('Failed to parse neural task response as JSON',
                     task: task.name,
                     response: response_text[0..200],
                     error: e.message)
        raise "Neural task '#{task.name}' returned invalid JSON: #{e.message}"
      end

      # Recursively convert all hash keys to symbols (optimized for performance)
      def deep_symbolize_keys(obj)
        case obj
        when Hash
          # OPTIMIZE: pre-allocate hash with correct size and avoid double iteration
          result = {}
          obj.each do |key, value|
            result[key.to_sym] = deep_symbolize_keys(value)
          end
          result
        when Array
          # OPTIMIZE: pre-allocate array with correct size
          result = Array.new(obj.size)
          obj.each_with_index do |item, index|
            result[index] = deep_symbolize_keys(item)
          end
          result
        else
          obj
        end
      end

      # Default configuration for task execution
      #
      # @return [Hash] Default configuration
      def default_config
        {
          timeout_symbolic: 30.0,     # Default timeout for symbolic tasks (seconds)
          timeout_neural: 360.0,      # Default timeout for neural tasks (seconds)
          timeout_hybrid: 360.0,      # Default timeout for hybrid tasks (seconds)
          max_retries: 3,             # Default max retry attempts
          retry_delay_base: 1.0,      # Base delay for exponential backoff
          retry_delay_max: 10.0       # Maximum delay between retries
        }
      end

      # Determine task type for logging and telemetry
      #
      # @param task [TaskDefinition] The task definition
      # @return [String] Task type
      def determine_task_type(task)
        if task.neural? && task.symbolic?
          'hybrid'
        elsif task.neural?
          'neural'
        elsif task.symbolic?
          'symbolic'
        else
          'undefined'
        end
      end

      # Determine appropriate timeout for a task based on its type
      #
      # Neural tasks typically require longer timeouts due to LLM API calls,
      # while symbolic tasks (pure Ruby code) can use shorter timeouts.
      #
      # @param task [TaskDefinition] The task definition
      # @return [Float] Timeout in seconds
      def task_timeout_for_type(task)
        if task.neural? && task.symbolic?
          # Hybrid tasks use neural timeout (they may call LLM)
          @config[:timeout_hybrid]
        elsif task.neural?
          # Neural tasks need longer timeout for LLM calls
          @config[:timeout_neural]
        elsif task.symbolic?
          # Symbolic tasks use shorter timeout
          @config[:timeout_symbolic]
        else
          # Default to symbolic timeout for undefined tasks
          @config[:timeout_symbolic]
        end
      end

      # Execute task with retry logic and timeout
      #
      # @param task [TaskDefinition] The task definition
      # @param task_name [Symbol] Name of the task
      # @param inputs [Hash] Input parameters
      # @param timeout [Numeric] Timeout in seconds
      # @param max_retries [Integer] Maximum retry attempts
      # @param execution_start [Time] When execution started
      # @return [Hash] Task outputs
      def execute_with_retry(task, task_name, inputs, timeout, max_retries, execution_start)
        attempt = 0
        last_error = nil

        while attempt <= max_retries
          begin
            return execute_single_attempt(task, task_name, inputs, timeout, attempt, execution_start)
          rescue StandardError => e
            last_error = e
            attempt += 1

            # Don't retry validation errors or non-retryable errors
            unless retryable_error?(e) && attempt <= max_retries
              # Re-raise ArgumentError so it gets caught by the ArgumentError rescue block
              raise e if e.is_a?(ArgumentError)

              log_task_error(task_name, e, categorize_error(e), execution_start, attempt - 1)
              raise create_appropriate_error(task_name, e)
            end

            # Calculate delay for exponential backoff
            delay = calculate_retry_delay(attempt - 1)
            logger.warn('Task execution failed, retrying',
                        task: task_name,
                        attempt: attempt,
                        max_retries: max_retries,
                        error: e.class.name,
                        message: e.message,
                        retry_delay: delay)

            sleep(delay) if delay.positive?
          end
        end

        # If we get here, we've exhausted all retries
        log_task_error(task_name, last_error, categorize_error(last_error), execution_start, max_retries)
        raise create_appropriate_error(task_name, last_error)
      end

      # Execute a single attempt of a task with timeout and error context preservation
      #
      # This method implements timeout handling that preserves original error context
      # while maintaining error precedence hierarchy. Timeout errors always take
      # precedence over any nested errors (including network errors).
      #
      # @param task [TaskDefinition] The task definition
      # @param task_name [Symbol] Name of the task
      # @param inputs [Hash] Input parameters
      # @param timeout [Numeric] Timeout in seconds
      # @param attempt [Integer] Current attempt number
      # @param execution_start [Time] When execution started
      # @return [Hash] Task outputs
      def execute_single_attempt(task, task_name, inputs, timeout, attempt, _execution_start)
        attempt_start = Time.now

        result = if timeout.positive?
                   execute_with_timeout(task, task_name, inputs, timeout)
                 else
                   execute_task_implementation(task, inputs)
                 end

        execution_time = Time.now - attempt_start

        # Optimize logging - only log if debug level enabled or log_executions is true
        if logger.logger.level <= ::Logger::DEBUG || @config[:log_executions]
          logger.info('Task completed',
                      task: task_name,
                      attempt: attempt + 1,
                      execution_time: execution_time.round(3),
                      outputs: summarize_values(result))
        end

        result
      end

      # Execute task with timeout wrapper that preserves error context
      #
      # This method ensures that timeout errors always take precedence over
      # any nested errors (e.g., network errors), solving the race condition
      # between timeout detection and error classification.
      #
      # @param task [TaskDefinition] The task definition
      # @param task_name [Symbol] Name of the task
      # @param inputs [Hash] Input parameters
      # @param timeout [Numeric] Timeout in seconds
      # @return [Hash] Task outputs
      # @raise [TaskTimeoutError] If execution times out (always takes precedence)
      def execute_with_timeout(task, task_name, inputs, timeout)
        attempt_start = Time.now

        Timeout.timeout(timeout) do
          execute_task_implementation(task, inputs)
        end
      rescue Timeout::Error => e
        # Timeout always wins - this solves the race condition
        execution_time = Time.now - attempt_start

        logger.warn('Task execution timed out',
                    task: task_name,
                    timeout: timeout,
                    execution_time: execution_time.round(3),
                    timeout_precedence: 'timeout error takes precedence over any nested errors')

        # Always wrap as TaskTimeoutError, preserving original timeout context
        raise TaskTimeoutError.new(task_name, "timed out after #{timeout}s (execution_time: #{execution_time.round(3)}s)", e)
      rescue *RETRYABLE_ERRORS => e
        # Network errors that escape timeout handling (very rare)
        # These occur outside the timeout window, so they're genuine network errors
        logger.debug('Network error outside timeout window',
                     task: task_name,
                     error: e.class.name,
                     message: e.message)
        raise TaskNetworkError.new(task_name, "network error: #{e.message}", e)
      end

      # Execute the actual task implementation (neural or symbolic)
      #
      # For hybrid tasks (both neural and symbolic), prefer symbolic execution
      # as it's more efficient and deterministic.
      #
      # @param task [TaskDefinition] The task definition
      # @param inputs [Hash] Input parameters
      # @return [Hash] Task outputs
      def execute_task_implementation(task, inputs)
        if task.symbolic?
          # Symbolic execution: Direct Ruby code within traced span
          # This takes precedence over neural for hybrid tasks
          tracer.in_span('task_executor.symbolic', attributes: symbolic_task_attributes(task)) do |span|
            validated_inputs = task.validate_inputs(inputs)
            span.set_attribute('task.input.keys', validated_inputs.keys.map(&:to_s).join(','))
            span.set_attribute('task.input.count', validated_inputs.size)

            # Pass self as context so symbolic tasks can call execute_task, execute_tool, etc.
            outputs = task.call(validated_inputs, self)

            record_output_metadata(outputs, span) if outputs.is_a?(Hash)
            outputs
          end
        elsif task.neural?
          # Neural execution: LLM with tool access
          # Only used for pure neural tasks (no symbolic implementation)
          execute_neural(task, inputs)
        else
          raise ArgumentError, "Task '#{task.name}' has neither neural nor symbolic implementation"
        end
      end

      # Check if an error should be retried
      #
      # @param error [Exception] The error that occurred
      # @return [Boolean] Whether the error should be retried
      def retryable_error?(error)
        case error
        when TaskNetworkError
          # Network errors wrapped in TaskNetworkError are retryable
          true
        when TaskTimeoutError, TaskValidationError
          # Timeout and validation errors are never retryable
          false
        when TaskExecutionError
          # Check the original error for retryability
          error.original_error ? retryable_error?(error.original_error) : false
        when RuntimeError
          # JSON parsing errors from neural tasks are retryable
          error.message.include?('returned invalid JSON')
        else
          # Check against the standard retryable error list
          RETRYABLE_ERRORS.any? { |error_class| error.is_a?(error_class) }
        end
      end

      # Categorize error for logging and operator integration with precedence hierarchy
      #
      # Error precedence (highest to lowest):
      # 1. Timeout errors (always win, even if wrapping network errors)
      # 2. Validation errors (argument/input validation failures)
      # 3. Network errors (connection, socket, DNS issues)
      # 4. Execution errors (general task execution failures)
      # 5. System errors (unexpected/unknown errors)
      #
      # @param error [Exception] The error that occurred
      # @return [Symbol] Error category
      def categorize_error(error)
        # Precedence Level 1: Timeout errors always win
        return :timeout if error.is_a?(Timeout::Error) || error.is_a?(TaskTimeoutError)

        # Precedence Level 2: Validation errors
        return :validation if error.is_a?(ArgumentError) || error.is_a?(TaskValidationError)

        # For wrapped errors, check original error but preserve timeout precedence
        return categorize_error(error.original_error) if error.is_a?(TaskExecutionError) && error.original_error

        # Precedence Level 3: Network errors
        return :network if error.is_a?(TaskNetworkError) || RETRYABLE_ERRORS.any? { |err_class| error.is_a?(err_class) }

        # Precedence Level 4: General execution errors
        :execution
      end

      # Calculate retry delay with exponential backoff
      #
      # @param attempt [Integer] Current attempt number (0-based)
      # @return [Float] Delay in seconds
      def calculate_retry_delay(attempt)
        delay = @config[:retry_delay_base] * (2**attempt)
        [delay, @config[:retry_delay_max]].min
      end

      # Create appropriate error type based on original error with precedence hierarchy
      #
      # @param task_name [Symbol] Name of the task
      # @param original_error [Exception] The original error
      # @return [TaskExecutionError] Appropriate error type
      def create_appropriate_error(task_name, original_error)
        case original_error
        when TaskTimeoutError, TaskValidationError, TaskNetworkError
          # Already wrapped in appropriate type
          original_error
        when Timeout::Error
          # Always wrap timeout errors, preserving original context
          TaskTimeoutError.new(task_name, "timed out after timeout (original: #{original_error.message})", original_error)
        when ArgumentError
          TaskValidationError.new(task_name, original_error.message, original_error)
        when *RETRYABLE_ERRORS
          # Wrap network errors for clear categorization
          TaskNetworkError.new(task_name, "network error: #{original_error.message}", original_error)
        else
          TaskExecutionError.new(task_name, original_error.message, original_error)
        end
      end

      # Log task error with comprehensive context
      #
      # @param task_name [Symbol] Name of the task
      # @param error [Exception] The error that occurred
      # @param category [Symbol] Error category
      # @param execution_start [Time] When execution started
      # @param retry_count [Integer] Number of retries attempted
      def log_task_error(task_name, error, category, execution_start, retry_count = 0)
        execution_time = Time.now - execution_start

        logger.error('Task execution failed',
                     task: task_name,
                     error_category: ERROR_CATEGORIES[category],
                     error_class: error.class.name,
                     error_message: error.message,
                     execution_time: execution_time.round(3),
                     retry_count: retry_count,
                     retryable: retryable_error?(error),
                     backtrace: error.backtrace&.first(5))
      end

      # Build task lookup cache for O(1) task resolution
      #
      # Pre-computes task metadata to avoid repeated type determinations
      # and provide fast hash-based lookup instead of linear search.
      #
      # @return [Hash] Cache mapping task names to metadata
      def build_task_cache
        cache = {}
        @tasks.each do |name, task|
          # Guard against test doubles that don't respond to task methods
          cache[name] = if task.respond_to?(:neural?) && task.respond_to?(:symbolic?)
                          {
                            definition: task,
                            type: determine_task_type(task),
                            neural: task.neural?,
                            symbolic: task.symbolic?
                          }
                        else
                          # Fallback for test doubles or invalid task objects
                          {
                            definition: task,
                            type: 'unknown',
                            neural: false,
                            symbolic: false
                          }
                        end
        end
        cache
      end

      # Build timeout cache for O(1) timeout resolution
      #
      # Pre-computes timeouts for all tasks to avoid repeated calculations
      # during task execution hot path.
      #
      # @return [Hash] Cache mapping task names to timeout values
      def build_timeout_cache
        cache = {}
        @tasks.each do |name, task|
          # Guard against test doubles that don't respond to task methods
          cache[name] = if task.respond_to?(:neural?) && task.respond_to?(:symbolic?)
                          task_timeout_for_type(task)
                        else
                          # Fallback timeout for test doubles or invalid task objects
                          @config[:timeout_symbolic]
                        end
        end
        cache
      end

      # Build semantic attributes for task execution span
      #
      # Includes attributes required for learning status tracking:
      # - task.name: Task identifier for learning controller
      # - agent.name: Agent identifier (explicit for learning system)
      # - gen_ai.operation.name: Semantic operation name
      #
      # @param task_name [Symbol] Name of the task being executed
      # @param inputs [Hash] Task input parameters
      # @param max_retries [Integer] Maximum retry attempts
      # @return [Hash] Span attributes
      def build_task_execution_attributes(task_name, inputs, max_retries)
        attributes = {
          # Core task identification (CRITICAL for learning system)
          'task.name' => task_name.to_s,
          'task.inputs' => inputs.keys.map(&:to_s).join(','),
          'task.max_retries' => max_retries,

          # Semantic operation name for better trace organization
          'gen_ai.operation.name' => 'execute_task'
        }

        # Explicitly add agent name if available (redundant with resource attribute but ensures visibility)
        if (agent_name = ENV.fetch('AGENT_NAME', nil))
          attributes['agent.name'] = agent_name
        end

        # Add task type information if available
        if (task_info = @task_cache[task_name.to_sym])
          attributes['task.type'] = task_info[:type]
          attributes['task.has_neural'] = task_info[:neural].to_s
          attributes['task.has_symbolic'] = task_info[:symbolic].to_s
        end

        attributes
      end
    end
  end
end
