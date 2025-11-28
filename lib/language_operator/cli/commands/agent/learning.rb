# frozen_string_literal: true

require 'json'
require_relative '../../command_loader'
require_relative '../../../constants/kubernetes_labels'

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Learning monitoring and control for agents
        module Learning
          def self.included(base)
            base.class_eval do
              desc 'learning SUBCOMMAND ...ARGS', 'Monitor and control agent learning'
              subcommand 'learning', LearningCommands
            end
          end

          # Learning subcommand class
          class LearningCommands < BaseCommand
            include Constants
            include CLI::Helpers::ClusterValidator
            include CLI::Helpers::UxHelper

            desc 'status NAME', 'Show current learning status and optimization history'
            long_desc <<-DESC
              Display the current learning status and optimization history for an agent.

              Shows learned tasks, confidence scores, and automatic optimization progress
              managed by the operator.

              Examples:
                aictl agent learning status my-agent
                aictl agent learning status my-agent --cluster production
            DESC
            option :cluster, type: :string, desc: 'Override current cluster context'
            def status(name)
              handle_command_error('get learning status') do
                ctx = CLI::Helpers::ClusterContext.from_options(options)

                # Get agent to verify it exists
                agent = ctx.client.get_resource(RESOURCE_AGENT, name, ctx.namespace)

                # Query learning status ConfigMap
                learning_status = get_learning_status(ctx.client, name, ctx.namespace)

                # Display learning information
                display_learning_status(agent, learning_status, ctx.name)
              end
            rescue K8s::Error::NotFound
              # Handle agent not found
              ctx = CLI::Helpers::ClusterContext.from_options(options)
              available_agents = ctx.client.list_resources(RESOURCE_AGENT, namespace: ctx.namespace)
              available_names = available_agents.map { |a| a.dig('metadata', 'name') }

              error = K8s::Error::NotFound.new(404, 'Not Found', RESOURCE_AGENT)
              CLI::Errors::Handler.handle_not_found(error,
                                                    resource_type: RESOURCE_AGENT,
                                                    resource_name: name,
                                                    cluster: ctx.name,
                                                    available_resources: available_names)
            end

            desc 'enable NAME', 'Enable automatic learning for an agent'
            long_desc <<-DESC
              Enable automatic learning for an agent by removing the learning-disabled annotation.

              Learning is enabled by default, so this command only needs to be used if learning
              was previously disabled.

              Examples:
                aictl agent learning enable my-agent
            DESC
            option :cluster, type: :string, desc: 'Override current cluster context'
            def enable(name)
              handle_command_error('enable learning') do
                ctx = CLI::Helpers::ClusterContext.from_options(options)

                # Get agent to verify it exists
                agent = ctx.client.get_resource(RESOURCE_AGENT, name, ctx.namespace)

                # Check current status
                annotations = agent.dig('metadata', 'annotations')
                annotations = annotations.respond_to?(:to_h) ? annotations.to_h : (annotations || {})
                disabled_annotation = Constants::KubernetesLabels::LEARNING_DISABLED_LABEL

                unless annotations.key?(disabled_annotation)
                  Formatters::ProgressFormatter.info("Learning is already enabled for agent '#{name}'")
                  return
                end

                # Remove the learning-disabled annotation
                Formatters::ProgressFormatter.with_spinner("Enabling learning for agent '#{name}'") do
                  remove_annotation(ctx.client, name, ctx.namespace, disabled_annotation)
                end

                Formatters::ProgressFormatter.success("Learning enabled for agent '#{name}'")
              end
            end

            desc 'disable NAME', 'Disable automatic learning for an agent'
            long_desc <<-DESC
              Disable automatic learning for an agent by adding the learning-disabled annotation.

              This prevents the operator from automatically optimizing the agent's tasks but
              does not affect existing learned optimizations.

              Examples:
                aictl agent learning disable my-agent
            DESC
            option :cluster, type: :string, desc: 'Override current cluster context'
            def disable(name)
              handle_command_error('disable learning') do
                ctx = CLI::Helpers::ClusterContext.from_options(options)

                # Get agent to verify it exists
                agent = ctx.client.get_resource(RESOURCE_AGENT, name, ctx.namespace)

                # Check current status
                annotations = agent.dig('metadata', 'annotations')
                annotations = annotations.respond_to?(:to_h) ? annotations.to_h : (annotations || {})
                disabled_annotation = Constants::KubernetesLabels::LEARNING_DISABLED_LABEL

                if annotations.key?(disabled_annotation)
                  Formatters::ProgressFormatter.info("Learning is already disabled for agent '#{name}'")
                  return
                end

                # Add the learning-disabled annotation
                Formatters::ProgressFormatter.with_spinner("Disabling learning for agent '#{name}'") do
                  add_annotation(ctx.client, name, ctx.namespace, disabled_annotation, 'true')
                end

                Formatters::ProgressFormatter.success("Learning disabled for agent '#{name}'")
              end
            end

            private

            def get_learning_status(client, name, namespace)
              config_map_name = "#{name}-learning-status"
              begin
                client.get_resource('ConfigMap', config_map_name, namespace)
              rescue K8s::Error::NotFound
                # Learning status ConfigMap doesn't exist yet - return nil
                nil
              end
            end

            def display_learning_status(agent, learning_status, cluster_name)
              agent_name = agent.dig('metadata', 'name')
              annotations = agent.dig('metadata', 'annotations')
              annotations = annotations.respond_to?(:to_h) ? annotations.to_h : (annotations || {})

              puts

              # Display Agent Status box
              display_agent_status_box(agent, cluster_name)
              puts

              # Display Learning Status box
              display_learning_status_box(agent, learning_status, annotations)

              # If learning status ConfigMap exists, show detailed information
              if learning_status
                display_detailed_learning_status(learning_status)
              else
                learning_enabled = !annotations.key?(Constants::KubernetesLabels::LEARNING_DISABLED_LABEL)
                display_learning_explanation(learning_enabled)
              end

              # Show next steps
              puts pastel.white.bold('Available Commands:')
              learning_enabled = !annotations.key?(Constants::KubernetesLabels::LEARNING_DISABLED_LABEL)
              if learning_enabled
                puts pastel.dim("  aictl agent learning disable #{agent_name}    # Disable automatic learning")
              else
                puts pastel.dim("  aictl agent learning enable #{agent_name}     # Enable automatic learning")
              end
              puts pastel.dim("  aictl agent inspect #{agent_name}               # View agent configuration")
              puts pastel.dim("  aictl agent logs #{agent_name}                 # View execution logs")
              puts pastel.dim("  aictl agent versions #{agent_name}             # View synthesis history")
            end

            def display_detailed_learning_status(learning_status)
              data = learning_status['data'] || {}

              # Parse learning data if available
              if data['tasks']
                tasks_data = begin
                  JSON.parse(data['tasks'])
                rescue StandardError
                  {}
                end

                if tasks_data.any?
                  puts pastel.white.bold('Learned Tasks:')
                  tasks_data.each do |task_name, task_info|
                    confidence = task_info['confidence'] || 0
                    executions = task_info['executions'] || 0
                    status = task_info['status'] || 'neural'

                    confidence_color = determine_confidence_color(confidence)

                    puts "  #{pastel.cyan(task_name)}"
                    puts "    Status: #{format_task_status(status)}"
                    confidence_text = pastel.send(confidence_color, "#{confidence}%")
                    puts "    Confidence: #{confidence_text} (#{executions} executions)"
                  end
                  puts
                end
              end

              # Show optimization history if available
              return unless data['history']

              history_data = begin
                JSON.parse(data['history'])
              rescue StandardError
                []
              end

              return unless history_data.any?

              puts pastel.white.bold('Optimization History:')
              history_data.last(5).each do |event|
                timestamp = event['timestamp'] || 'Unknown'
                action = event['action'] || 'Unknown'
                task = event['task'] || 'Unknown'

                puts "  #{pastel.dim(timestamp)} - #{action} #{pastel.cyan(task)}"
              end
              puts
            end

            def format_task_status(status)
              case status
              when 'symbolic'
                pastel.green('Learned (Symbolic)')
              when 'neural'
                pastel.yellow('Learning (Neural)')
              when 'hybrid'
                pastel.blue('Hybrid')
              else
                pastel.dim(status.capitalize)
              end
            end

            def add_annotation(client, name, namespace, annotation_key, annotation_value)
              # Get current agent
              agent = client.get_resource(RESOURCE_AGENT, name, namespace)

              # Add annotation
              annotations = agent.dig('metadata', 'annotations')
              annotations = annotations.respond_to?(:to_h) ? annotations.to_h : (annotations || {})
              annotations[annotation_key] = annotation_value
              agent['metadata']['annotations'] = annotations

              # Update the agent
              client.update_resource(agent)
            end

            def remove_annotation(client, name, namespace, annotation_key)
              # Get current agent
              agent = client.get_resource(RESOURCE_AGENT, name, namespace)

              # Remove annotation
              annotations = agent.dig('metadata', 'annotations')
              annotations = annotations.respond_to?(:to_h) ? annotations.to_h : (annotations || {})
              annotations.delete(annotation_key)
              agent['metadata']['annotations'] = annotations

              # Update the agent
              client.update_resource(agent)
            end

            def format_agent_timestamp(agent)
              created_time = agent.dig('metadata', 'creationTimestamp')
              return 'Unknown' unless created_time

              begin
                Time.parse(created_time).strftime('%Y-%m-%d %H:%M:%S UTC')
              rescue StandardError
                'Unknown'
              end
            end

            def display_agent_status_box(agent, cluster_name)
              agent_name = agent.dig('metadata', 'name')
              timestamp = format_agent_timestamp(agent)

              # Get agent operational status
              status = agent['status']
              if status && status['conditions']
                ready_condition = status['conditions'].find { |c| c['type'] == 'Ready' }
                if ready_condition
                  begin
                    last_activity = Time.parse(ready_condition['lastTransitionTime']).strftime('%Y-%m-%d %H:%M:%S UTC')
                    status_text = ready_condition['status'] == 'True' ? 'Ready' : 'Not Ready'
                    status_colored = ready_condition['status'] == 'True' ? pastel.green(status_text) : pastel.yellow(status_text)
                  rescue StandardError
                    last_activity = 'Unknown'
                    status_colored = pastel.dim('Unknown')
                  end
                else
                  last_activity = 'Unknown'
                  status_colored = pastel.dim('Unknown')
                end
              else
                last_activity = 'Unknown'
                status_colored = pastel.dim('Unknown')
              end

              highlighted_box(
                title: 'Agent Status',
                color: :yellow,
                rows: {
                  'Name' => pastel.white.bold(agent_name),
                  'Cluster' => cluster_name,
                  'Created' => timestamp,
                  'Last Activity' => last_activity,
                  'Status' => status_colored
                }
              )
            end

            def display_learning_status_box(_agent, _learning_status, annotations)
              learning_enabled = !annotations.key?(Constants::KubernetesLabels::LEARNING_DISABLED_LABEL)
              status_color = learning_enabled ? :green : :yellow
              status_text = learning_enabled ? 'Enabled' : 'Disabled'

              # TODO: Replace with real execution data when backend is ready (issue #88)
              runs_completed = 'Unknown'
              progress = 'Waiting for execution data'

              highlighted_box(
                title: 'Learning Status',
                color: :cyan,
                rows: {
                  'Learning' => pastel.send(status_color).bold(status_text),
                  'Threshold' => "#{pastel.cyan('10 successful runs')} (auto-learning trigger)",
                  'Confidence Target' => "#{pastel.cyan('85%')} (pattern detection)",
                  'Runs Completed' => runs_completed,
                  'Progress' => progress
                }
              )
            end

            def display_learning_explanation(learning_enabled)
              if learning_enabled
                puts pastel.dim('Learning is enabled and will begin automatically after the agent completes 10 successful runs.')
                puts pastel.dim('Neural tasks will be analyzed for patterns and converted to symbolic implementations.')
              else
                puts pastel.yellow('Learning is disabled for this agent.')
                puts pastel.dim('Enable learning to allow automatic task optimization after sufficient executions.')
              end
              puts
              puts pastel.dim('Note: Execution metrics will be available once the agent starts running and')
              puts pastel.dim('the operator begins collecting telemetry data.')
              puts
            end

            def determine_confidence_color(confidence)
              if confidence >= 85
                :green
              elsif confidence >= 70
                :yellow
              else
                :red
              end
            end
          end
        end
      end
    end
  end
end
