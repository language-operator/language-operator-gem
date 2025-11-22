# frozen_string_literal: true

require 'json'

module LanguageOperator
  module Learning
    # Synthesizes deterministic code for neural tasks using LLM analysis
    #
    # TaskSynthesizer uses an LLM to analyze task definitions and execution traces,
    # then generates optimized Ruby code if the task can be made deterministic.
    # This approach can handle inconsistent traces better than pure pattern matching
    # because the LLM can understand intent and unify variations.
    #
    # @example Basic usage
    #   synthesizer = TaskSynthesizer.new(
    #     llm_client: my_llm_client,
    #     validator: ASTValidator.new
    #   )
    #
    #   result = synthesizer.synthesize(
    #     task_definition: task_def,
    #     traces: execution_traces,
    #     available_tools: tool_list
    #   )
    #
    #   if result[:is_deterministic]
    #     puts result[:code]
    #   end
    class TaskSynthesizer
      # Template file name
      TEMPLATE_FILE = 'task_synthesis.tmpl'

      # Initialize synthesizer
      #
      # @param llm_client [Object] Client for LLM API calls (must respond to #chat)
      # @param validator [Agent::Safety::ASTValidator] Code validator
      # @param logger [Logger, nil] Logger instance
      def initialize(llm_client:, validator:, logger: nil)
        @llm_client = llm_client
        @validator = validator
        @logger = logger || ::Logger.new($stdout, level: ::Logger::WARN)
      end

      # Synthesize deterministic code for a task
      #
      # @param task_definition [Dsl::TaskDefinition] Task to optimize
      # @param traces [Array<Hash>] Execution traces from TraceAnalyzer
      # @param available_tools [Array<String>] List of available tool names
      # @param consistency_score [Float] Current consistency score
      # @param common_pattern [String, nil] Most common tool pattern
      # @return [Hash] Synthesis result with :is_deterministic, :code, :explanation, :confidence
      def synthesize(task_definition:, traces:, available_tools: [], consistency_score: 0.0, common_pattern: nil)
        # Build prompt from template
        prompt = build_prompt(
          task_definition: task_definition,
          traces: traces,
          available_tools: available_tools,
          consistency_score: consistency_score,
          common_pattern: common_pattern
        )

        @logger.info("Task synthesis prompt:\n#{prompt}")

        # Call LLM
        response = call_llm(prompt)

        # Parse JSON response
        result = parse_response(response)

        # Validate generated code if present
        if result[:is_deterministic] && result[:code]
          validation = validate_code(result[:code])
          unless validation[:valid]
            @logger.warn("Generated code failed validation: #{validation[:errors].join(', ')}")
            result[:validation_errors] = validation[:errors]
            result[:is_deterministic] = false
            result[:explanation] = "Generated code failed safety validation: #{validation[:errors].first}"
          end
        end

        result
      rescue StandardError => e
        @logger.error("Task synthesis failed: #{e.message}")
        @logger.error(e.backtrace&.first(10)&.join("\n"))
        {
          is_deterministic: false,
          confidence: 0.0,
          explanation: "Synthesis error: #{e.message}",
          code: nil
        }
      end

      private

      # Build synthesis prompt from template
      #
      # @return [String] Rendered prompt
      def build_prompt(task_definition:, traces:, available_tools:, consistency_score:, common_pattern:)
        template = load_template

        # Pre-render traces since our template engine doesn't support loops
        traces_text = format_traces(traces)
        inputs_text = format_schema(task_definition.inputs)
        outputs_text = format_schema(task_definition.outputs)
        tools_text = available_tools.map { |t| "- #{t}" }.join("\n")

        # Count unique patterns
        unique_patterns = traces.map { |t| (t[:tool_calls] || []).map { |tc| tc[:tool_name] }.join(' → ') }.uniq.size

        # Build data hash for template substitution
        data = {
          'TaskName' => task_definition.name.to_s,
          'Instructions' => task_definition.instructions || '(none)',
          'Inputs' => inputs_text,
          'Outputs' => outputs_text,
          'TaskCode' => format_task_code(task_definition),
          'TraceCount' => traces.size.to_s,
          'Traces' => traces_text,
          'CommonPattern' => common_pattern || '(none detected)',
          'ConsistencyScore' => (consistency_score * 100).round(1).to_s,
          'UniquePatternCount' => unique_patterns.to_s,
          'ToolsList' => tools_text.empty? ? '(none available)' : tools_text
        }

        render_template(template, data)
      end

      # Load template file
      #
      # @return [String] Template content
      def load_template
        template_path = File.join(__dir__, '..', 'templates', TEMPLATE_FILE)
        File.read(template_path)
      end

      # Render Go-style template with data
      #
      # @param template [String] Template content
      # @param data [Hash] Data to substitute
      # @return [String] Rendered content
      def render_template(template, data)
        result = template.dup

        # Remove range blocks (we pre-render these)
        result.gsub!(/{{range.*?}}.*?{{end}}/m, '')

        # Remove if blocks for empty values
        result.gsub!(/{{if not \.Inputs}}.*?{{end}}/m, '')
        result.gsub!(/{{if \.InputSummary}}.*?{{end}}/m, '')

        # Replace simple variables {{.Variable}}
        data.each do |key, value|
          result.gsub!("{{.#{key}}}", value.to_s)
        end

        result
      end

      # Format traces for template
      #
      # @param traces [Array<Hash>] Execution traces
      # @return [String] Formatted traces text
      def format_traces(traces)
        return '(no traces available)' if traces.empty?

        traces.first(10).each_with_index.map do |trace, idx|
          format_single_trace(trace, idx)
        end.join("\n")
      end

      # Format a single trace execution
      #
      # @param trace [Hash] Single trace data
      # @param idx [Integer] Trace index
      # @return [String] Formatted trace
      def format_single_trace(trace, idx)
        tool_sequence = trace[:tool_calls]&.map { |tc| tc[:tool_name] }&.join(' → ') || '(no tools)'
        duration = trace[:duration_ms]&.round(1) || 'unknown'
        inputs_summary = trace[:inputs]&.keys&.join(', ') || 'none'
        tool_details = format_tool_calls(trace[:tool_calls])

        <<~TRACE
          ### Execution #{idx + 1}
          - **Tool Sequence:** #{tool_sequence}
          - **Duration:** #{duration}ms
          - **Inputs:** #{inputs_summary}
          - **Tool Calls:**
          #{tool_details}
        TRACE
      end

      # Format tool call details
      #
      # @param tool_calls [Array<Hash>, nil] Tool call data
      # @return [String] Formatted tool calls
      def format_tool_calls(tool_calls)
        return '  (no tool calls)' unless tool_calls&.any?

        tool_calls.map do |tc|
          details = "  - #{tc[:tool_name]}"
          details += "\n    Args: #{tc[:arguments]}" if tc[:arguments]
          details += "\n    Result: #{tc[:result]}" if tc[:result]
          details
        end.join("\n")
      end

      # Format schema hash as text
      #
      # @param schema [Hash] Input/output schema
      # @return [String] Formatted text
      def format_schema(schema)
        return '(none)' if schema.nil? || schema.empty?

        schema.map { |k, v| "- #{k}: #{v}" }.join("\n")
      end

      # Format task definition as Ruby code
      #
      # @param task_def [Dsl::TaskDefinition] Task definition
      # @return [String] Ruby code representation
      def format_task_code(task_def)
        inputs_str = (task_def.inputs || {}).map { |k, v| "#{k}: '#{v}'" }.join(', ')
        outputs_str = (task_def.outputs || {}).map { |k, v| "#{k}: '#{v}'" }.join(', ')

        <<~RUBY
          task :#{task_def.name},
            instructions: "#{task_def.instructions}",
            inputs: { #{inputs_str} },
            outputs: { #{outputs_str} }
        RUBY
      end

      # Call LLM with prompt
      #
      # @param prompt [String] Synthesis prompt
      # @return [String] LLM response
      def call_llm(prompt)
        @llm_client.chat(prompt)
      end

      # Parse JSON response from LLM
      #
      # @param response [String] LLM response text
      # @return [Hash] Parsed result
      def parse_response(response)
        # Extract JSON from response (may be wrapped in markdown code block)
        json_match = response.match(/```json\s*(.*?)\s*```/m) ||
                     response.match(/\{.*\}/m)

        json_str = json_match ? json_match[1] || json_match[0] : response

        parsed = JSON.parse(json_str, symbolize_names: true)

        {
          is_deterministic: parsed[:is_deterministic] == true,
          confidence: parsed[:confidence].to_f,
          explanation: parsed[:explanation] || 'No explanation provided',
          code: parsed[:code]
        }
      rescue JSON::ParserError => e
        @logger.warn("Failed to parse LLM response as JSON: #{e.message}")
        {
          is_deterministic: false,
          confidence: 0.0,
          explanation: "Failed to parse synthesis response: #{e.message}",
          code: nil
        }
      end

      # Validate generated code
      #
      # @param code [String] Ruby code to validate
      # @return [Hash] Validation result with :valid and :errors
      def validate_code(code)
        errors = @validator.validate(code)
        {
          valid: errors.empty?,
          errors: errors
        }
      rescue StandardError => e
        {
          valid: false,
          errors: ["Validation error: #{e.message}"]
        }
      end
    end
  end
end
