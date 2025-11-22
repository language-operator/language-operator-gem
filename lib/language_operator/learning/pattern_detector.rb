# frozen_string_literal: true

require 'logger'

module LanguageOperator
  module Learning
    # Detects patterns in task execution traces and generates symbolic code
    #
    # The PatternDetector analyzes execution patterns from TraceAnalyzer and
    # converts deterministic neural task behavior into symbolic Ruby DSL v1 code.
    # This enables the learning system to automatically optimize neural tasks
    # into faster, cheaper symbolic implementations.
    #
    # @example Basic usage
    #   analyzer = TraceAnalyzer.new(endpoint: ENV['OTEL_QUERY_ENDPOINT'])
    #   validator = Agent::Safety::ASTValidator.new
    #   detector = PatternDetector.new(trace_analyzer: analyzer, validator: validator)
    #
    #   analysis = analyzer.analyze_patterns(task_name: 'fetch_user_data')
    #   result = detector.detect_pattern(analysis_result: analysis)
    #
    #   if result[:success]
    #     puts "Generated code:"
    #     puts result[:generated_code]
    #   end
    class PatternDetector
      # Default minimum consistency threshold for learning
      DEFAULT_CONSISTENCY_THRESHOLD = 0.85

      # Default minimum executions required before learning
      DEFAULT_MIN_EXECUTIONS = 10

      # Minimum pattern confidence for code generation
      MIN_PATTERN_CONFIDENCE = 0.75

      # Initialize pattern detector
      #
      # @param trace_analyzer [TraceAnalyzer] Analyzer for querying execution traces
      # @param validator [Agent::Safety::ASTValidator] Validator for generated code
      # @param logger [Logger, nil] Logger instance (creates default if nil)
      def initialize(trace_analyzer:, validator:, logger: nil)
        @trace_analyzer = trace_analyzer
        @validator = validator
        @logger = logger || ::Logger.new($stdout, level: ::Logger::WARN)
      end

      # Detect patterns and generate symbolic code
      #
      # Main entry point for pattern detection. Takes analysis results from
      # TraceAnalyzer and generates validated symbolic code if the pattern
      # meets consistency and execution count thresholds.
      #
      # @param analysis_result [Hash] Result from TraceAnalyzer#analyze_patterns
      # @return [Hash] Detection result with generated code and metadata
      def detect_pattern(analysis_result:)
        # Validate that we can generate code from this analysis
        return early_rejection_result(analysis_result) unless can_generate_code?(analysis_result)

        # Generate symbolic code from the pattern
        code = generate_symbolic_code(
          pattern: analysis_result[:common_pattern],
          task_name: analysis_result[:task_name]
        )

        # Validate the generated code
        validation_result = validate_generated_code(code: code)

        # Build result
        {
          success: validation_result[:valid],
          task_name: analysis_result[:task_name],
          generated_code: code,
          validation_violations: validation_result[:violations],
          consistency_score: analysis_result[:consistency_score],
          execution_count: analysis_result[:execution_count],
          pattern: analysis_result[:common_pattern],
          ready_to_deploy: validation_result[:valid] && analysis_result[:consistency_score] >= 0.90,
          generated_at: Time.now.iso8601
        }
      end

      # Generate symbolic Ruby code from tool call pattern
      #
      # Converts a deterministic tool call sequence into a valid Ruby DSL v1
      # task definition with chained execute_tool calls.
      #
      # @param pattern [String] Tool sequence like "db_fetch → cache_get → api"
      # @param task_name [String] Name of the task being learned
      # @param task_definition [Dsl::TaskDefinition, nil] Optional task definition for schema
      # @param fragment_only [Boolean] If true, returns only task fragment (default: false)
      # @return [String] Complete Ruby DSL v1 agent definition or task fragment
      def generate_symbolic_code(pattern:, task_name:, task_definition: nil, fragment_only: false)
        sequence = extract_tool_sequence(pattern)

        # Generate the task code body with chained execute_tool calls
        task_body = generate_task_code(sequence: sequence, task_definition: task_definition)

        if fragment_only
          # Generate just the task definition
          generate_task_fragment(
            task_name: task_name,
            task_body: task_body,
            task_definition: task_definition
          )
        else
          # Wrap in complete agent definition (backward compatibility)
          generate_agent_wrapper(
            task_name: task_name,
            task_body: task_body
          )
        end
      end

      # Validate generated code with ASTValidator
      #
      # @param code [String] Ruby code to validate
      # @return [Hash] Validation result with violations
      def validate_generated_code(code:)
        violations = @validator.validate(code)

        {
          valid: violations.empty?,
          violations: violations,
          safe_methods_used: true
        }
      rescue StandardError => e
        @logger.error("Failed to validate generated code: #{e.message}")
        {
          valid: false,
          violations: [{ type: :validation_error, message: e.message }],
          safe_methods_used: false
        }
      end

      private

      # Check if pattern analysis meets criteria for code generation
      #
      # @param analysis_result [Hash] Analysis result from TraceAnalyzer
      # @return [Boolean] True if code can be generated
      def can_generate_code?(analysis_result)
        return false unless analysis_result.is_a?(Hash)

        # Check if ready for learning flag is set
        return false unless analysis_result[:ready_for_learning]

        # Check execution count
        return false if analysis_result[:execution_count].to_i < DEFAULT_MIN_EXECUTIONS

        # Check consistency score
        return false if analysis_result[:consistency_score].to_f < DEFAULT_CONSISTENCY_THRESHOLD

        # Check pattern exists
        return false if analysis_result[:common_pattern].nil? || analysis_result[:common_pattern].empty?

        true
      end

      # Build early rejection result when criteria not met
      #
      # @param analysis_result [Hash, nil] Analysis result if available
      # @return [Hash] Rejection result with reason
      def early_rejection_result(analysis_result)
        if analysis_result.nil? || !analysis_result.is_a?(Hash)
          return {
            success: false,
            reason: 'Invalid analysis result'
          }
        end

        reasons = []
        if analysis_result[:execution_count].to_i < DEFAULT_MIN_EXECUTIONS
          reasons << "Insufficient executions (#{analysis_result[:execution_count]}/#{DEFAULT_MIN_EXECUTIONS})"
        end
        if analysis_result[:consistency_score].to_f < DEFAULT_CONSISTENCY_THRESHOLD
          reasons << "Low consistency (#{analysis_result[:consistency_score]}/#{DEFAULT_CONSISTENCY_THRESHOLD})"
        end
        reasons << 'No common pattern found' if analysis_result[:common_pattern].nil? || analysis_result[:common_pattern].empty?

        {
          success: false,
          task_name: analysis_result[:task_name],
          execution_count: analysis_result[:execution_count],
          consistency_score: analysis_result[:consistency_score],
          ready_for_learning: false,
          reason: reasons.join('; ')
        }
      end

      # Extract tool sequence from pattern string
      #
      # @param pattern [String] Pattern like "db_fetch → cache_get → api"
      # @return [Array<Symbol>] Sequence like [:db_fetch, :cache_get, :api]
      def extract_tool_sequence(pattern)
        pattern.split('→').map(&:strip).map(&:to_sym)
      end

      # Generate task code body with chained execute_tool calls
      #
      # Creates Ruby code that executes tools in sequence, passing outputs
      # from each tool to the next one as inputs.
      #
      # @param sequence [Array<Symbol>] Tool sequence
      # @param task_definition [Dsl::TaskDefinition, nil] Optional task definition for schema
      # @return [String] Ruby code for task body
      def generate_task_code(sequence:, task_definition: nil)
        # Determine the output structure from task definition
        output_keys = if task_definition&.outputs&.any?
                        task_definition.outputs.keys
                      else
                        [:result]
                      end

        return "      { #{output_keys.map { |k| "#{k}: {}" }.join(', ')} }" if sequence.empty?

        lines = []

        # First call: use original inputs
        first_tool = sequence[0]
        lines << "step1_result = execute_tool('#{first_tool}', inputs)"

        # Middle calls: chain outputs from previous step
        if sequence.size > 1
          sequence[1..-2].each_with_index do |tool, index|
            step_num = index + 2
            prev_step = "step#{step_num - 1}_result"
            lines << "step#{step_num}_result = execute_tool('#{tool}', #{prev_step})"
          end

          # Final call
          final_tool = sequence[-1]
          last_step = "step#{sequence.size - 1}_result"
          lines << "final_result = execute_tool('#{final_tool}', #{last_step})"
        else
          lines << 'final_result = step1_result'
        end

        # Return statement matching the output schema
        if output_keys.size == 1
          lines << "{ #{output_keys.first}: final_result }"
        else
          # For multiple output keys, try to map final_result intelligently
          # This is a simplification - real implementation might need more context
          lines << '# Map final_result to output schema'
          lines << '{'
          output_keys.each do |key|
            lines << "  #{key}: final_result[:#{key}] || final_result,"
          end
          lines << '}'
        end

        # Indent and join
        lines.map { |line| "      #{line}" }.join("\n")
      end

      # Generate task fragment (just the task definition)
      #
      # @param task_name [String] Name of the task
      # @param task_body [String] Generated task code body
      # @param task_definition [Dsl::TaskDefinition, nil] Optional task definition for schema
      # @return [String] Just the task definition
      def generate_task_fragment(task_name:, task_body:, task_definition: nil)
        # Use actual schema from task definition if available
        if task_definition
          inputs_str = (task_definition.inputs || {}).map { |k, v| "#{k}: '#{v}'" }.join(', ')
          outputs_str = (task_definition.outputs || {}).map { |k, v| "#{k}: '#{v}'" }.join(', ')
          task_definition.instructions
        else
          # Fallback to generic schema
          inputs_str = "data: 'hash'"
          outputs_str = "result: 'hash'"
          'Learned symbolic implementation from execution patterns'
        end

        <<~RUBY
          task :#{task_name},
               inputs: { #{inputs_str} },
               outputs: { #{outputs_str} } do |inputs|
          #{task_body}
          end
        RUBY
      end

      # Generate complete agent wrapper with task definition
      #
      # @param task_name [String] Name of the task
      # @param task_body [String] Generated task code body
      # @return [String] Complete Ruby DSL v1 agent definition
      def generate_agent_wrapper(task_name:, task_body:)
        # Convert task name to kebab-case for agent name
        agent_name = task_name.to_s.gsub('_', '-')

        <<~RUBY
          # frozen_string_literal: true

          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "#{agent_name}-symbolic" do
              description "Symbolic implementation of #{task_name} (learned from execution patterns)"

              task :core_pattern,
                inputs: { data: 'hash' },
                outputs: { result: 'hash' }
              do |inputs|
          #{task_body}
              end

              main do |inputs|
                execute_task(:core_pattern, inputs: inputs)
              end
            end
          end
        RUBY
      end
    end
  end
end
