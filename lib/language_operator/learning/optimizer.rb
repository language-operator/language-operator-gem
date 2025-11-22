# frozen_string_literal: true

require 'logger'

module LanguageOperator
  module Learning
    # Orchestrates the optimization of neural tasks to symbolic implementations
    #
    # The Optimizer analyzes running agents, identifies optimization opportunities,
    # proposes code changes, and applies them with user approval. It integrates
    # TraceAnalyzer (pattern detection) and PatternDetector (code generation) to
    # provide a complete optimization workflow.
    #
    # @example Basic usage
    #   optimizer = Optimizer.new(
    #     agent_name: 'github-monitor',
    #     agent_definition: agent_def,
    #     trace_analyzer: TraceAnalyzer.new(endpoint: ENV['OTEL_QUERY_ENDPOINT']),
    #     pattern_detector: PatternDetector.new(...)
    #   )
    #
    #   opportunities = optimizer.analyze
    #   opportunities.each do |opp|
    #     proposal = optimizer.propose(task_name: opp[:task_name])
    #     # Show to user, get approval
    #     optimizer.apply(proposal) if approved
    #   end
    # rubocop:disable Metrics/ClassLength
    class Optimizer
      # Minimum consistency score required for optimization
      DEFAULT_MIN_CONSISTENCY = 0.85

      # Minimum executions required for optimization
      DEFAULT_MIN_EXECUTIONS = 10

      # Initialize optimizer
      #
      # @param agent_name [String] Name of the agent to optimize
      # @param agent_definition [Dsl::AgentDefinition] Agent definition object
      # @param trace_analyzer [TraceAnalyzer] Analyzer for querying execution traces
      # @param pattern_detector [PatternDetector] Detector for generating symbolic code
      # @param task_synthesizer [TaskSynthesizer, nil] Optional LLM-based synthesizer
      # @param semantic_validator [SemanticValidator, nil] Optional semantic code validator
      # @param logger [Logger, nil] Logger instance (creates default if nil)
      def initialize(agent_name:, agent_definition:, trace_analyzer:, pattern_detector:, task_synthesizer: nil,
                     semantic_validator: nil, logger: nil)
        @agent_name = agent_name
        @agent_definition = agent_definition
        @trace_analyzer = trace_analyzer
        @pattern_detector = pattern_detector
        @task_synthesizer = task_synthesizer
        @semantic_validator = semantic_validator
        @logger = logger || ::Logger.new($stdout, level: ::Logger::WARN)
      end

      # Analyze agent for optimization opportunities
      #
      # Queries execution traces for each neural task and determines which tasks
      # are eligible for optimization based on consistency and execution count.
      #
      # @param min_consistency [Float] Minimum consistency threshold (0.0-1.0)
      # @param min_executions [Integer] Minimum execution count required
      # @param time_range [Integer, Range<Time>, nil] Time range for trace queries
      # @return [Array<Hash>] Array of optimization opportunities
      def analyze(min_consistency: DEFAULT_MIN_CONSISTENCY, min_executions: DEFAULT_MIN_EXECUTIONS, time_range: nil)
        opportunities = []

        # Find all neural tasks in the agent
        neural_tasks = find_neural_tasks

        if neural_tasks.empty?
          @logger.info("No neural tasks found in agent '#{@agent_name}'")
          return opportunities
        end

        # Analyze each neural task
        neural_tasks.each do |task|
          analysis = @trace_analyzer.analyze_patterns(
            task_name: task[:name],
            agent_name: @agent_name,
            min_executions: min_executions,
            consistency_threshold: min_consistency,
            time_range: time_range
          )

          next unless analysis

          opportunities << {
            task_name: task[:name],
            task_definition: task[:definition],
            execution_count: analysis[:execution_count],
            consistency_score: analysis[:consistency_score],
            ready_for_learning: analysis[:ready_for_learning],
            common_pattern: analysis[:common_pattern],
            reason: analysis[:reason]
          }
        end

        opportunities
      end

      # Generate optimization proposal for a specific task
      #
      # Uses PatternDetector to generate symbolic code and calculates
      # the performance impact of the optimization. Falls back to TaskSynthesizer
      # (LLM-based) if pattern detection fails and synthesizer is available.
      #
      # @param task_name [String] Name of task to optimize
      # @param use_synthesis [Boolean] Force use of LLM synthesis instead of pattern detection
      # @return [Hash] Optimization proposal with code, metrics, and metadata
      def propose(task_name:, use_synthesis: false)
        task_def = find_task_definition(task_name)
        raise ArgumentError, "Task '#{task_name}' not found" unless task_def

        analysis = @trace_analyzer.analyze_patterns(task_name: task_name, agent_name: @agent_name)
        raise ArgumentError, "No execution data found for task '#{task_name}'" unless analysis

        traces = @trace_analyzer.query_task_traces(task_name: task_name, agent_name: @agent_name, limit: 20)
        detection_result = @pattern_detector.detect_pattern(analysis_result: analysis) unless use_synthesis

        return propose_via_synthesis(task_name, task_def, analysis, traces) if should_use_synthesis?(use_synthesis, detection_result)

        unless detection_result&.dig(:success)
          raise ArgumentError, "Cannot optimize task '#{task_name}': #{detection_result&.dig(:reason) || 'No common pattern found'}"
        end

        build_pattern_proposal(task_name, task_def, analysis, detection_result)
      end

      # Apply optimization proposal
      #
      # This method would update the agent definition in Kubernetes.
      # For now, it returns the updated agent code that would be applied.
      #
      # @param proposal [Hash] Proposal from #propose
      # @return [Hash] Result with updated agent definition
      def apply(proposal:)
        # In a real implementation, this would:
        # 1. Update the agent CRD with new task definition
        # 2. Create new ConfigMap version
        # 3. Trigger pod restart
        # For now, we return what would be applied

        {
          success: true,
          task_name: proposal[:task_name],
          updated_code: proposal[:proposed_code],
          action: 'would_update_agent_definition',
          message: "Optimization for '#{proposal[:task_name]}' ready to apply"
        }
      end

      private

      def should_use_synthesis?(use_synthesis, detection_result)
        (use_synthesis || !detection_result&.dig(:success)) && @task_synthesizer
      end

      def propose_via_synthesis(task_name, task_def, analysis, traces)
        @logger.info("Using LLM synthesis for task '#{task_name}'")
        synthesis_result = @task_synthesizer.synthesize(
          task_definition: task_def,
          traces: traces,
          available_tools: detect_available_tools(traces),
          consistency_score: analysis[:consistency_score],
          common_pattern: analysis[:common_pattern]
        )

        raise ArgumentError, "Cannot optimize task '#{task_name}': #{synthesis_result[:explanation]}" unless synthesis_result[:is_deterministic]

        build_synthesis_proposal(task_name: task_name, task_def: task_def, analysis: analysis,
                                 synthesis_result: synthesis_result)
      end

      def build_pattern_proposal(task_name, task_def, analysis, detection_result)
        impact = calculate_impact(execution_count: analysis[:execution_count],
                                  consistency_score: analysis[:consistency_score])

        proposed_code = extract_task_code(detection_result[:generated_code])

        # Add semantic validation if validator available
        all_violations = detection_result[:validation_violations].dup
        if @semantic_validator
          semantic_result = @semantic_validator.validate(code: proposed_code, task_definition: task_def)
          all_violations.concat(semantic_result[:violations]) unless semantic_result[:valid]
        end

        {
          task_name: task_name,
          task_definition: task_def,
          current_code: format_current_code(task_def),
          proposed_code: proposed_code,
          full_generated_code: detection_result[:generated_code],
          consistency_score: analysis[:consistency_score], execution_count: analysis[:execution_count],
          pattern: analysis[:common_pattern], performance_impact: impact,
          validation_violations: all_violations,
          ready_to_deploy: all_violations.empty? && detection_result[:ready_to_deploy],
          synthesis_method: :pattern_detection
        }
      end

      # Find all neural tasks in the agent definition
      #
      # @return [Array<Hash>] Array of neural task info
      def find_neural_tasks
        return [] unless @agent_definition.respond_to?(:tasks)

        neural_tasks = @agent_definition.tasks.select do |_name, task_def|
          # Neural tasks have instructions but no code block
          task_def.neural?
        end

        neural_tasks.map do |name, task_def|
          {
            name: name.to_s,
            definition: task_def
          }
        end
      end

      # Find a specific task definition by name
      #
      # @param task_name [String] Task name
      # @return [Dsl::TaskDefinition, nil] Task definition or nil
      def find_task_definition(task_name)
        return nil unless @agent_definition.respond_to?(:tasks)

        @agent_definition.tasks[task_name.to_sym]
      end

      # Format current task code for display
      #
      # @param task_def [Dsl::TaskDefinition] Task definition
      # @return [String] Formatted code
      def format_current_code(task_def)
        inputs_str = (task_def.inputs || {}).map { |k, v| "#{k}: '#{v}'" }.join(', ')
        outputs_str = (task_def.outputs || {}).map { |k, v| "#{k}: '#{v}'" }.join(', ')

        <<~RUBY
          task :#{task_def.name},
            instructions: "#{task_def.instructions}",
            inputs: { #{inputs_str} },
            outputs: { #{outputs_str} }
        RUBY
      end

      # Extract task code from full agent definition
      #
      # @param full_code [String] Complete agent definition
      # @return [String] Just the task definition portion
      def extract_task_code(full_code)
        # Extract just the task definition from the full agent code
        lines = full_code.lines
        task_start = lines.index { |l| l.strip.start_with?('task :') }
        task_end = lines.index { |l| l.strip == 'end' && l.start_with?('      end') }

        return full_code unless task_start && task_end

        lines[task_start..task_end].join
      end

      # Calculate performance impact of optimization
      #
      # @param execution_count [Integer] Number of executions observed
      # @param consistency_score [Float] Pattern consistency
      # @return [Hash] Impact metrics
      def calculate_impact(execution_count:, consistency_score:)
        # Estimates based on typical LLM vs symbolic execution
        avg_neural_time = 2.5 # seconds
        avg_neural_cost = 0.003 # dollars
        avg_symbolic_time = 0.1 # seconds
        avg_symbolic_cost = 0.0 # dollars

        time_saved = avg_neural_time - avg_symbolic_time
        cost_saved = avg_neural_cost - avg_symbolic_cost

        {
          current_avg_time: avg_neural_time,
          optimized_avg_time: avg_symbolic_time,
          time_reduction_pct: ((time_saved / avg_neural_time) * 100).round(1),
          current_avg_cost: avg_neural_cost,
          optimized_avg_cost: avg_symbolic_cost,
          cost_reduction_pct: ((cost_saved / avg_neural_cost) * 100).round(1),
          projected_monthly_savings: (cost_saved * execution_count * 30).round(2)
        }
      end

      # Build proposal from synthesis result
      #
      # @param task_name [String] Task name
      # @param task_def [Dsl::TaskDefinition] Task definition
      # @param analysis [Hash] Pattern analysis result
      # @param synthesis_result [Hash] LLM synthesis result
      # @return [Hash] Optimization proposal
      def build_synthesis_proposal(task_name:, task_def:, analysis:, synthesis_result:)
        impact = calculate_impact(
          execution_count: analysis[:execution_count],
          consistency_score: synthesis_result[:confidence]
        )

        # Collect all validation violations
        all_violations = synthesis_result[:validation_errors] || []

        # Add semantic validation if validator available
        if @semantic_validator
          semantic_result = @semantic_validator.validate(
            code: synthesis_result[:code],
            task_definition: task_def
          )
          all_violations.concat(semantic_result[:violations]) unless semantic_result[:valid]
        end

        {
          task_name: task_name,
          task_definition: task_def,
          current_code: format_current_code(task_def),
          proposed_code: synthesis_result[:code],
          full_generated_code: synthesis_result[:code],
          consistency_score: analysis[:consistency_score],
          execution_count: analysis[:execution_count],
          pattern: analysis[:common_pattern],
          performance_impact: impact,
          validation_violations: all_violations,
          ready_to_deploy: all_violations.empty?,
          synthesis_method: :llm_synthesis,
          synthesis_confidence: synthesis_result[:confidence],
          synthesis_explanation: synthesis_result[:explanation]
        }
      end

      # Detect available tools from agent definition
      #
      # @return [Array<String>] Tool names
      def detect_available_tools(traces)
        # Extract unique tool names from execution traces
        tools = traces.flat_map do |trace|
          (trace[:tool_calls] || []).map { |tc| tc[:tool_name] }
        end.compact.uniq.sort

        @logger.debug("Detected tools from traces: #{tools.join(', ')}") if tools.any?
        tools
      rescue StandardError => e
        @logger.warn("Failed to detect tools from traces: #{e.message}")
        []
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
