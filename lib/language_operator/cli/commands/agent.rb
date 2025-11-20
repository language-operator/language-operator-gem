# frozen_string_literal: true

require 'thor'
require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../formatters/table_formatter'
require_relative '../formatters/value_formatter'
require_relative '../formatters/log_formatter'
require_relative '../formatters/status_formatter'
require_relative '../helpers/cluster_validator'
require_relative '../helpers/cluster_context'
require_relative '../helpers/user_prompts'
require_relative '../helpers/editor_helper'
require_relative '../helpers/pastel_helper'
require_relative '../errors/handler'
require_relative '../../config/cluster_config'
require_relative '../../kubernetes/client'
require_relative '../../kubernetes/resource_builder'
require_relative '../../ux/create_agent'

module LanguageOperator
  module CLI
    module Commands
      # Agent management commands
      class Agent < BaseCommand
        include Helpers::ClusterValidator
        include Helpers::PastelHelper

        desc 'create [DESCRIPTION]', 'Create a new agent with natural language description'
        long_desc <<-DESC
          Create a new autonomous agent by describing what you want it to do in natural language.

          The operator will synthesize the agent from your description and deploy it to your cluster.

          Examples:
            aictl agent create "review my spreadsheet at 4pm daily and email me any errors"
            aictl agent create "summarize Hacker News top stories every morning at 8am"
            aictl agent create "monitor my website uptime and alert me if it goes down"
            aictl agent create --wizard    # Interactive wizard mode
        DESC
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :create_cluster, type: :string, desc: 'Create cluster if it doesn\'t exist'
        option :name, type: :string, desc: 'Agent name (generated from description if not provided)'
        option :persona, type: :string, desc: 'Persona to use for the agent'
        option :tools, type: :array, desc: 'Tools to make available to the agent'
        option :models, type: :array, desc: 'Models to make available to the agent'
        option :workspace, type: :boolean, default: true, desc: 'Enable workspace for state persistence'
        option :dry_run, type: :boolean, default: false, desc: 'Preview what would be created without applying'
        option :wizard, type: :boolean, default: false, desc: 'Use interactive wizard mode'
        def create(description = nil)
          handle_command_error('create agent') do
            # Read from stdin if available and no description provided
            description = $stdin.read.strip if description.nil? && !$stdin.tty?

            # Activate wizard mode if --wizard flag or no description provided
            if options[:wizard] || description.nil? || description.empty?
              description = Ux::CreateAgent.execute(ctx)

              # User cancelled wizard
              unless description
                Formatters::ProgressFormatter.info('Agent creation cancelled')
                return
              end
            end

            # Handle --create-cluster flag
            if options[:create_cluster]
              cluster_name = options[:create_cluster]
              unless Config::ClusterConfig.cluster_exists?(cluster_name)
                Formatters::ProgressFormatter.info("Creating cluster '#{cluster_name}'...")
                # Delegate to cluster create command
                require_relative 'cluster'
                Cluster.new.invoke(:create, [cluster_name], switch: true)
              end
              cluster = cluster_name
            else
              # Validate cluster selection (this will exit if none selected)
              cluster = Helpers::ClusterValidator.get_cluster(options[:cluster])
            end

            ctx = Helpers::ClusterContext.from_options(options.merge(cluster: cluster))

            # Generate agent name from description if not provided
            agent_name = options[:name] || generate_agent_name(description)

            # Get models: use specified models, or default to all available models in cluster
            models = options[:models]
            if models.nil? || models.empty?
              available_models = ctx.client.list_resources('LanguageModel', namespace: ctx.namespace)
              models = available_models.map { |m| m.dig('metadata', 'name') }

              Errors::Handler.handle_no_models_available(cluster: ctx.name) if models.empty?
            end

            # Build LanguageAgent resource
            agent_resource = Kubernetes::ResourceBuilder.language_agent(
              agent_name,
              instructions: description,
              cluster: ctx.namespace,
              persona: options[:persona],
              tools: options[:tools] || [],
              models: models,
              workspace: options[:workspace]
            )

            # Dry-run mode: preview without applying
            if options[:dry_run]
              display_dry_run_preview(agent_resource, ctx.name, description)
              return
            end

            # Apply resource to cluster
            Formatters::ProgressFormatter.with_spinner("Creating agent '#{agent_name}'") do
              ctx.client.apply_resource(agent_resource)
            end

            # Watch synthesis status
            synthesis_result = watch_synthesis_status(ctx.client, agent_name, ctx.namespace)

            # Exit if synthesis failed
            exit 1 unless synthesis_result[:success]

            # Fetch the updated agent to get complete details
            agent = ctx.client.get_resource('LanguageAgent', agent_name, ctx.namespace)

            # Display enhanced success output
            display_agent_created(agent, ctx.name, description, synthesis_result)
          end
        end

        desc 'list', 'List all agents in current cluster'
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :all_clusters, type: :boolean, default: false, desc: 'Show agents across all clusters'
        def list
          handle_command_error('list agents') do
            if options[:all_clusters]
              list_all_clusters
            else
              ctx = Helpers::ClusterContext.from_options(options)
              list_cluster_agents(ctx.name)
            end
          end
        end

        desc 'inspect NAME', 'Show detailed agent information'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def inspect(name)
          handle_command_error('inspect agent') do
            ctx = Helpers::ClusterContext.from_options(options)

            begin
              agent = ctx.client.get_resource('LanguageAgent', name, ctx.namespace)
            rescue K8s::Error::NotFound
              handle_agent_not_found(name, ctx)
              return
            end

            puts "Agent: #{name}"
            puts "  Cluster:   #{ctx.name}"
            puts "  Namespace: #{ctx.namespace}"
            puts

            # Status
            status = agent.dig('status', 'phase') || 'Unknown'
            puts "Status: #{format_status(status)}"
            puts

            # Spec details
            puts 'Configuration:'
            puts "  Mode:         #{agent.dig('spec', 'mode') || 'autonomous'}"
            puts "  Schedule:     #{agent.dig('spec', 'schedule') || 'N/A'}" if agent.dig('spec', 'schedule')
            puts "  Persona:      #{agent.dig('spec', 'persona') || '(auto-selected)'}"
            puts

            # Instructions
            instructions = agent.dig('spec', 'instructions')
            if instructions
              puts 'Instructions:'
              puts "  #{instructions}"
              puts
            end

            # Tools
            tools = agent.dig('spec', 'tools') || []
            if tools.any?
              puts "Tools (#{tools.length}):"
              tools.each { |tool| puts "  - #{tool}" }
              puts
            end

            # Models
            model_refs = agent.dig('spec', 'modelRefs') || []
            if model_refs.any?
              puts "Models (#{model_refs.length}):"
              model_refs.each { |ref| puts "  - #{ref['name']}" }
              puts
            end

            # Synthesis info
            synthesis = agent.dig('status', 'synthesis')
            if synthesis
              puts 'Synthesis:'
              puts "  Status:       #{synthesis['status']}"
              puts "  Model:        #{synthesis['model']}" if synthesis['model']
              puts "  Completed:    #{synthesis['completedAt']}" if synthesis['completedAt']
              puts "  Duration:     #{synthesis['duration']}" if synthesis['duration']
              puts "  Token Count:  #{synthesis['tokenCount']}" if synthesis['tokenCount']
              puts
            end

            # Execution stats
            execution_count = agent.dig('status', 'executionCount') || 0
            last_execution = agent.dig('status', 'lastExecution')
            next_run = agent.dig('status', 'nextRun')

            puts 'Execution:'
            puts "  Total Runs:   #{execution_count}"
            puts "  Last Run:     #{last_execution || 'Never'}"
            puts "  Next Run:     #{next_run || 'N/A'}" if agent.dig('spec', 'schedule')
            puts

            # Conditions
            conditions = agent.dig('status', 'conditions') || []
            if conditions.any?
              puts "Conditions (#{conditions.length}):"
              conditions.each do |condition|
                status_icon = condition['status'] == 'True' ? '✓' : '✗'
                puts "  #{status_icon} #{condition['type']}: #{condition['message'] || condition['reason']}"
              end
              puts
            end

            # Recent events (if available)
            # This would require querying events, which we can add later
          end
        end

        desc 'delete NAME', 'Delete an agent'
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :force, type: :boolean, default: false, desc: 'Skip confirmation'
        def delete(name)
          handle_command_error('delete agent') do
            ctx = Helpers::ClusterContext.from_options(options)

            # Get agent to show details before deletion
            agent = get_resource_or_exit('LanguageAgent', name)

            # Confirm deletion
            details = {
              'Instructions' => agent.dig('spec', 'instructions'),
              'Mode' => agent.dig('spec', 'mode') || 'autonomous'
            }
            return unless confirm_deletion('agent', name, ctx.name, details: details, force: options[:force])

            # Delete the agent
            Formatters::ProgressFormatter.with_spinner("Deleting agent '#{name}'") do
              ctx.client.delete_resource('LanguageAgent', name, ctx.namespace)
            end

            Formatters::ProgressFormatter.success("Agent '#{name}' deleted successfully")
          end
        end

        desc 'logs NAME', 'Show agent execution logs'
        long_desc <<-DESC
          Stream agent execution logs in real-time.

          Use -f to follow logs continuously (like tail -f).

          Examples:
            aictl agent logs my-agent
            aictl agent logs my-agent -f
        DESC
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :follow, type: :boolean, aliases: '-f', default: false, desc: 'Follow logs'
        option :tail, type: :numeric, default: 100, desc: 'Number of lines to show from the end'
        def logs(name)
          handle_command_error('get logs') do
            ctx = Helpers::ClusterContext.from_options(options)

            # Get agent to determine the pod name
            agent = get_resource_or_exit('LanguageAgent', name)

            mode = agent.dig('spec', 'mode') || 'autonomous'

            # Build kubectl command for log streaming
            tail_arg = "--tail=#{options[:tail]}"
            follow_arg = options[:follow] ? '-f' : ''

            # For scheduled agents, logs come from CronJob pods
            # For autonomous agents, logs come from Deployment pods
            if mode == 'scheduled'
            # Get most recent job from cronjob
            else
              # Get pod from deployment
            end
            label_selector = "app.kubernetes.io/name=#{name}"

            # Use kubectl logs with label selector
            cmd = "#{ctx.kubectl_prefix} logs -l #{label_selector} #{tail_arg} #{follow_arg} --all-containers"

            Formatters::ProgressFormatter.info("Streaming logs for agent '#{name}'...")
            puts

            # Stream raw logs in real-time without formatting
            require 'open3'
            Open3.popen3(cmd) do |_stdin, stdout, stderr, wait_thr|
              # Handle stdout (logs)
              stdout_thread = Thread.new do
                stdout.each_line do |line|
                  puts line
                  $stdout.flush
                end
              end

              # Handle stderr (errors)
              stderr_thread = Thread.new do
                stderr.each_line do |line|
                  warn line
                end
              end

              # Wait for both streams to complete
              stdout_thread.join
              stderr_thread.join

              # Check exit status
              exit_status = wait_thr.value
              exit exit_status.exitstatus unless exit_status.success?
            end
          end
        end

        desc 'code NAME', 'Display synthesized agent code'
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :raw, type: :boolean, default: false, desc: 'Output raw code without formatting'
        def code(name)
          handle_command_error('get code') do
            require_relative '../formatters/code_formatter'

            ctx = Helpers::ClusterContext.from_options(options)

            # Get the code ConfigMap for this agent
            configmap_name = "#{name}-code"
            begin
              configmap = ctx.client.get_resource('ConfigMap', configmap_name, ctx.namespace)
            rescue K8s::Error::NotFound
              Formatters::ProgressFormatter.error("Synthesized code not found for agent '#{name}'")
              puts
              puts 'Possible reasons:'
              puts '  - Agent synthesis not yet complete'
              puts '  - Agent synthesis failed'
              puts
              puts 'Check synthesis status with:'
              puts "  aictl agent inspect #{name}"
              exit 1
            end

            # Get the agent.rb code from the ConfigMap
            code_content = configmap.dig('data', 'agent.rb')
            unless code_content
              Formatters::ProgressFormatter.error('Code content not found in ConfigMap')
              exit 1
            end

            # Raw output mode - just print the code
            if options[:raw]
              puts code_content
              return
            end

            # Display with syntax highlighting
            Formatters::CodeFormatter.display_ruby_code(
              code_content,
              title: "Synthesized Code for Agent: #{name}"
            )
          end
        end

        desc 'edit NAME', 'Edit agent instructions'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def edit(name)
          handle_command_error('edit agent') do
            ctx = Helpers::ClusterContext.from_options(options)

            # Get current agent
            agent = get_resource_or_exit('LanguageAgent', name)

            current_instructions = agent.dig('spec', 'instructions')

            # Edit instructions in user's editor
            new_instructions = Helpers::EditorHelper.edit_content(
              current_instructions,
              'agent-instructions-',
              '.txt'
            ).strip

            # Check if changed
            if new_instructions == current_instructions
              Formatters::ProgressFormatter.info('No changes made')
              return
            end

            # Update agent resource
            agent['spec']['instructions'] = new_instructions

            Formatters::ProgressFormatter.with_spinner('Updating agent instructions') do
              ctx.client.apply_resource(agent)
            end

            Formatters::ProgressFormatter.success('Agent instructions updated')
            puts
            puts 'The operator will automatically re-synthesize the agent code.'
            puts
            puts 'Watch synthesis progress with:'
            puts "  aictl agent inspect #{name}"
          end
        end

        desc 'pause NAME', 'Pause scheduled agent execution'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def pause(name)
          handle_command_error('pause agent') do
            ctx = Helpers::ClusterContext.from_options(options)

            # Get agent
            agent = get_resource_or_exit('LanguageAgent', name)

            mode = agent.dig('spec', 'mode') || 'autonomous'
            unless mode == 'scheduled'
              Formatters::ProgressFormatter.warn("Agent '#{name}' is not a scheduled agent (mode: #{mode})")
              puts
              puts 'Only scheduled agents can be paused.'
              puts 'Autonomous agents can be stopped by deleting them.'
              exit 1
            end

            # Suspend the CronJob by setting spec.suspend = true
            # This is done by patching the underlying CronJob resource
            cronjob_name = name
            ctx.namespace

            Formatters::ProgressFormatter.with_spinner("Pausing agent '#{name}'") do
              # Use kubectl to patch the cronjob
              cmd = "#{ctx.kubectl_prefix} patch cronjob #{cronjob_name} -p '{\"spec\":{\"suspend\":true}}'"
              system(cmd)
            end

            Formatters::ProgressFormatter.success("Agent '#{name}' paused")
            puts
            puts 'The agent will not execute on its schedule until resumed.'
            puts
            puts 'Resume with:'
            puts "  aictl agent resume #{name}"
          end
        end

        desc 'resume NAME', 'Resume paused agent'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def resume(name)
          handle_command_error('resume agent') do
            ctx = Helpers::ClusterContext.from_options(options)

            # Get agent
            agent = get_resource_or_exit('LanguageAgent', name)

            mode = agent.dig('spec', 'mode') || 'autonomous'
            unless mode == 'scheduled'
              Formatters::ProgressFormatter.warn("Agent '#{name}' is not a scheduled agent (mode: #{mode})")
              puts
              puts 'Only scheduled agents can be resumed.'
              exit 1
            end

            # Resume the CronJob by setting spec.suspend = false
            cronjob_name = name
            ctx.namespace

            Formatters::ProgressFormatter.with_spinner("Resuming agent '#{name}'") do
              # Use kubectl to patch the cronjob
              cmd = "#{ctx.kubectl_prefix} patch cronjob #{cronjob_name} -p '{\"spec\":{\"suspend\":false}}'"
              system(cmd)
            end

            Formatters::ProgressFormatter.success("Agent '#{name}' resumed")
            puts
            puts 'The agent will now execute according to its schedule.'
            puts
            puts 'View next execution time with:'
            puts "  aictl agent inspect #{name}"
          end
        end

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
        def optimize(name)
          handle_command_error('optimize agent') do
            require_relative '../../learning/trace_analyzer'
            require_relative '../../learning/pattern_detector'
            require_relative '../../learning/optimizer'
            require_relative '../../agent/safety/ast_validator'
            require_relative '../formatters/optimization_formatter'

            ctx = Helpers::ClusterContext.from_options(options)

            # Get agent to verify it exists
            agent = get_resource_or_exit('LanguageAgent', name)

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
              endpoint: ENV['OTEL_QUERY_ENDPOINT'],
              api_key: ENV['OTEL_QUERY_API_KEY']
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

            optimizer = LanguageOperator::Learning::Optimizer.new(
              agent_name: name,
              agent_definition: agent_definition,
              trace_analyzer: trace_analyzer,
              pattern_detector: pattern_detector
            )

            formatter = Formatters::OptimizationFormatter.new

            # Analyze for opportunities
            opportunities = optimizer.analyze

            # Display analysis
            puts formatter.format_analysis(agent_name: name, opportunities: opportunities)

            # Exit if status-only mode
            return if options[:status_only]

            # Exit if no opportunities
            return if opportunities.empty?

            # Filter to ready opportunities
            ready = opportunities.select { |opp| opp[:ready_for_learning] }
            return if ready.empty?

            # Process each opportunity
            ready.each do |opp|
              task_name = opp[:task_name]

              # Skip if not in requested tasks list
              next if options[:tasks] && !options[:tasks].include?(task_name)

              # Generate proposal
              begin
                proposal = optimizer.propose(task_name: task_name)
              rescue ArgumentError => e
                Formatters::ProgressFormatter.warn("Cannot optimize '#{task_name}': #{e.message}")
                next
              end

              # Display proposal
              puts formatter.format_proposal(proposal: proposal)

              # Get user confirmation or auto-accept
              accepted = if options[:auto_accept] && proposal[:consistency_score] >= options[:min_confidence]
                           puts pastel.green("✓ Auto-accepting (consistency: #{(proposal[:consistency_score] * 100).round(1)}% >= #{(options[:min_confidence] * 100).round(1)}%)")
                           true
                         elsif options[:dry_run]
                           puts pastel.yellow('[DRY RUN] Would prompt for acceptance')
                           false
                         else
                           prompt_for_optimization_acceptance(proposal)
                         end

              # Apply if accepted
              if accepted && !options[:dry_run]
                result = optimizer.apply(proposal: proposal)
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

        desc 'workspace NAME', 'Browse agent workspace files'
        long_desc <<-DESC
          Browse and manage the workspace files for an agent.

          Workspaces provide persistent storage for agents to maintain state,
          cache data, and remember information across executions.

          Examples:
            aictl agent workspace my-agent                           # List all files
            aictl agent workspace my-agent --path /workspace/state.json  # View specific file
            aictl agent workspace my-agent --clean                   # Clear workspace
        DESC
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :path, type: :string, desc: 'View specific file contents'
        option :clean, type: :boolean, desc: 'Clear workspace (with confirmation)'
        def workspace(name)
          handle_command_error('access workspace') do
            ctx = Helpers::ClusterContext.from_options(options)

            # Get agent to verify it exists
            agent = get_resource_or_exit('LanguageAgent', name)

            # Check if workspace is enabled
            workspace_enabled = agent.dig('spec', 'workspace', 'enabled')
            unless workspace_enabled
              Formatters::ProgressFormatter.warn("Workspace is not enabled for agent '#{name}'")
              puts
              puts 'Enable workspace in agent configuration:'
              puts '  spec:'
              puts '    workspace:'
              puts '      enabled: true'
              puts '      size: 10Gi'
              exit 1
            end

            if options[:path]
              view_workspace_file(ctx, name, options[:path])
            elsif options[:clean]
              clean_workspace(ctx, name)
            else
              list_workspace_files(ctx, name)
            end
          end
        end

        private

        def handle_agent_not_found(name, ctx)
          # Get available agents for fuzzy matching
          agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)
          available_names = agents.map { |a| a.dig('metadata', 'name') }

          error = K8s::Error::NotFound.new(404, 'Not Found', 'LanguageAgent')
          Errors::Handler.handle_not_found(error,
                                           resource_type: 'LanguageAgent',
                                           resource_name: name,
                                           cluster: ctx.name,
                                           available_resources: available_names)
        end

        def display_agent_created(agent, cluster, _description, synthesis_result)
          require_relative '../formatters/code_formatter'
          agent_name = agent.dig('metadata', 'name')

          puts
          Formatters::ProgressFormatter.success("Agent '#{agent_name}' created and deployed!")
          puts

          # Get synthesized code if available
          begin
            ctx = Helpers::ClusterContext.from_options(cluster: cluster)
            configmap_name = "#{agent_name}-code"
            configmap = ctx.client.get_resource('ConfigMap', configmap_name, ctx.namespace)
            code_content = configmap.dig('data', 'agent.rb')

            if code_content
              # Display code preview (first 20 lines)
              Formatters::CodeFormatter.display_ruby_code(
                code_content,
                title: 'Synthesized Code Preview:',
                max_lines: 20
              )
              puts
            end
          rescue StandardError
            # Code not available yet, skip preview
          end

          # Display agent configuration
          puts pastel.cyan('Agent Configuration:')
          puts "  Name:         #{agent_name}"
          puts "  Cluster:      #{cluster}"

          # Schedule information
          schedule = agent.dig('spec', 'schedule')
          mode = agent.dig('spec', 'mode') || 'autonomous'
          if schedule
            human_schedule = parse_schedule(schedule)
            puts "  Schedule:     #{human_schedule} (#{schedule})"

            # Calculate next run
            next_run = agent.dig('status', 'nextRun')
            if next_run
              begin
                next_run_time = Time.parse(next_run)
                time_until = format_time_until(next_run_time)
                puts "  Next run:     #{next_run} (#{time_until})"
              rescue StandardError
                puts "  Next run:     #{next_run}"
              end
            end
          else
            puts "  Mode:         #{mode}"
          end

          # Persona
          persona = agent.dig('spec', 'persona')
          puts "  Persona:      #{persona || '(auto-selected)'}"

          # Tools
          tools = agent.dig('spec', 'tools') || []
          puts "  Tools:        #{tools.join(', ')}" if tools.any?

          # Models
          model_refs = agent.dig('spec', 'modelRefs') || []
          if model_refs.any?
            model_names = model_refs.map { |ref| ref['name'] }
            puts "  Models:       #{model_names.join(', ')}"
          end

          puts

          # Synthesis stats
          if synthesis_result[:duration]
            puts pastel.dim("Synthesis completed in #{format_duration(synthesis_result[:duration])}")
            puts pastel.dim("Model: #{synthesis_result[:model]}") if synthesis_result[:model]
            puts
          end

          # Next steps
          puts pastel.cyan('Next Steps:')
          puts "  aictl agent logs #{agent_name} -f     # Follow agent execution logs"
          puts "  aictl agent code #{agent_name}        # View full synthesized code"
          puts "  aictl agent inspect #{agent_name}     # View detailed agent status"
          puts
        end

        def parse_schedule(cron_expr)
          # Simple cron to human-readable conversion
          # Format: minute hour day month weekday
          parts = cron_expr.split

          return cron_expr if parts.length != 5

          minute, hour, day, month, weekday = parts

          # Common patterns
          if minute == '0' && hour != '*' && day == '*' && month == '*' && weekday == '*'
            # Daily at specific hour
            hour12 = hour.to_i % 12
            hour12 = 12 if hour12.zero?
            period = hour.to_i < 12 ? 'AM' : 'PM'
            return "Daily at #{hour12}:00 #{period}"
          elsif minute != '*' && hour != '*' && day == '*' && month == '*' && weekday == '*'
            # Daily at specific time
            hour12 = hour.to_i % 12
            hour12 = 12 if hour12.zero?
            period = hour.to_i < 12 ? 'AM' : 'PM'
            return "Daily at #{hour12}:#{minute.rjust(2, '0')} #{period}"
          elsif minute.start_with?('*/') && hour == '*'
            # Every N minutes
            interval = minute[2..].to_i
            return "Every #{interval} minutes"
          elsif minute == '*' && hour.start_with?('*/')
            # Every N hours
            interval = hour[2..].to_i
            return "Every #{interval} hours"
          end

          # Fallback to cron expression
          cron_expr
        end

        def format_time_until(future_time)
          Formatters::ValueFormatter.time_until(future_time)
        end

        def display_dry_run_preview(agent_resource, cluster, description)
          require 'yaml'

          puts
          puts '=' * 80
          puts '  DRY RUN: Agent Creation Preview'
          puts '=' * 80
          puts

          # Extract key information
          name = agent_resource.dig('metadata', 'name')
          namespace = agent_resource.dig('metadata', 'namespace')
          persona = agent_resource.dig('spec', 'persona')
          tools = agent_resource.dig('spec', 'tools') || []
          model_refs = agent_resource.dig('spec', 'modelRefs') || []
          models = model_refs.map { |ref| ref['name'] }
          mode = agent_resource.dig('spec', 'mode') || 'autonomous'
          schedule = agent_resource.dig('spec', 'schedule')

          # Display summary
          puts 'Agent Summary:'
          puts "  Name:         #{name}"
          puts "  Cluster:      #{cluster}"
          puts "  Namespace:    #{namespace}"
          puts "  Mode:         #{mode}"
          puts "  Schedule:     #{schedule || 'N/A'}" if schedule
          puts "  Instructions: #{description}"
          puts

          # Show detected configuration
          if persona
            puts 'Detected Configuration:'
            puts "  Persona:      #{persona}"
          end

          puts "  Tools:        #{tools.join(', ')}" if tools.any?

          puts "  Models:       #{models.join(', ')}" if models.any?

          puts if persona || tools.any? || models.any?

          # Show full YAML
          puts 'Generated YAML:'
          puts '─' * 80
          puts YAML.dump(agent_resource)
          puts '─' * 80
          puts

          # Show what would happen
          puts 'What would happen:'
          puts '  1. Agent resource would be created in the cluster'
          puts '  2. Operator would synthesize Ruby code from instructions'
          puts '  3. Agent would be deployed and start running'
          puts

          # Show how to actually create
          Formatters::ProgressFormatter.info('No changes made (dry-run mode)')
          puts
          puts 'To create this agent for real, run:'
          cmd_parts = ["aictl agent create \"#{description}\""]
          cmd_parts << "--name #{name}" if options[:name]
          cmd_parts << "--persona #{persona}" if persona
          cmd_parts << "--tools #{tools.join(' ')}" if tools.any?
          cmd_parts << "--models #{models.join(' ')}" if models.any?
          cmd_parts << "--cluster #{cluster}" if options[:cluster]
          puts "  #{cmd_parts.join(' ')}"
        end

        def format_status(status)
          Formatters::StatusFormatter.format(status)
        end

        def generate_agent_name(description)
          # Simple name generation from description
          # Take first few words, lowercase, hyphenate
          words = description.downcase.gsub(/[^a-z0-9\s]/, '').split[0..2]
          name = words.join('-')
          # Add random suffix to avoid collisions
          "#{name}-#{Time.now.to_i.to_s[-4..]}"
        end

        def watch_synthesis_status(k8s, agent_name, namespace)
          max_wait = 600 # Wait up to 10 minutes (local models can be slow)
          interval = 2   # Check every 2 seconds
          elapsed = 0
          start_time = Time.now
          synthesis_data = {}

          result = Formatters::ProgressFormatter.with_spinner('Synthesizing code from instructions') do
            loop do
              status = check_synthesis_status(k8s, agent_name, namespace, synthesis_data, start_time)
              return status if status

              # Timeout check
              if elapsed >= max_wait
                Formatters::ProgressFormatter.warn('Synthesis taking longer than expected, continuing in background...')
                puts
                puts 'Check synthesis status with:'
                puts "  aictl agent inspect #{agent_name}"
                return { success: true, timeout: true }
              end

              sleep interval
              elapsed += interval
            end
          rescue K8s::Error::NotFound
            # Agent not found yet, keep waiting
            sleep interval
            elapsed += interval
            retry if elapsed < max_wait

            Formatters::ProgressFormatter.error('Agent resource not found')
            return { success: false }
          rescue StandardError => e
            Formatters::ProgressFormatter.warn("Could not watch synthesis: #{e.message}")
            return { success: true } # Continue anyway
          end

          # Show synthesis details after spinner completes
          if result[:success] && !result[:timeout]
            duration = result[:duration]
            Formatters::ProgressFormatter.success("Code synthesis completed in #{format_duration(duration)}")
            puts "  Model: #{synthesis_data[:model]}" if synthesis_data[:model]
            puts "  Tokens: #{synthesis_data[:token_count]}" if synthesis_data[:token_count]
          end

          result
        end

        def check_synthesis_status(k8s, agent_name, namespace, synthesis_data, start_time)
          agent = k8s.get_resource('LanguageAgent', agent_name, namespace)
          conditions = agent.dig('status', 'conditions') || []
          synthesis_status = agent.dig('status', 'synthesis')

          # Capture synthesis metadata
          if synthesis_status
            synthesis_data[:model] = synthesis_status['model']
            synthesis_data[:token_count] = synthesis_status['tokenCount']
          end

          # Check for synthesis completion
          synthesized = conditions.find { |c| c['type'] == 'Synthesized' }
          return nil unless synthesized

          if synthesized['status'] == 'True'
            duration = Time.now - start_time
            { success: true, duration: duration, **synthesis_data }
          elsif synthesized['status'] == 'False'
            Formatters::ProgressFormatter.error("Synthesis failed: #{synthesized['message']}")
            { success: false }
          end
        end

        def format_duration(seconds)
          Formatters::ValueFormatter.duration(seconds)
        end

        def list_cluster_agents(cluster)
          ctx = Helpers::ClusterContext.from_options(cluster: cluster)

          Formatters::ProgressFormatter.info("Agents in cluster '#{cluster}'")

          agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)

          table_data = agents.map do |agent|
            {
              name: agent.dig('metadata', 'name'),
              mode: agent.dig('spec', 'mode') || 'autonomous',
              status: agent.dig('status', 'phase') || 'Unknown',
              next_run: agent.dig('status', 'nextRun') || 'N/A',
              executions: agent.dig('status', 'executionCount') || 0
            }
          end

          Formatters::TableFormatter.agents(table_data)

          return unless agents.empty?

          puts
          puts 'Create an agent with:'
          puts '  aictl agent create "<description>"'
        end

        def list_all_clusters
          clusters = Config::ClusterConfig.list_clusters

          if clusters.empty?
            Formatters::ProgressFormatter.info('No clusters found')
            puts
            puts 'Create a cluster first:'
            puts '  aictl cluster create <name>'
            return
          end

          all_agents = []

          clusters.each do |cluster|
            ctx = Helpers::ClusterContext.from_options(cluster: cluster[:name])

            agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)

            agents.each do |agent|
              all_agents << {
                cluster: cluster[:name],
                name: agent.dig('metadata', 'name'),
                mode: agent.dig('spec', 'mode') || 'autonomous',
                status: agent.dig('status', 'phase') || 'Unknown',
                next_run: agent.dig('status', 'nextRun') || 'N/A',
                executions: agent.dig('status', 'executionCount') || 0
              }
            end
          rescue StandardError => e
            Formatters::ProgressFormatter.warn("Failed to get agents from cluster '#{cluster[:name]}': #{e.message}")
          end

          # Group agents by cluster for formatted display
          agents_by_cluster = all_agents.group_by { |agent| agent[:cluster] }
                                        .transform_values { |agents| agents.map { |a| a.except(:cluster) } }

          Formatters::TableFormatter.all_agents(agents_by_cluster)
        end

        # Workspace-related helper methods

        def get_agent_pod(ctx, agent_name)
          # Find pod for this agent using label selector
          label_selector = "app.kubernetes.io/name=#{agent_name}"
          pods = ctx.client.list_resources('Pod', namespace: ctx.namespace, label_selector: label_selector)

          if pods.empty?
            Formatters::ProgressFormatter.error("No running pods found for agent '#{agent_name}'")
            puts
            puts 'Possible reasons:'
            puts '  - Agent pod has not started yet'
            puts '  - Agent is paused or stopped'
            puts '  - Agent failed to deploy'
            puts
            puts 'Check agent status with:'
            puts "  aictl agent inspect #{agent_name}"
            exit 1
          end

          # Find a running pod
          running_pod = pods.find do |pod|
            pod.dig('status', 'phase') == 'Running'
          end

          unless running_pod
            Formatters::ProgressFormatter.error('Agent pod exists but is not running')
            puts
            puts "Current pod status: #{pods.first.dig('status', 'phase')}"
            puts
            puts 'Check pod logs with:'
            puts "  aictl agent logs #{agent_name}"
            exit 1
          end

          running_pod.dig('metadata', 'name')
        end

        def exec_in_pod(ctx, pod_name, command)
          # Properly escape command for shell
          cmd_str = command.is_a?(Array) ? command.join(' ') : command
          kubectl_cmd = "#{ctx.kubectl_prefix} exec #{pod_name} -- #{cmd_str}"

          # Execute and capture output
          require 'open3'
          stdout, stderr, status = Open3.capture3(kubectl_cmd)

          raise "Command failed: #{stderr}" unless status.success?

          stdout
        end

        def list_workspace_files(ctx, agent_name)
          pod_name = get_agent_pod(ctx, agent_name)

          # Check if workspace directory exists
          begin
            exec_in_pod(ctx, pod_name, 'test -d /workspace')
          rescue StandardError
            Formatters::ProgressFormatter.error('Workspace directory not found in agent pod')
            puts
            puts 'The /workspace directory does not exist in the agent pod.'
            puts 'This agent may not have workspace support enabled.'
            exit 1
          end

          # Get workspace usage
          usage_output = exec_in_pod(
            ctx,
            pod_name,
            'du -sh /workspace 2>/dev/null || echo "0\t/workspace"'
          )
          workspace_size = usage_output.split("\t").first.strip

          # List files with details
          file_list = exec_in_pod(
            ctx,
            pod_name,
            'find /workspace -ls 2>/dev/null | tail -n +2'
          )

          puts
          puts pastel.cyan("Workspace for agent '#{agent_name}' (#{workspace_size})")
          puts '=' * 60
          puts

          if file_list.strip.empty?
            puts pastel.dim('Workspace is empty')
            puts
            puts 'The agent will create files here as it runs.'
            puts
            return
          end

          # Parse and display file list
          file_list.each_line do |line|
            parts = line.strip.split(/\s+/, 11)
            next if parts.length < 11

            # Extract relevant parts
            # Format: inode blocks perms links user group size month day time path
            perms = parts[2]
            size = parts[6]
            month = parts[7]
            day = parts[8]
            time_or_year = parts[9]
            path = parts[10]

            # Skip the /workspace directory itself
            next if path == '/workspace'

            # Determine file type and icon
            icon = if perms.start_with?('d')
                     pastel.blue('📁')
                   else
                     pastel.white('📄')
                   end

            # Format path relative to workspace
            relative_path = path.sub('/workspace/', '')
            indent = '  ' * relative_path.count('/')

            # Format size
            formatted_size = format_file_size(size.to_i).rjust(8)

            # Format time
            formatted_time = "#{month} #{day.rjust(2)} #{time_or_year}"

            puts "#{indent}#{icon} #{File.basename(relative_path).ljust(30)} #{pastel.dim(formatted_size)}  #{pastel.dim(formatted_time)}"
          end

          puts
          puts pastel.dim('Commands:')
          puts pastel.dim("  aictl agent workspace #{agent_name} --path /workspace/<file>  # View file")
          puts pastel.dim("  aictl agent workspace #{agent_name} --clean                   # Clear workspace")
          puts
        end

        def view_workspace_file(ctx, agent_name, file_path)
          pod_name = get_agent_pod(ctx, agent_name)

          # Check if file exists
          begin
            exec_in_pod(ctx, pod_name, "test -f #{file_path}")
          rescue StandardError
            Formatters::ProgressFormatter.error("File not found: #{file_path}")
            puts
            puts 'List available files with:'
            puts "  aictl agent workspace #{agent_name}"
            exit 1
          end

          # Get file metadata
          stat_output = exec_in_pod(
            ctx,
            pod_name,
            "stat -c '%s %Y' #{file_path}"
          )
          size, mtime = stat_output.strip.split

          # Get file contents
          contents = exec_in_pod(
            ctx,
            pod_name,
            "cat #{file_path}"
          )

          # Display file
          puts
          puts pastel.cyan("File: #{file_path}")
          puts "Size: #{format_file_size(size.to_i)}"
          puts "Modified: #{format_timestamp(Time.at(mtime.to_i))}"
          puts '=' * 60
          puts
          puts contents
          puts
        end

        def clean_workspace(ctx, agent_name)
          pod_name = get_agent_pod(ctx, agent_name)

          # Get current workspace usage
          usage_output = exec_in_pod(
            ctx,
            pod_name,
            'du -sh /workspace 2>/dev/null || echo "0\t/workspace"'
          )
          workspace_size = usage_output.split("\t").first.strip

          # Count files
          file_count = exec_in_pod(
            ctx,
            pod_name,
            'find /workspace -type f | wc -l'
          ).strip.to_i

          puts
          puts pastel.yellow("This will delete ALL files in the workspace for '#{agent_name}'")
          puts
          puts 'The agent will lose:'
          puts '  • Execution history'
          puts '  • Cached data'
          puts '  • State information'
          puts
          puts "Current workspace: #{file_count} files, #{workspace_size}"
          puts

          # Use UserPrompts helper
          return unless Helpers::UserPrompts.confirm('Are you sure?')

          # Delete all files in workspace
          Formatters::ProgressFormatter.with_spinner('Cleaning workspace') do
            exec_in_pod(
              ctx,
              pod_name,
              'find /workspace -mindepth 1 -delete'
            )
          end

          Formatters::ProgressFormatter.success("Workspace cleared (freed #{workspace_size})")
          puts
          puts 'The agent will start fresh on its next execution.'
        end

        def format_file_size(bytes)
          Formatters::ValueFormatter.file_size(bytes)
        end

        def format_timestamp(time)
          Formatters::ValueFormatter.timestamp(time)
        end

        # Load agent definition from ConfigMap
        def load_agent_definition(ctx, agent_name)
          # Try to get the agent code ConfigMap
          configmap_name = "#{agent_name}-code"
          begin
            configmap = ctx.client.get_resource('ConfigMap', configmap_name, ctx.namespace)
            code_content = configmap.dig('data', 'agent.rb')

            return nil unless code_content

            # Parse the code to extract agent definition
            # For now, we'll create a mock definition with the task structure
            # In a full implementation, this would eval the code safely
            parse_agent_code(code_content)
          rescue K8s::Error::NotFound
            nil
          rescue StandardError => e
            @logger&.error("Failed to load agent definition: #{e.message}")
            nil
          end
        end

        # Parse agent code to extract definition
        def parse_agent_code(code)
          # This is a simplified parser that creates a mock agent definition
          # In production, this would use the actual DSL parser
          require_relative '../../dsl/agent_definition'

          # Create a minimal agent definition structure
          # that supports the optimizer's needs
          agent_def = Struct.new(:tasks, :name) do
            def initialize
              super({}, 'agent')
            end
          end

          agent = agent_def.new

          # Parse tasks from code (simplified)
          # Look for task definitions
          code.scan(/task\s+:(\w+),?\s*(.*?)(?=\n\s*(?:task|main|end))/m) do |match|
            task_name = match[0].to_sym
            task_block = match[1]

            # Check if neural (has instructions) or symbolic (has do block)
            is_neural = task_block.include?('instructions:')

            task = Struct.new(:name, :neural?, :instructions, :inputs, :outputs) do
              def initialize(name, neural)
                super(name, neural, '', {}, {})
              end
            end

            agent.tasks[task_name] = task.new(task_name, is_neural)
          end

          agent
        end

        # Prompt user for optimization acceptance
        def prompt_for_optimization_acceptance(proposal)
          require 'tty-prompt'
          prompt = TTY::Prompt.new

          choices = [
            { name: 'Yes - apply this optimization', value: :yes },
            { name: 'No - skip this task', value: :no },
            { name: 'View full code diff', value: :diff },
            { name: 'Skip all remaining', value: :skip_all }
          ]

          loop do
            choice = prompt.select(
              "Accept optimization for '#{proposal[:task_name]}'?",
              choices,
              per_page: 10
            )

            case choice
            when :yes
              return true
            when :no
              return false
            when :diff
              show_code_diff(proposal)
              # Loop to ask again
            when :skip_all
              throw :skip_all
            end
          end
        end

        # Show full code diff
        def show_code_diff(proposal)
          puts
          puts pastel.bold('Full Generated Code:')
          puts pastel.dim('=' * 70)
          puts proposal[:full_generated_code]
          puts pastel.dim('=' * 70)
          puts
        end
      end
    end
  end
end
