# frozen_string_literal: true

require 'opentelemetry/sdk'
require 'json'

module LanguageOperator
  module Instrumentation
    # OpenTelemetry instrumentation for task execution
    #
    # Provides comprehensive tracing for DSL v1 task execution including:
    # - Neural task execution (LLM calls with tool access)
    # - Symbolic task execution (direct Ruby code)
    # - Input/output validation
    # - Retry attempts
    # - Tool call tracking (when available)
    #
    # Follows OpenTelemetry Semantic Conventions for GenAI:
    # https://opentelemetry.io/docs/specs/semconv/gen-ai/
    #
    # @example Enable full data capture
    #   ENV['CAPTURE_TASK_INPUTS'] = 'true'
    #   ENV['CAPTURE_TASK_OUTPUTS'] = 'true'
    #   ENV['CAPTURE_TOOL_ARGS'] = 'true'
    #
    # @example Performance overhead
    #   Instrumentation adds <5% overhead with default settings
    #   Overhead may increase to ~10% with full data capture enabled
    #
    # rubocop:disable Metrics/ModuleLength
    module TaskTracer
      # Maximum length for captured data before truncation
      MAX_CAPTURED_LENGTH = 1000

      private

      # Check if data capture is enabled for a specific type
      #
      # @param type [Symbol] Type of data (:inputs, :outputs, :tool_args, :tool_results)
      # @return [Boolean] Whether capture is enabled
      def capture_enabled?(type)
        case type
        when :inputs
          ENV['CAPTURE_TASK_INPUTS'] == 'true'
        when :outputs
          ENV['CAPTURE_TASK_OUTPUTS'] == 'true'
        when :tool_args
          ENV['CAPTURE_TOOL_ARGS'] == 'true'
        when :tool_results
          ENV['CAPTURE_TOOL_RESULTS'] == 'true'
        else
          false
        end
      end

      # Sanitize data for span attributes
      #
      # By default, only captures metadata (sizes, counts).
      # Full data capture requires explicit opt-in via environment variables.
      #
      # @param data [Object] Data to sanitize
      # @param type [Symbol] Type of data for capture control
      # @param max_length [Integer] Maximum length before truncation
      # @return [String, nil] Sanitized string or nil if capture disabled
      def sanitize_data(data, type, max_length: MAX_CAPTURED_LENGTH)
        return nil unless capture_enabled?(type)

        str = case data
              when String then data
              when Hash then JSON.generate(data)
              else data.to_s
              end

        # Truncate if too long
        if str.length > max_length
          "#{str[0...max_length]}... (truncated #{str.length - max_length} chars)"
        else
          str
        end
      rescue StandardError => e
        logger&.warn('Failed to sanitize data for tracing', error: e.message)
        nil
      end

      # Build attributes for neural task span following GenAI semantic conventions
      #
      # @param task [TaskDefinition] The task definition
      # @param prompt [String] The generated prompt
      # @param validated_inputs [Hash] Validated input parameters
      # @return [Hash] Span attributes
      def neural_task_attributes(task, prompt, validated_inputs)
        attributes = {
          'gen_ai.operation.name' => 'chat',
          'gen_ai.system' => determine_genai_system,
          'gen_ai.prompt.size' => prompt.bytesize
        }

        # Add agent context (CRITICAL for learning system)
        add_agent_context_attributes(attributes)

        # Add task identification
        attributes['task.name'] = task.name.to_s if task.respond_to?(:name) && task.name

        # Add model if available
        if @agent.respond_to?(:config) && @agent.config
          model = @agent.config.dig('llm', 'model') || @agent.config['model']
          attributes['gen_ai.request.model'] = model if model
        end

        # Add sanitized prompt if capture enabled
        if (sanitized_prompt = sanitize_data(prompt, :inputs))
          attributes['gen_ai.prompt'] = sanitized_prompt
        end

        # Add input metadata
        attributes['task.input.keys'] = validated_inputs.keys.map(&:to_s).join(',')
        attributes['task.input.count'] = validated_inputs.size

        attributes
      end

      # Determine GenAI system identifier from agent configuration
      #
      # @return [String] GenAI system identifier
      def determine_genai_system
        return 'ruby_llm' unless @agent.respond_to?(:config)

        provider = @agent.config.dig('llm', 'provider') ||
                   @agent.config['provider'] ||
                   'ruby_llm'

        provider.to_s
      end

      # Build attributes for symbolic task span
      #
      # @param task [TaskDefinition] The task definition
      # @return [Hash] Span attributes
      def symbolic_task_attributes(task)
        attributes = {
          'task.execution.type' => 'symbolic',
          'task.execution.has_block' => task.execute_block ? 'true' : 'false',
          'gen_ai.operation.name' => 'execute_task'
        }

        # Add agent context (CRITICAL for learning system)
        add_agent_context_attributes(attributes)

        # Add task identification
        attributes['task.name'] = task.name.to_s if task.respond_to?(:name) && task.name

        attributes
      end

      # Record token usage from LLM response on span
      #
      # @param response [Object] LLM response object
      # @param span [OpenTelemetry::Trace::Span] The span to update
      def record_token_usage(response, span)
        return unless response

        span.set_attribute('gen_ai.usage.input_tokens', response.input_tokens.to_i) if response.respond_to?(:input_tokens) && response.input_tokens

        span.set_attribute('gen_ai.usage.output_tokens', response.output_tokens.to_i) if response.respond_to?(:output_tokens) && response.output_tokens

        # Try to get model from response if available
        span.set_attribute('gen_ai.response.model', response.model.to_s) if response.respond_to?(:model) && response.model

        # Try to get response ID if available
        span.set_attribute('gen_ai.response.id', response.id.to_s) if response.respond_to?(:id) && response.id

        # Try to get finish reason if available
        span.set_attribute('gen_ai.response.finish_reasons', response.stop_reason.to_s) if response.respond_to?(:stop_reason) && response.stop_reason
      rescue StandardError => e
        logger&.warn('Failed to record token usage', error: e.message)
      end

      # Record tool calls from LLM response
      #
      # Attempts to extract tool call information from the response object
      # and create child spans for each tool invocation.
      #
      # @param response [Object] LLM response object
      # @param parent_span [OpenTelemetry::Trace::Span] Parent span
      def record_tool_calls(response, parent_span)
        return unless response.respond_to?(:tool_calls)
        return unless response.tool_calls&.any?

        logger&.info('Tool calls detected in LLM response',
                     event: 'tool_calls_detected',
                     tool_call_count: response.tool_calls.length,
                     tool_names: response.tool_calls.map { |tc| extract_tool_name(tc) })

        response.tool_calls.each do |tool_call|
          record_single_tool_call(tool_call, parent_span)
        end
      rescue StandardError => e
        logger&.warn('Failed to record tool calls', error: e.message)
      end

      # Record a single tool call as a span
      #
      # @param tool_call [Object] Tool call object
      # @param parent_span [OpenTelemetry::Trace::Span] Parent span
      def record_single_tool_call(tool_call, _parent_span)
        tool_name = extract_tool_name(tool_call)
        tool_id = tool_call.respond_to?(:id) ? tool_call.id : nil

        # Extract and log tool arguments
        arguments = extract_tool_arguments(tool_call)

        logger&.info('Tool invoked by LLM',
                     event: 'tool_call_invoked',
                     tool_name: tool_name,
                     tool_id: tool_id,
                     arguments: arguments,
                     arguments_json: (arguments.is_a?(Hash) ? JSON.generate(arguments) : arguments.to_s))

        start_time = Time.now
        tracer.in_span("execute_tool #{tool_name}", attributes: build_tool_call_attributes(tool_call)) do |tool_span|
          # Tool execution already completed by ruby_llm
          # Just record the metadata
          if tool_call.respond_to?(:result) && tool_call.result
            duration_ms = ((Time.now - start_time) * 1000).round(2)
            record_tool_result(tool_call.result, tool_span, tool_name, tool_id, duration_ms)
          end
        end
      rescue StandardError => e
        logger&.warn('Failed to record tool call span', error: e.message, tool: tool_name)
      end

      # Extract tool name from tool call object
      #
      # @param tool_call [Object] Tool call object
      # @return [String] Tool name
      def extract_tool_name(tool_call)
        if tool_call.respond_to?(:name)
          tool_call.name.to_s
        elsif tool_call.respond_to?(:function) && tool_call.function.respond_to?(:name)
          tool_call.function.name.to_s
        else
          'unknown'
        end
      end

      # Extract tool arguments from tool call object
      #
      # @param tool_call [Object] Tool call object
      # @return [Hash, String] Tool arguments
      def extract_tool_arguments(tool_call)
        if tool_call.respond_to?(:arguments)
          args = tool_call.arguments
          parse_json_args(args)
        elsif tool_call.respond_to?(:function) && tool_call.function.respond_to?(:arguments)
          args = tool_call.function.arguments
          parse_json_args(args)
        else
          {}
        end
      end

      # Parse JSON arguments safely
      #
      # @param args [String, Object] Arguments to parse
      # @return [Hash, String] Parsed arguments or original
      def parse_json_args(args)
        return args unless args.is_a?(String)

        JSON.parse(args)
      rescue JSON::ParserError
        args
      end

      # Build attributes for tool call span
      #
      # @param tool_call [Object] Tool call object
      # @return [Hash] Span attributes
      def build_tool_call_attributes(tool_call)
        attributes = {
          'gen_ai.operation.name' => 'execute_tool',
          'gen_ai.tool.name' => extract_tool_name(tool_call)
        }

        # Add agent context (CRITICAL for learning system)
        add_agent_context_attributes(attributes)

        # Add tool call ID if available
        attributes['gen_ai.tool.call.id'] = tool_call.id.to_s if tool_call.respond_to?(:id) && tool_call.id

        # Add arguments if available and capture enabled
        if tool_call.respond_to?(:arguments) && tool_call.arguments
          args_str = tool_call.arguments.is_a?(String) ? tool_call.arguments : JSON.generate(tool_call.arguments)
          attributes['gen_ai.tool.call.arguments.size'] = args_str.bytesize

          if (sanitized_args = sanitize_data(tool_call.arguments, :tool_args))
            attributes['gen_ai.tool.call.arguments'] = sanitized_args
          end
        elsif tool_call.respond_to?(:function) && tool_call.function.respond_to?(:arguments)
          args = tool_call.function.arguments
          args_str = args.is_a?(String) ? args : JSON.generate(args)
          attributes['gen_ai.tool.call.arguments.size'] = args_str.bytesize

          if (sanitized_args = sanitize_data(args, :tool_args))
            attributes['gen_ai.tool.call.arguments'] = sanitized_args
          end
        end

        attributes
      end

      # Record tool call result on span
      #
      # @param result [Object] Tool call result
      # @param span [OpenTelemetry::Trace::Span] The span to update
      # @param tool_name [String] Tool name (for logging)
      # @param tool_id [String] Tool call ID (for logging)
      # @param duration_ms [Float] Execution duration in milliseconds (for logging)
      def record_tool_result(result, span, tool_name = nil, tool_id = nil, duration_ms = nil)
        result_str = result.is_a?(String) ? result : JSON.generate(result)
        span.set_attribute('gen_ai.tool.call.result.size', result_str.bytesize)

        if (sanitized_result = sanitize_data(result, :tool_results))
          span.set_attribute('gen_ai.tool.call.result', sanitized_result)
        end

        # Log tool execution completion
        logger&.info('Tool execution completed',
                     event: 'tool_call_completed',
                     tool_name: tool_name,
                     tool_id: tool_id,
                     result_size: result_str.bytesize,
                     result: sanitize_data(result, :tool_results),
                     duration_ms: duration_ms)
      rescue StandardError => e
        logger&.warn('Failed to record tool result', error: e.message)
      end

      # Record response parsing metadata
      #
      # @param response_text [String] Raw response text
      # @param span [OpenTelemetry::Trace::Span] The span to update
      def record_parse_metadata(response_text, span)
        span.set_attribute('gen_ai.completion.size', response_text.bytesize)

        # Add sanitized completion if capture enabled
        if (sanitized_completion = sanitize_data(response_text, :outputs))
          span.set_attribute('gen_ai.completion', sanitized_completion)
        end
      rescue StandardError => e
        logger&.warn('Failed to record parse metadata', error: e.message)
      end

      # Record output validation metadata
      #
      # @param outputs [Hash] Task outputs
      # @param span [OpenTelemetry::Trace::Span] The span to update
      def record_output_metadata(outputs, span)
        span.set_attribute('task.output.keys', outputs.keys.map(&:to_s).join(','))
        span.set_attribute('task.output.count', outputs.size)
      rescue StandardError => e
        logger&.warn('Failed to record output metadata', error: e.message)
      end

      # Add agent context attributes to span attributes hash
      #
      # Ensures all spans include agent identification required for learning system.
      # This is redundant with resource attributes but provides explicit visibility.
      #
      # @param attributes [Hash] Span attributes hash to modify
      def add_agent_context_attributes(attributes)
        # Agent name is CRITICAL for learning controller to track executions
        if (agent_name = ENV.fetch('AGENT_NAME', nil))
          attributes['agent.name'] = agent_name
        end

        # Add agent mode for better traceability
        if (agent_mode = ENV.fetch('AGENT_MODE', nil))
          attributes['agent.mode'] = agent_mode
        end

        # Add cluster context if available
        if (cluster_name = ENV.fetch('AGENT_CLUSTER', nil))
          attributes['agent.cluster'] = cluster_name
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
