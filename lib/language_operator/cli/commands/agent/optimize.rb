# frozen_string_literal: true

require 'tty-prompt'

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Neural-to-symbolic optimization for agents
        module Optimize
          def self.included(base)
            base.class_eval do
              desc 'optimize NAME', 'Optimize neural tasks to symbolic based on learned patterns'
              long_desc <<-DESC
                Analyze agent execution patterns and propose optimizations to convert
                neural (LLM-based) tasks into symbolic (code-based) implementations.

                This command queries OpenTelemetry traces to detect deterministic patterns
                in task execution, then generates optimized symbolic code that runs faster
                and costs less while maintaining the same behavior.

                Requirements:
                  • OpenTelemetry backend configured (SigNoz, Jaeger, or Tempo)
                  • Neural task has executed at least 10 times
                  • Execution pattern consistency >= 85%

                Examples:
                  aictl agent optimize my-agent                    # Analyze and propose optimizations
                  aictl agent optimize my-agent --dry-run          # Show what would be optimized
                  aictl agent optimize my-agent --status-only      # Show learning status only
                  aictl agent optimize my-agent --auto-accept      # Auto-accept high-confidence optimizations
                  aictl agent optimize my-agent --tasks task1,task2  # Optimize specific tasks only
              DESC
              option :cluster, type: :string, desc: 'Override current cluster context'
              option :dry_run, type: :boolean, default: false, desc: 'Show what would be optimized without applying'
              option :status_only, type: :boolean, default: false, desc: 'Show learning status without optimizing'
              option :auto_accept, type: :boolean, default: false, desc: 'Auto-accept optimizations above min-confidence'
              option :min_confidence, type: :numeric, default: 0.90, desc: 'Minimum consistency for auto-accept (0.0-1.0)'
              option :tasks, type: :array, desc: 'Only optimize specific tasks'
              option :since, type: :string, desc: 'Only analyze traces since (e.g., "2h", "1d", "7d")'
              option :use_synthesis, type: :boolean, default: false, desc: 'Use LLM synthesis instead of pattern detection'
              option :synthesis_model, type: :string, desc: 'Model to use for synthesis (default: cluster default)'
              def optimize(name)
                handle_command_error('optimize agent') do
                  require_relative '../../../learning/trace_analyzer'
                  require_relative '../../../learning/pattern_detector'
                  require_relative '../../../learning/optimizer'
                  require_relative '../../../learning/task_synthesizer'
                  require_relative '../../../learning/semantic_validator'
                  require_relative '../../../agent/safety/ast_validator'
                  require_relative '../../formatters/optimization_formatter'

                  ctx = Helpers::ClusterContext.from_options(options)

                  # Get agent to verify it exists
                  get_resource_or_exit('LanguageAgent', name)

                  # Get agent code/definition
                  agent_definition = load_agent_definition(ctx, name)
                  unless agent_definition
                    Formatters::ProgressFormatter.error("Could not load agent definition for '#{name}'")
                    exit 1
                  end

                  # Check for OpenTelemetry configuration
                  unless ENV['OTEL_QUERY_ENDPOINT']
                    Formatters::ProgressFormatter.warn('OpenTelemetry endpoint not configured')
                    puts
                    puts 'Set OTEL_QUERY_ENDPOINT to enable learning:'
                    puts '  export OTEL_QUERY_ENDPOINT=https://your-signoz-instance.com'
                    puts '  export OTEL_QUERY_API_KEY=your-api-key          # For SigNoz authentication'
                    puts '  export OTEL_QUERY_BACKEND=signoz                # Optional: signoz, jaeger, or tempo'
                    puts
                    puts 'Auto-detection tries backends in order: SigNoz → Jaeger → Tempo'
                    puts 'Set OTEL_QUERY_BACKEND to skip auto-detection and use a specific backend.'
                    puts
                    exit 1
                  end

                  # Initialize learning components
                  trace_analyzer = Learning::TraceAnalyzer.new(
                    endpoint: ENV.fetch('OTEL_QUERY_ENDPOINT', nil),
                    api_key: ENV.fetch('OTEL_QUERY_API_KEY', nil),
                    backend: ENV.fetch('OTEL_QUERY_BACKEND', nil)
                  )

                  unless trace_analyzer.available?
                    Formatters::ProgressFormatter.error('OpenTelemetry backend not available')
                    puts
                    puts 'Check your OTEL_QUERY_ENDPOINT configuration and backend status.'
                    exit 1
                  end

                  validator = LanguageOperator::Agent::Safety::ASTValidator.new
                  pattern_detector = LanguageOperator::Learning::PatternDetector.new(
                    trace_analyzer: trace_analyzer,
                    validator: validator
                  )

                  # Create task synthesizer for fallback (or forced via --use-synthesis)
                  # Synthesis is used when pattern detection fails OR --use-synthesis is set
                  task_synthesizer = nil
                  llm_client = create_synthesis_llm_client(ctx, options[:synthesis_model])
                  if llm_client
                    task_synthesizer = LanguageOperator::Learning::TaskSynthesizer.new(
                      llm_client: llm_client,
                      validator: validator
                    )
                    Formatters::ProgressFormatter.info('LLM synthesis mode (forced)') if options[:use_synthesis]
                  elsif options[:use_synthesis]
                    Formatters::ProgressFormatter.warn('Could not create LLM client for synthesis')
                  end

                  # Create semantic validator
                  semantic_validator = LanguageOperator::Learning::SemanticValidator.new(
                    agent_definition: agent_definition
                  )

                  optimizer = LanguageOperator::Learning::Optimizer.new(
                    agent_name: name,
                    agent_definition: agent_definition,
                    trace_analyzer: trace_analyzer,
                    pattern_detector: pattern_detector,
                    task_synthesizer: task_synthesizer,
                    semantic_validator: semantic_validator
                  )

                  formatter = Formatters::OptimizationFormatter.new

                  # Parse --since option into time range
                  time_range = parse_since_option(options[:since])

                  # Analyze for opportunities
                  opportunities = optimizer.analyze(time_range: time_range)

                  # Display analysis only in status-only mode
                  if options[:status_only]
                    puts formatter.format_analysis(agent_name: name, opportunities: opportunities)
                    return
                  end

                  # Exit if no opportunities
                  if opportunities.empty?
                    puts "No optimization opportunities found for agent '#{name}'"
                    puts 'Tasks need at least 10 executions before optimization can begin.'
                    return
                  end

                  # Filter opportunities:
                  # - If synthesis available: try any task with enough executions
                  # - Otherwise: only tasks ready for pattern detection
                  candidates = if task_synthesizer
                                 # With synthesis, try any task that has min executions
                                 opportunities.select { |opp| opp[:execution_count] >= 10 }
                               else
                                 opportunities.select { |opp| opp[:ready_for_learning] }
                               end
                  return if candidates.empty?

                  # Process each opportunity
                  candidates.each do |opp|
                    task_name = opp[:task_name]

                    # Skip if not in requested tasks list
                    next if options[:tasks] && !options[:tasks].include?(task_name)

                    # Generate proposal
                    begin
                      proposal = optimizer.propose(task_name: task_name, use_synthesis: options[:use_synthesis])
                    rescue ArgumentError => e
                      Formatters::ProgressFormatter.warn("Cannot optimize '#{task_name}': #{e.message}")
                      next
                    end

                    # Display proposal
                    puts formatter.format_proposal(proposal: proposal)

                    # Get user confirmation or auto-accept
                    accepted = if options[:auto_accept] && proposal[:consistency_score] >= options[:min_confidence]
                                 consistency_pct = (proposal[:consistency_score] * 100).round(1)
                                 threshold_pct = (options[:min_confidence] * 100).round(1)
                                 puts pastel.green("✓ Auto-accepting (consistency: #{consistency_pct}% >= #{threshold_pct}%)")
                                 true
                               elsif options[:dry_run]
                                 puts pastel.yellow('[DRY RUN] Would prompt for acceptance')
                                 false
                               else
                                 prompt_for_optimization_acceptance(proposal)
                               end

                    # Apply if accepted
                    if accepted && !options[:dry_run]
                      result = apply_optimization(ctx, name, proposal)
                      puts formatter.format_success(result: result)
                    elsif accepted
                      puts pastel.yellow('[DRY RUN] Would apply optimization')
                    else
                      puts pastel.yellow("Skipped optimization for '#{task_name}'")
                    end

                    puts
                  end
                end
              end

              private

              # Parse --since option into seconds (time range)
              #
              # @param since [String, nil] Duration string (e.g., "2h", "1d", "7d")
              # @return [Integer, nil] Seconds or nil if not specified
              def parse_since_option(since)
                return nil unless since

                match = since.match(/^(\d+)([hHdDwW])$/)
                unless match
                  Formatters::ProgressFormatter.warn("Invalid --since format '#{since}', using default (24h)")
                  Formatters::ProgressFormatter.info('Valid formats: 2h (hours), 1d (days), 1w (weeks)')
                  return nil
                end

                value = match[1].to_i
                unit = match[2].downcase

                case unit
                when 'h' then value * 3600
                when 'd' then value * 86_400
                when 'w' then value * 604_800
                end
              end

              # Create LLM client for task synthesis using cluster model
              #
              # @param ctx [ClusterContext] Cluster context
              # @param model_name [String, nil] Specific model to use (defaults to first available)
              # @return [Object, nil] LLM client or nil if unavailable
              def create_synthesis_llm_client(ctx, model_name = nil)
                # Get model from cluster
                selected_model = model_name || select_synthesis_model(ctx)
                return nil unless selected_model

                # Get model resource to extract model ID
                # Always use port-forwarding to deployment (LiteLLM proxy for cost controls)
                begin
                  model = ctx.client.get_resource('LanguageModel', selected_model, ctx.namespace)
                  model_id = model.dig('spec', 'modelName')
                  return nil unless model_id

                  Helpers::ClusterLLMClient.new(
                    ctx: ctx,
                    model_name: selected_model,
                    model_id: model_id,
                    agent_command: self
                  )
                rescue StandardError => e
                  @logger&.warn("Failed to create cluster LLM client: #{e.message}")
                  nil
                end
              end

              # Select model for synthesis (first available if not specified)
              #
              # @param ctx [ClusterContext] Cluster context
              # @return [String, nil] Model name or nil
              def select_synthesis_model(ctx)
                models = ctx.client.list_resources('LanguageModel', namespace: ctx.namespace)
                return nil if models.empty?

                models.first.dig('metadata', 'name')
              rescue StandardError
                nil
              end

              # Prompt user for optimization acceptance
              #
              # @param proposal [Hash] Optimization proposal
              # @return [Boolean] User accepted or not
              def prompt_for_optimization_acceptance(proposal)
                choices = [
                  { name: 'Yes - apply this optimization', value: :yes },
                  { name: 'No - skip this task', value: :no },
                  { name: 'Cancel', value: :skip_all }
                ]

                choice = prompt.select(
                  "Accept optimization for '#{proposal[:task_name]}'?",
                  choices,
                  per_page: 10
                )

                case choice
                when :yes
                  true
                when :no
                  false
                when :skip_all
                  throw :skip_all
                end
              end
            end
          end
        end
      end
    end
  end
end
