# frozen_string_literal: true

require 'thor'
require_relative '../../command_loader'
require_relative '../../wizards/agent_wizard'

# Include all agent subcommand modules
require_relative 'workspace'
require_relative 'optimize'
require_relative 'rollback'
require_relative 'code_operations'
require_relative 'logs'
require_relative 'lifecycle'

# Include helper modules
require_relative 'helpers/cluster_llm_client'
require_relative 'helpers/code_parser'
require_relative 'helpers/synthesis_watcher'
require_relative 'helpers/optimization_helper'

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Base agent command class
        class Base < BaseCommand
          include Constants
          include CLI::Helpers::ClusterValidator
          include CLI::Helpers::UxHelper
          include Agent::Helpers::CodeParser
          include Agent::Helpers::SynthesisWatcher
          include Agent::Helpers::OptimizationHelper

          # Include all subcommand modules
          include Workspace
          include Optimize
          include Rollback
          include CodeOperations
          include Logs
          include Lifecycle

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
          def create(_description = nil)
            # TODO: Extract full implementation from original agent.rb
            puts 'Agent create command - implementation pending'
          end

          desc 'list', 'List all agents in current cluster'
          option :cluster, type: :string, desc: 'Override current cluster context'
          option :all_clusters, type: :boolean, default: false, desc: 'Show agents across all clusters'
          def list
            # TODO: Extract full implementation from original agent.rb
            puts 'Agent list command - implementation pending'
          end

          desc 'inspect NAME', 'Show detailed agent information'
          option :cluster, type: :string, desc: 'Override current cluster context'
          def inspect(_name)
            # TODO: Extract full implementation from original agent.rb
            puts 'Agent inspect command - implementation pending'
          end

          desc 'delete NAME', 'Delete an agent'
          option :cluster, type: :string, desc: 'Override current cluster context'
          option :force, type: :boolean, default: false, desc: 'Skip confirmation'
          def delete(_name)
            # TODO: Extract full implementation from original agent.rb
            puts 'Agent delete command - implementation pending'
          end

          private

          # Shared helper methods that are used across multiple commands
          # These will be extracted from the original agent.rb

          def handle_agent_not_found(name, ctx)
            # Get available agents for fuzzy matching
            agents = ctx.client.list_resources(RESOURCE_AGENT, namespace: ctx.namespace)
            available_names = agents.map { |a| a.dig('metadata', 'name') }

            error = K8s::Error::NotFound.new(404, 'Not Found', RESOURCE_AGENT)
            Errors::Handler.handle_not_found(error,
                                             resource_type: RESOURCE_AGENT,
                                             resource_name: name,
                                             cluster: ctx.name,
                                             available_resources: available_names)
          end

          def display_agent_created(agent, _cluster, _description, _synthesis_result)
            agent_name = agent.dig('metadata', 'name')

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

          def format_duration(seconds)
            Formatters::ValueFormatter.duration(seconds)
          end

          def list_cluster_agents(cluster)
            ctx = Helpers::ClusterContext.from_options(cluster: cluster)

            Formatters::ProgressFormatter.info("Agents in cluster '#{cluster}'")

            agents = ctx.client.list_resources(RESOURCE_AGENT, namespace: ctx.namespace)

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

              agents = ctx.client.list_resources(RESOURCE_AGENT, namespace: ctx.namespace)

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
        end
      end
    end
  end
end
