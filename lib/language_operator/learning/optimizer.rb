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
      # @param logger [Logger, nil] Logger instance (creates default if nil)
      def initialize(agent_name:, agent_definition:, trace_analyzer:, pattern_detector:, logger: nil)
        @agent_name = agent_name
        @agent_definition = agent_definition
        @trace_analyzer = trace_analyzer
        @pattern_detector = pattern_detector
        @logger = logger || ::Logger.new($stdout, level: ::Logger::WARN)
      end

      # Analyze agent for optimization opportunities
      #
      # Queries execution traces for each neural task and determines which tasks
      # are eligible for optimization based on consistency and execution count.
      #
      # @param min_consistency [Float] Minimum consistency threshold (0.0-1.0)
      # @param min_executions [Integer] Minimum execution count required
      # @return [Array<Hash>] Array of optimization opportunities
      def analyze(min_consistency: DEFAULT_MIN_CONSISTENCY, min_executions: DEFAULT_MIN_EXECUTIONS)
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
            min_executions: min_executions,
            consistency_threshold: min_consistency
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
      # the performance impact of the optimization.
      #
      # @param task_name [String] Name of task to optimize
      # @return [Hash] Optimization proposal with code, metrics, and metadata
      def propose(task_name:)
        # Find the task definition
        task_def = find_task_definition(task_name)
        raise ArgumentError, "Task '#{task_name}' not found" unless task_def

        # Get analysis from TraceAnalyzer
        analysis = @trace_analyzer.analyze_patterns(task_name: task_name)
        raise ArgumentError, "No execution data found for task '#{task_name}'" unless analysis

        # Generate symbolic code using PatternDetector
        detection_result = @pattern_detector.detect_pattern(analysis_result: analysis)

        raise ArgumentError, "Cannot optimize task '#{task_name}': #{detection_result[:reason]}" unless detection_result[:success]

        # Calculate performance impact
        impact = calculate_impact(
          execution_count: analysis[:execution_count],
          consistency_score: analysis[:consistency_score]
        )

        # Build proposal
        {
          task_name: task_name,
          current_code: format_current_code(task_def),
          proposed_code: extract_task_code(detection_result[:generated_code]),
          full_generated_code: detection_result[:generated_code],
          consistency_score: analysis[:consistency_score],
          execution_count: analysis[:execution_count],
          pattern: analysis[:common_pattern],
          performance_impact: impact,
          validation_violations: detection_result[:validation_violations],
          ready_to_deploy: detection_result[:ready_to_deploy]
        }
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
        inputs_str = task_def.inputs.map { |k, v| "#{k}: '#{v}'" }.join(', ')
        outputs_str = task_def.outputs.map { |k, v| "#{k}: '#{v}'" }.join(', ')

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
    end
  end
end
