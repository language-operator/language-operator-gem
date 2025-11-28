# frozen_string_literal: true

require 'thor'
require_relative '../../command_loader'
require_relative '../../wizards/agent_wizard'

# Include all agent subcommand modules
require_relative 'workspace'
require_relative 'code_operations'
require_relative 'logs'
require_relative 'lifecycle'
require_relative 'learning'

# Include helper modules
require_relative 'helpers/cluster_llm_client'
require_relative 'helpers/code_parser'
require_relative 'helpers/synthesis_watcher'
require_relative '../../helpers/cluster_context'
require_relative '../../../kubernetes/resource_builder'

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Base agent command class
        class Base < BaseCommand
          include Constants
          include ::LanguageOperator::CLI::Helpers::ClusterValidator
          include CLI::Helpers::UxHelper
          include Agent::Helpers::CodeParser
          include Agent::Helpers::SynthesisWatcher

          # Include all subcommand modules
          include Workspace
          include CodeOperations
          include Logs
          include Lifecycle
          include Learning

          # NOTE: Core commands (create, list, inspect, delete) will be added below
          # This file is a placeholder for the refactoring process
          # The full implementation needs to be extracted from the original agent.rb

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
                wizard = Wizards::AgentWizard.new
                description = wizard.run

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
                  require_relative '../cluster'
                  Cluster.new.invoke(:create, [cluster_name], switch: true)
                end
                cluster = cluster_name
              else
                # Validate cluster selection (this will exit if none selected)
                cluster = CLI::Helpers::ClusterValidator.get_cluster(options[:cluster])
              end

              ctx = CLI::Helpers::ClusterContext.from_options(options.merge(cluster: cluster))

              # Generate agent name from description if not provided
              agent_name = options[:name] || generate_agent_name(description)

              # Get models: use specified models, or default to all available models in cluster
              models = options[:models]
              if models.nil? || models.empty?
                available_models = ctx.client.list_resources(RESOURCE_MODEL, namespace: ctx.namespace)
                models = available_models.map { |m| m.dig('metadata', 'name') }

                Errors::Handler.handle_no_models_available(cluster: ctx.name) if models.empty?
              end

              # Build LanguageAgent resource
              agent_resource = Kubernetes::ResourceBuilder.language_agent(
                agent_name,
                instructions: description,
                cluster: ctx.namespace,
                cluster_ref: ctx.name,
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
              agent = ctx.client.get_resource(RESOURCE_AGENT, agent_name, ctx.namespace)

              # Display enhanced success output
              display_agent_created(agent, ctx, description, synthesis_result)
            end
          end

          desc 'list', 'List all agents in current cluster'
          option :cluster, type: :string, desc: 'Override current cluster context'
          option :all_clusters, type: :boolean, default: false, desc: 'Show agents across all clusters'
          def list
            if options[:all_clusters]
              list_all_clusters
            else
              cluster = options[:cluster]
              list_cluster_agents(cluster)
            end
          end

          desc 'inspect NAME', 'Show detailed agent information'
          option :cluster, type: :string, desc: 'Override current cluster context'
          def inspect(name)
            handle_command_error('inspect agent') do
              ctx = CLI::Helpers::ClusterContext.from_options(options)

              begin
                agent = ctx.client.get_resource(RESOURCE_AGENT, name, ctx.namespace)
              rescue K8s::Error::NotFound
                handle_agent_not_found(name, ctx)
                return
              end

              # Main agent information
              puts
              status = agent.dig('status', 'phase') || 'Unknown'
              format_agent_details(
                name: name,
                namespace: ctx.namespace,
                cluster: ctx.name,
                status: format_status(status),
                mode: agent.dig('spec', 'executionMode') || 'autonomous',
                schedule: agent.dig('spec', 'schedule'),
                persona: agent.dig('spec', 'persona'),
                created: agent.dig('metadata', 'creationTimestamp')
              )
              puts

              # Execution stats (only for scheduled agents)
              mode = agent.dig('spec', 'executionMode') || 'autonomous'
              if mode == 'scheduled'
                exec_data = get_execution_data(name, ctx)

                exec_rows = {
                  'Total Runs' => exec_data[:total_runs],
                  'Last Run' => exec_data[:last_run] || 'Never'
                }
                exec_rows['Next Run'] = exec_data[:next_run] || 'N/A' if agent.dig('spec', 'schedule')

                highlighted_box(title: 'Executions', rows: exec_rows, color: :blue)
                puts
              end

              # Resources
              resources = agent.dig('spec', 'resources')
              if resources
                resource_rows = {}
                requests = resources['requests'] || {}
                limits = resources['limits'] || {}

                # CPU
                cpu_request = requests['cpu']
                cpu_limit = limits['cpu']
                resource_rows['CPU'] = [cpu_request, cpu_limit].compact.join(' / ') if cpu_request || cpu_limit

                # Memory
                memory_request = requests['memory']
                memory_limit = limits['memory']
                resource_rows['Memory'] = [memory_request, memory_limit].compact.join(' / ') if memory_request || memory_limit

                highlighted_box(title: 'Resources (Request/Limit)', rows: resource_rows, color: :cyan) unless resource_rows.empty?
                puts
              end

              # Instructions
              instructions = agent.dig('spec', 'instructions')
              if instructions
                puts pastel.white.bold('Instructions')
                puts instructions
                puts
              end

              # Tools
              tools = agent.dig('spec', 'tools') || []
              unless tools.empty?
                list_box(title: 'Tools', items: tools)
                puts
              end

              # Models
              model_refs = agent.dig('spec', 'modelRefs') || []
              unless model_refs.empty?
                model_names = model_refs.map { |ref| ref['name'] }
                list_box(title: 'Models', items: model_names, bullet: '⛁')
                puts
              end

              # Synthesis info
              synthesis = agent.dig('status', 'synthesis')
              if synthesis
                highlighted_box(
                  title: 'Synthesis',
                  rows: {
                    'Status' => synthesis['status'],
                    'Model' => synthesis['model'],
                    'Completed' => synthesis['completedAt'],
                    'Duration' => synthesis['duration'],
                    'Token Count' => synthesis['tokenCount']
                  }
                )
                puts
              end

              # Conditions
              conditions = agent.dig('status', 'conditions') || []
              unless conditions.empty?
                list_box(
                  title: 'Conditions',
                  items: conditions,
                  style: :conditions
                )
                puts
              end

              # Labels
              labels = agent.dig('metadata', 'labels') || {}
              list_box(
                title: 'Labels',
                items: labels,
                style: :key_value
              )

              # Recent events (if available)
              # This would require querying events, which we can add later
            end
          end

          desc 'delete NAME', 'Delete an agent'
          option :cluster, type: :string, desc: 'Override current cluster context'
          option :force, type: :boolean, default: false, desc: 'Skip confirmation'
          def delete(name)
            handle_command_error('delete agent') do
              ctx = CLI::Helpers::ClusterContext.from_options(options)

              # Get agent to verify it exists
              get_resource_or_exit(RESOURCE_AGENT, name)

              # Confirm deletion
              return unless confirm_deletion_with_force('agent', name, ctx.name, force: options[:force])

              # Delete the agent
              puts
              Formatters::ProgressFormatter.with_spinner("Deleting agent '#{name}'") do
                ctx.client.delete_resource(RESOURCE_AGENT, name, ctx.namespace)
              end
            end
          end

          desc 'versions NAME', 'Show ConfigMap versions managed by operator'
          long_desc <<-DESC
            List the versioned ConfigMaps created by the operator for an agent.

            Shows the automatic optimization history and available versions for rollback.

            Examples:
              aictl agent versions my-agent
              aictl agent versions my-agent --cluster production
          DESC
          option :cluster, type: :string, desc: 'Override current cluster context'
          def versions(name)
            handle_command_error('list agent versions') do
              ctx = CLI::Helpers::ClusterContext.from_options(options)

              # Get agent to verify it exists
              get_resource_or_exit(RESOURCE_AGENT, name)

              # List all ConfigMaps with the agent label
              config_maps = ctx.client.list_resources('ConfigMap', namespace: ctx.namespace)

              # Filter for versioned ConfigMaps for this agent
              agent_configs = config_maps.select do |cm|
                labels = cm.dig('metadata', 'labels') || {}
                labels['agent'] == name && labels['version']
              end

              # Sort by version (assuming numeric versions)
              agent_configs.sort! do |a, b|
                version_a = a.dig('metadata', 'labels', 'version').to_i
                version_b = b.dig('metadata', 'labels', 'version').to_i
                version_b <=> version_a # Reverse order (newest first)
              end

              display_agent_versions(agent_configs, name, ctx.name)
            end
          end

          private

          # Shared helper methods that are used across multiple commands
          # These will be extracted from the original agent.rb

          def handle_agent_not_found(name, ctx, error)
            # Get available agents for fuzzy matching
            agents = ctx.client.list_resources(RESOURCE_AGENT, namespace: ctx.namespace)
            available_names = agents.map { |a| a.dig('metadata', 'name') }

            CLI::Errors::Handler.handle_not_found(error,
                                                  resource_type: RESOURCE_AGENT,
                                                  resource_name: name,
                                                  cluster: ctx.name,
                                                  available_resources: available_names)
          end

          def display_agent_created(agent, ctx, _description, _synthesis_result)
            agent_name = agent.dig('metadata', 'name')
            status = agent.dig('status', 'phase') || 'Unknown'

            puts
            format_agent_details(
              name: agent_name,
              namespace: ctx.namespace,
              cluster: ctx.name,
              status: format_status(status),
              mode: agent.dig('spec', 'executionMode') || 'autonomous',
              schedule: agent.dig('spec', 'schedule'),
              persona: agent.dig('spec', 'persona') || '(auto-selected)',
              created: Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')
            )

            puts
            puts 'Next steps:'
            puts pastel.dim("aictl agent logs #{agent_name} -f")
            puts pastel.dim("aictl agent code #{agent_name}")
            puts pastel.dim("aictl agent inspect #{agent_name}")
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
            mode = agent_resource.dig('spec', 'executionMode') || 'autonomous'
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

            # Ensure name starts with a letter (Kubernetes requirement)
            name = "agent-#{name}" unless name.match?(/^[a-z]/)

            # Add random suffix to avoid collisions
            "#{name}-#{Time.now.to_i.to_s[-4..]}"
          end

          def format_duration(seconds)
            Formatters::ValueFormatter.duration(seconds)
          end

          def list_cluster_agents(cluster)
            context = CLI::Helpers::ClusterContext.from_options({ cluster: cluster })
            agents = context.client.list_resources(RESOURCE_AGENT, namespace: context.namespace)

            if agents.empty?
              Formatters::ProgressFormatter.info('No agents found')
              puts
              puts 'Create an agent with:'
              puts '  aictl agent create "<description>"'
              return
            end

            table_data = agents.map do |agent|
              {
                name: agent.dig('metadata', 'name'),
                namespace: agent.dig('metadata', 'namespace') || context.namespace,
                mode: agent.dig('spec', 'executionMode') || 'autonomous',
                status: agent.dig('status', 'phase') || 'Unknown'
              }
            end

            Formatters::TableFormatter.agents(table_data)
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
              ctx = CLI::Helpers::ClusterContext.from_options({ cluster: cluster[:name] })

              agents = ctx.client.list_resources(RESOURCE_AGENT, namespace: ctx.namespace)

              agents.each do |agent|
                all_agents << {
                  cluster: cluster[:name],
                  name: agent.dig('metadata', 'name'),
                  mode: agent.dig('spec', 'executionMode') || 'autonomous',
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

          def watch_synthesis_status(k8s, agent_name, namespace)
            max_wait = 600 # Wait up to 10 minutes (local models can be slow)
            interval = 2   # Check every 2 seconds
            elapsed = 0
            start_time = Time.now
            synthesis_data = {}

            Formatters::ProgressFormatter.with_spinner('Synthesizing code from instructions') do
              synthesis_result = nil
              loop do
                status = check_synthesis_status(k8s, agent_name, namespace, synthesis_data, start_time)
                if status
                  synthesis_result = status
                  break
                end

                # Timeout check
                if elapsed >= max_wait
                  Formatters::ProgressFormatter.warn('Synthesis taking longer than expected, continuing in background...')
                  puts
                  puts 'Check synthesis status with:'
                  puts "  aictl agent inspect #{agent_name}"
                  synthesis_result = { success: true, timeout: true }
                  break
                end

                sleep interval
                elapsed += interval
              end
              synthesis_result
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
          end

          def check_synthesis_status(k8s, agent_name, namespace, synthesis_data, start_time)
            agent = k8s.get_resource(RESOURCE_AGENT, agent_name, namespace)
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

          def get_resource_or_exit(resource_type, name)
            ctx = CLI::Helpers::ClusterContext.from_options(options)
            begin
              ctx.client.get_resource(resource_type, name, ctx.namespace)
            rescue K8s::Error::NotFound => e
              handle_agent_not_found(name, ctx, e) if resource_type == RESOURCE_AGENT
              exit 1
            end
          end

          def display_agent_versions(agent_configs, agent_name, cluster_name)
            puts

            if agent_configs.empty?
              puts pastel.yellow("No versioned ConfigMaps found for agent '#{agent_name}'")
              puts
              puts 'Versioned ConfigMaps are created by the operator during automatic learning.'
              puts 'Run the agent a few times to see optimization versions appear here.'
              return
            end

            highlighted_box(
              title: "Agent Versions: #{agent_name}",
              rows: {
                'Agent' => pastel.white.bold(agent_name),
                'Cluster' => cluster_name,
                'Total Versions' => agent_configs.length
              }
            )
            puts

            puts pastel.white.bold('Version History:')

            agent_configs.each do |config_map|
              labels = config_map.dig('metadata', 'labels') || {}
              annotations = config_map.dig('metadata', 'annotations') || {}

              version = labels['version']
              synthesis_type = labels['synthesis-type'] || 'unknown'
              created_at = config_map.dig('metadata', 'creationTimestamp')
              learned_at = annotations['learned-at']
              learned_tasks = annotations['learned-tasks']

              # Format creation time
              if created_at
                begin
                  time = Time.parse(created_at)
                  formatted_time = time.strftime('%Y-%m-%d %H:%M:%S UTC')
                rescue StandardError
                  formatted_time = created_at
                end
              else
                formatted_time = 'Unknown'
              end

              # Format version display
              version_display = case synthesis_type
                                when 'initial'
                                  pastel.blue("v#{version} (initial)")
                                when 'learned'
                                  pastel.green("v#{version} (learned)")
                                when 'manual'
                                  pastel.yellow("v#{version} (manual)")
                                else
                                  pastel.dim("v#{version} (#{synthesis_type})")
                                end

              puts "  #{version_display}"
              puts "    Created: #{pastel.dim(formatted_time)}"

              puts "    Learned: #{pastel.dim(learned_at)}" if learned_at

              if learned_tasks && !learned_tasks.empty?
                tasks = learned_tasks.split(',').map(&:strip)
                puts "    Tasks: #{pastel.cyan(tasks.join(', '))}"
              end

              puts
            end

            puts pastel.white.bold('Available Commands:')
            puts pastel.dim("  aictl agent learning status #{agent_name}")
            puts pastel.dim("  aictl agent inspect #{agent_name}")
          end

          def get_execution_data(agent_name, ctx)
            execution_data = {
              total_runs: 0,
              last_run: nil,
              next_run: nil
            }

            # Get data from CronJob
            begin
              # Get CronJob to find last execution time and next run
              cronjob = ctx.client.get_resource('CronJob', agent_name, ctx.namespace)

              # Get last successful execution time
              last_successful = cronjob.dig('status', 'lastSuccessfulTime')
              if last_successful
                last_time = Time.parse(last_successful)
                execution_data[:last_run] = Formatters::ValueFormatter.time_ago(last_time)
              end

              # Calculate next run time from schedule
              schedule = cronjob.dig('spec', 'schedule')
              execution_data[:next_run] = calculate_next_run(schedule) if schedule
            rescue K8s::Error::NotFound, StandardError
              # CronJob not found or parsing error, continue with job counting
            end

            # Count completed jobs (separate from CronJob processing)
            begin
              # Count total completed jobs for this agent
              jobs = ctx.client.list_resources('Job', namespace: ctx.namespace)

              agent_jobs = jobs.select do |job|
                labels = job.dig('metadata', 'labels') || {}
                labels['app.kubernetes.io/name'] == agent_name
              end

              # Count successful completions
              successful_jobs = agent_jobs.select do |job|
                conditions = job.dig('status', 'conditions') || []
                conditions.any? { |c| c['type'] == 'Complete' && c['status'] == 'True' }
              end

              execution_data[:total_runs] = successful_jobs.length
            rescue StandardError
              # If job listing fails, keep default count of 0
            end

            execution_data
          end

          def calculate_next_run(schedule)
            # Simple next run calculation for common cron patterns
            # Handle the most common case: */N * * * * (every N minutes)

            parts = schedule.split
            return schedule unless parts.length == 5 # Not a valid cron expression

            minute, hour, day, month, weekday = parts
            current_time = Time.now

            # Handle every-N-minutes pattern: */10 * * * *
            if minute.start_with?('*/') && hour == '*' && day == '*' && month == '*' && weekday == '*'
              interval = minute[2..].to_i
              if interval > 0 && interval < 60
                current_minute = current_time.min
                current_time.sec

                # Find the next occurrence
                next_minute_mark = ((current_minute / interval) + 1) * interval

                if next_minute_mark < 60
                  # Same hour
                  next_time = Time.new(current_time.year, current_time.month, current_time.day,
                                       current_time.hour, next_minute_mark, 0)
                else
                  # Next hour
                  next_hour = current_time.hour + 1
                  next_minute = next_minute_mark - 60

                  if next_hour < 24
                    next_time = Time.new(current_time.year, current_time.month, current_time.day,
                                         next_hour, next_minute, 0)
                  else
                    # Next day
                    next_day = current_time + (24 * 60 * 60) # Add one day
                    next_time = Time.new(next_day.year, next_day.month, next_day.day,
                                         0, next_minute, 0)
                  end
                end

                return Formatters::ValueFormatter.time_until(next_time)
              end
            end

            # For other patterns, show the schedule (could add more patterns later)
            schedule
          rescue StandardError
            schedule
          end
        end
      end
    end
  end
end
