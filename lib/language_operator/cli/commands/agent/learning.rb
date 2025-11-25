# frozen_string_literal: true

require 'json'
require_relative '../../command_loader'

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
                annotations = agent.dig('metadata', 'annotations') || {}
                disabled_annotation = 'langop.io/learning-disabled'

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
                annotations = agent.dig('metadata', 'annotations') || {}
                disabled_annotation = 'langop.io/learning-disabled'

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
              annotations = agent.dig('metadata', 'annotations') || {}
              
              puts
              
              # Learning enablement status
              learning_enabled = !annotations.key?('langop.io/learning-disabled')
              status_color = learning_enabled ? :green : :yellow
              status_text = learning_enabled ? 'Enabled' : 'Disabled'
              
              highlighted_box(
                title: 'Learning Status',
                rows: {
                  'Agent' => pastel.white.bold(agent_name),
                  'Cluster' => cluster_name,
                  'Learning' => pastel.send(status_color).bold(status_text),
                  'Last Updated' => agent.dig('metadata', 'resourceVersion') || 'Unknown'
                }
              )
              puts

              # If learning status ConfigMap exists, show detailed information
              if learning_status
                display_detailed_learning_status(learning_status)
              else
                puts pastel.dim('No learning status data available yet.')
                puts pastel.dim('Learning data will appear after the agent has run and the operator has analyzed its behavior.')
                puts
              end

              # Show next steps
              puts pastel.white.bold('Available Commands:')
              if learning_enabled
                puts pastel.dim("  aictl agent learning disable #{agent_name}")
              else
                puts pastel.dim("  aictl agent learning enable #{agent_name}")
              end
              puts pastel.dim("  aictl agent versions #{agent_name}")
              puts pastel.dim("  aictl agent inspect #{agent_name}")
            end

            def display_detailed_learning_status(learning_status)
              data = learning_status.dig('data') || {}
              
              # Parse learning data if available
              if data['tasks']
                tasks_data = JSON.parse(data['tasks']) rescue {}
                
                if tasks_data.any?
                  puts pastel.white.bold('Learned Tasks:')
                  tasks_data.each do |task_name, task_info|
                    confidence = task_info['confidence'] || 0
                    executions = task_info['executions'] || 0
                    status = task_info['status'] || 'neural'
                    
                    confidence_color = confidence >= 85 ? :green : confidence >= 70 ? :yellow : :red
                    
                    puts "  #{pastel.cyan(task_name)}"
                    puts "    Status: #{format_task_status(status)}"
                    confidence_text = pastel.send(confidence_color, "#{confidence}%")
                    puts "    Confidence: #{confidence_text} (#{executions} executions)"
                  end
                  puts
                end
              end

              # Show optimization history if available
              if data['history']
                history_data = JSON.parse(data['history']) rescue []
                
                if history_data.any?
                  puts pastel.white.bold('Optimization History:')
                  history_data.last(5).each do |event|
                    timestamp = event['timestamp'] || 'Unknown'
                    action = event['action'] || 'Unknown'
                    task = event['task'] || 'Unknown'
                    
                    puts "  #{pastel.dim(timestamp)} - #{action} #{pastel.cyan(task)}"
                  end
                  puts
                end
              end
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
              annotations = agent.dig('metadata', 'annotations') || {}
              annotations[annotation_key] = annotation_value
              agent['metadata']['annotations'] = annotations
              
              # Update the agent
              client.update_resource(agent)
            end

            def remove_annotation(client, name, namespace, annotation_key)
              # Get current agent
              agent = client.get_resource(RESOURCE_AGENT, name, namespace)
              
              # Remove annotation
              annotations = agent.dig('metadata', 'annotations') || {}
              annotations.delete(annotation_key)
              agent['metadata']['annotations'] = annotations
              
              # Update the agent
              client.update_resource(agent)
            end
          end
        end
      end
    end
  end
end