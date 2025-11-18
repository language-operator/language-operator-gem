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

        with_span('task_executor.execute_task', attributes: {
                    'task.name' => task_name.to_s,
                    'task.inputs' => inputs.keys.map(&:to_s).join(','),
                    'task.max_retries' => max_retries
                  }) do
          # Find task definition
          task = @tasks[task_name.to_sym]
          raise ArgumentError, "Task not found: #{task_name}. Available tasks: #{@tasks.keys.join(', ')}" unless task

          task_type = determine_task_type(task)

          # Determine timeout based on task type if not explicitly provided
          timeout ||= task_timeout_for_type(task)

          logger.info('Executing task',
                      task: task_name,
                      type: task_type,
                      timeout: timeout,
                      max_retries: max_retries)

          # Add timeout to span attributes after it's determined
          OpenTelemetry::Trace.current_span&.set_attribute('task.timeout', timeout)

          # Execute with retry logic
          execute_with_retry(task, task_name, inputs, timeout, max_retries, execution_start)
        end
      rescue ArgumentError => e
        # Validation errors should not be retried - re-raise immediately
        log_task_error(task_name, e, :validation, execution_start)
        raise TaskValidationError.new(task_name, e.message, e)
      rescue StandardError => e
        # Catch any unexpected errors that escaped retry logic
        log_task_error(task_name, e, :system, execution_start)
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

          logger.info('LLM response received, extracting content',
                      task: task.name,
                      response_class: response.class.name,
                      has_tool_calls: response.respond_to?(:tool_calls) && response.tool_calls&.any?)

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

          # Parse response within child span
          parsed_outputs = tracer.in_span('task_executor.parse_response') do |parse_span|
            record_parse_metadata(response_text, parse_span)
            parse_neural_response(response_text, task)
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
      # This is a simplified interface - symbolic tasks should primarily use
      # execute_llm to leverage tools through the LLM interface, or call tools
      # directly through the MCP client if needed.
      #
      # @param tool_name [String] Name of the tool
      # @param action [String] Tool action/method
      # @param params [Hash] Tool parameters
      # @return [Object] Tool response
      # @note For DSL v1, tools are accessed via LLM tool calling, not direct invocation
      def execute_tool(tool_name, action, params = {})
        # Build prompt to use the tool via LLM
        prompt = "Use the #{tool_name} tool to perform #{action} with parameters: #{params.inspect}"
        execute_llm(prompt)
        # Parse response - for now just return the text
        # TODO: More sophisticated tool result extraction
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

        logger.info('Executing tasks in parallel', count: tasks.size, threads: in_threads)

        results = Parallel.map(tasks, in_threads: in_threads) do |task_spec|
          task_name = task_spec[:name]
          task_inputs = task_spec[:inputs] || {}

          execute_task(task_name, inputs: task_inputs)
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
        prompt += "Return ONLY valid JSON matching the output schema above.\n"
        prompt += "Do NOT include any explanations, thinking, or text before or after the JSON.\n"
        prompt += "Do NOT use [THINK] tags or any other markup.\n"
        prompt += "Use available tools as needed to complete the task.\n"

        prompt
      end

      # Parse LLM response to extract output values
      #
      # @param response_text [String] LLM response
      # @param task [TaskDefinition] Task definition for schema
      # @return [Hash] Parsed outputs
      # @raise [RuntimeError] If parsing fails
      def parse_neural_response(response_text, task)
        # Strip thinking tags that some models add (e.g., [THINK]...[/THINK])
        cleaned_text = response_text.gsub(%r{\[THINK\].*?\[/THINK\]}m, '').strip

        # Try to extract JSON from response
        # Look for JSON code blocks first
        json_match = cleaned_text.match(/```json\s*\n(.*?)\n```/m)
        json_text = if json_match
                      json_match[1]
                    else
                      # Try to find raw JSON object
                      json_object_match = cleaned_text.match(/\{.*\}/m)
                      json_object_match ? json_object_match[0] : cleaned_text
                    end

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

      # Recursively convert all hash keys to symbols
      def deep_symbolize_keys(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize_keys(v) }
        when Array
          obj.map { |item| deep_symbolize_keys(item) }
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

      # Execute a single attempt of a task with timeout
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
                   Timeout.timeout(timeout) do
                     execute_task_implementation(task, inputs)
                   end
                 else
                   execute_task_implementation(task, inputs)
                 end

        execution_time = Time.now - attempt_start
        logger.debug('Task execution completed',
                     task: task_name,
                     attempt: attempt + 1,
                     execution_time: execution_time.round(3))

        result
      rescue Timeout::Error => e
        execution_time = Time.now - attempt_start
        logger.warn('Task execution timed out',
                    task: task_name,
                    attempt: attempt + 1,
                    timeout: timeout,
                    execution_time: execution_time.round(3))
        raise TaskTimeoutError.new(task_name, "timed out after #{timeout}s", e)
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
        RETRYABLE_ERRORS.any? { |error_class| error.is_a?(error_class) }
      end

      # Categorize error for logging and operator integration
      #
      # @param error [Exception] The error that occurred
      # @return [Symbol] Error category
      def categorize_error(error)
        case error
        when ArgumentError, TaskValidationError
          :validation
        when Timeout::Error, TaskTimeoutError
          :timeout
        when TaskExecutionError
          # Check the original error for categorization
          error.original_error ? categorize_error(error.original_error) : :execution
        when *RETRYABLE_ERRORS
          :network
        else
          :execution
        end
      end

      # Calculate retry delay with exponential backoff
      #
      # @param attempt [Integer] Current attempt number (0-based)
      # @return [Float] Delay in seconds
      def calculate_retry_delay(attempt)
        delay = @config[:retry_delay_base] * (2**attempt)
        [delay, @config[:retry_delay_max]].min
      end

      # Create appropriate error type based on original error
      #
      # @param task_name [Symbol] Name of the task
      # @param original_error [Exception] The original error
      # @return [TaskExecutionError] Appropriate error type
      def create_appropriate_error(task_name, original_error)
        case original_error
        when TaskTimeoutError
          original_error
        when Timeout::Error
          TaskTimeoutError.new(task_name, 'timed out', original_error)
        when ArgumentError
          TaskValidationError.new(task_name, original_error.message, original_error)
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
    end
  end
end
