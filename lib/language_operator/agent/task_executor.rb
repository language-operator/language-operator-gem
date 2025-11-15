# frozen_string_literal: true

require_relative '../loggable'
require_relative 'instrumentation'

module LanguageOperator
  module Agent
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

      attr_reader :agent, :tasks

      # Initialize the task executor
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance (provides LLM client, tools)
      # @param tasks [Hash<Symbol, TaskDefinition>] Registry of task definitions
      def initialize(agent, tasks = {})
        @agent = agent
        @tasks = tasks
        logger.debug('TaskExecutor initialized', task_count: @tasks.size)
      end

      # Execute a task by name with given inputs
      #
      # This is the main entry point called from MainDefinition blocks.
      # Routes to neural or symbolic execution based on task implementation.
      #
      # @param task_name [Symbol] Name of the task to execute
      # @param inputs [Hash] Input parameters for the task
      # @return [Hash] Validated output from the task
      # @raise [ArgumentError] If task not found or inputs invalid
      # @raise [RuntimeError] If task execution fails
      def execute_task(task_name, inputs: {})
        with_span('task_executor.execute_task', attributes: {
                    'task.name' => task_name.to_s,
                    'task.inputs' => inputs.keys.map(&:to_s).join(',')
                  }) do
          # Find task definition
          task = @tasks[task_name.to_sym]
          raise ArgumentError, "Task not found: #{task_name}. Available tasks: #{@tasks.keys.join(', ')}" unless task

          task_type = if task.neural? && task.symbolic?
                        'hybrid'
                      elsif task.neural?
                        'neural'
                      elsif task.symbolic?
                        'symbolic'
                      else
                        'undefined'
                      end
          logger.info('Executing task', task: task_name, type: task_type)

          # Task validation and execution happens in TaskDefinition#call
          # which handles input validation, type coercion, and output validation
          if task.neural?
            # Neural execution: LLM with tool access
            execute_neural(task, inputs)
          else
            # Symbolic execution: Direct Ruby code
            # Pass self as context so symbolic tasks can call execute_task, execute_tool, etc.
            task.call(inputs, self)
          end
        end
      rescue ArgumentError => e
        # Re-raise validation errors with clear context for re-synthesis
        logger.error('Task execution failed - validation error',
                     task: task_name,
                     error: e.message)
        raise
      rescue StandardError => e
        # Fail fast on execution errors (critical for operator re-synthesis)
        logger.error('Task execution failed',
                     task: task_name,
                     error: e.class.name,
                     message: e.message,
                     backtrace: e.backtrace&.first(3))
        raise "Task '#{task_name}' execution failed: #{e.message}"
      end

      # Execute a neural task (instructions-based, LLM-driven)
      #
      # @param task [TaskDefinition] The task definition
      # @param inputs [Hash] Input parameters (already validated by task.call)
      # @return [Hash] Validated outputs
      # @raise [RuntimeError] If LLM execution fails or output validation fails
      def execute_neural(task, inputs)
        # Validate inputs first
        validated_inputs = task.validate_inputs(inputs)

        logger.debug('Executing neural task',
                     task: task.name,
                     instructions: task.instructions_text,
                     inputs: validated_inputs)

        # Build prompt for LLM
        prompt = build_neural_prompt(task, validated_inputs)

        # Call LLM with full tool access
        response = @agent.send_message(prompt)
        response_text = response.is_a?(String) ? response : response.content

        logger.debug('Neural task response received',
                     task: task.name,
                     response_length: response_text.length)

        # Parse response and extract outputs
        # For now, assume LLM returns valid JSON matching output schema
        # TODO: More sophisticated parsing/extraction
        outputs = parse_neural_response(response_text, task)

        # Validate outputs against schema
        task.validate_outputs(outputs)
      rescue StandardError => e
        logger.error('Neural task execution failed',
                     task: task.name,
                     error: e.message)
        raise "Neural task '#{task.name}' failed: #{e.message}"
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

        prompt += 'Return ONLY valid JSON matching the output schema. '
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
        # Try to extract JSON from response
        # Look for JSON code blocks first
        json_match = response_text.match(/```json\s*\n(.*?)\n```/m)
        json_text = if json_match
                      json_match[1]
                    else
                      # Try to find raw JSON object
                      json_object_match = response_text.match(/\{.*\}/m)
                      json_object_match ? json_object_match[0] : response_text
                    end

        # Parse JSON
        parsed = JSON.parse(json_text)

        # Convert string keys to symbols
        parsed.is_a?(Hash) ? parsed.transform_keys(&:to_sym) : parsed
      rescue JSON::ParserError => e
        logger.error('Failed to parse neural task response as JSON',
                     task: task.name,
                     response: response_text[0..200],
                     error: e.message)
        raise "Neural task '#{task.name}' returned invalid JSON: #{e.message}"
      end
    end
  end
end
