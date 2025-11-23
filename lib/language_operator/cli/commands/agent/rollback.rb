# frozen_string_literal: true

require 'tty-prompt'

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Version rollback for optimized agents
        module Rollback
          def self.included(base)
            base.class_eval do
              desc 'rollback NAME', 'Rollback agent optimization to a previous version'
              long_desc <<-DESC
                Rollback an optimized agent to a previous ConfigMap version.

                This command lists all available versions of the agent's code ConfigMap
                and allows you to select a previous version to restore. Useful when an
                optimization introduces bugs or performance regressions.

                Examples:
                  aictl agent rollback my-agent                  # Interactive version selection
                  aictl agent rollback my-agent --version v2     # Rollback to specific version
                  aictl agent rollback my-agent --list           # List available versions only
              DESC
              option :cluster, type: :string, desc: 'Override current cluster context'
              option :version, type: :string, desc: 'Specific version to rollback to (e.g., v2)'
              option :list, type: :boolean, default: false, desc: 'List available versions only'
              option :force, type: :boolean, default: false, desc: 'Skip confirmation'
              def rollback(name)
                handle_command_error('rollback agent') do
                  ctx = Helpers::ClusterContext.from_options(options)
                  base_configmap_name = "#{name}-code"

                  # Get current ConfigMap
                  current_configmap = ctx.client.get_resource('ConfigMap', base_configmap_name, ctx.namespace)
                  current_version = current_configmap.dig('metadata', 'annotations', 'langop.io/version') || 'v0'

                  # List all versioned ConfigMaps
                  configmaps = ctx.client.list_resources(
                    'ConfigMap',
                    namespace: ctx.namespace,
                    label_selector: "langop.io/agent=#{name},langop.io/component=agent-code"
                  )

                  # Filter and sort versions
                  versioned_cms = configmaps.select do |cm|
                    cm.dig('metadata', 'name').match?(/#{name}-code-v\d+/)
                  end

                  if versioned_cms.empty?
                    Formatters::ProgressFormatter.error("No versioned ConfigMaps found for agent '#{name}'")
                    puts 'Agent must be optimized at least once before rollback is possible.'
                    return
                  end

                  sorted_cms = versioned_cms.sort_by do |cm|
                    version_str = cm.dig('metadata', 'annotations', 'langop.io/version') || 'v0'
                    -version_str.sub(/^v/, '').to_i
                  end

                  # List mode: just show versions
                  if options[:list]
                    puts
                    puts pastel.cyan("Available versions for '#{name}':")
                    puts
                    sorted_cms.each do |cm|
                      version = cm.dig('metadata', 'annotations', 'langop.io/version')
                      optimized_at = cm.dig('metadata', 'annotations', 'langop.io/optimized-at')
                      task = cm.dig('metadata', 'annotations', 'langop.io/optimized-task')
                      is_current = version == current_version

                      status = is_current ? pastel.green('(current)') : ''
                      puts "  #{pastel.bold(version)} #{status}"
                      puts "    Optimized: #{format_timestamp(Time.parse(optimized_at))}" if optimized_at
                      puts "    Task: #{task}" if task
                      puts
                    end
                    return
                  end

                  # Determine target version
                  target_version = options[:version] || select_version_interactively(sorted_cms, current_version)

                  return unless target_version

                  # Find the target ConfigMap
                  target_cm = sorted_cms.find do |cm|
                    cm.dig('metadata', 'annotations', 'langop.io/version') == target_version
                  end

                  unless target_cm
                    Formatters::ProgressFormatter.error("Version '#{target_version}' not found")
                    return
                  end

                  # Confirm rollback
                  unless options[:force]
                    puts
                    puts "This will rollback agent '#{name}' from #{current_version} to #{target_version}"
                    puts pastel.yellow('This operation will restart the agent pod.')
                    puts
                    return unless prompt.yes?('Continue with rollback?')
                  end

                  # Perform rollback
                  Formatters::ProgressFormatter.start("Rolling back to #{target_version}...")

                  # Get the code from target version
                  target_code = target_cm.dig('data', 'agent.rb')

                  # Update base ConfigMap
                  updated_base_configmap = {
                    'apiVersion' => 'v1',
                    'kind' => 'ConfigMap',
                    'metadata' => {
                      'name' => base_configmap_name,
                      'namespace' => ctx.namespace,
                      'resourceVersion' => current_configmap.metadata.resourceVersion,
                      'labels' => current_configmap.dig('metadata', 'labels') || {},
                      'annotations' => {
                        'langop.io/version' => target_version,
                        'langop.io/rolled-back' => 'true',
                        'langop.io/rolled-back-at' => Time.now.iso8601,
                        'langop.io/previous-version' => current_version
                      }
                    },
                    'data' => {
                      'agent.rb' => target_code
                    }
                  }

                  ctx.client.update_resource('ConfigMap', base_configmap_name, ctx.namespace, updated_base_configmap, 'v1')

                  # Restart pod
                  restart_agent_pod(ctx, name)

                  Formatters::ProgressFormatter.success("Successfully rolled back to #{target_version}")
                  puts
                  puts "Agent '#{name}' is now running version #{target_version}"
                  puts
                end
              end

              private

              # Interactive version selection for rollback
              #
              # @param sorted_cms [Array] Sorted ConfigMaps
              # @param current_version [String] Current version
              # @return [String, nil] Selected version or nil if cancelled
              def select_version_interactively(sorted_cms, current_version)
                puts
                puts pastel.cyan('Available versions:')
                puts

                choices = sorted_cms.map do |cm|
                  version = cm.dig('metadata', 'annotations', 'langop.io/version')
                  optimized_at = cm.dig('metadata', 'annotations', 'langop.io/optimized-at')
                  task = cm.dig('metadata', 'annotations', 'langop.io/optimized-task')
                  is_current = version == current_version

                  label = if is_current
                            "#{version} (current) - Task: #{task}"
                          else
                            timestamp = optimized_at ? format_timestamp(Time.parse(optimized_at)) : 'unknown'
                            "#{version} - #{timestamp} - Task: #{task}"
                          end

                  { name: label, value: version, disabled: is_current ? '(current version)' : false }
                end

                prompt.select('Select version to rollback to:', choices, per_page: 10)
              rescue TTY::Reader::InputInterrupt
                puts
                puts pastel.yellow('Rollback cancelled')
                nil
              end

              def format_timestamp(time)
                Formatters::ValueFormatter.timestamp(time)
              end
            end
          end
        end
      end
    end
  end
end
