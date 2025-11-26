# frozen_string_literal: true

require 'open3'

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Lifecycle management for agents (pause/resume)
        module Lifecycle
          def self.included(base)
            base.class_eval do
              desc 'pause NAME', 'Pause scheduled agent execution'
              option :cluster, type: :string, desc: 'Override current cluster context'
              def pause(name)
                handle_command_error('pause agent') do
                  ctx = CLI::Helpers::ClusterContext.from_options(options)

                  # Get agent
                  agent = get_resource_or_exit(LanguageOperator::Constants::RESOURCE_AGENT, name)

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

                  Formatters::ProgressFormatter.with_spinner("Pausing agent '#{name}'") do
                    # Use kubectl to patch the cronjob
                    cmd = "#{ctx.kubectl_prefix} patch cronjob #{cronjob_name} -p '{\"spec\":{\"suspend\":true}}'"
                    _, stderr, status = Open3.capture3(cmd)

                    unless status.success?
                      error_msg = "Failed to pause agent '#{name}': kubectl command failed (exit code: #{status.exitstatus})"
                      error_msg += "\nError: #{stderr.strip}" unless stderr.nil? || stderr.strip.empty?
                      raise error_msg
                    end
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
                  ctx = CLI::Helpers::ClusterContext.from_options(options)

                  # Get agent
                  agent = get_resource_or_exit(LanguageOperator::Constants::RESOURCE_AGENT, name)

                  mode = agent.dig('spec', 'mode') || 'autonomous'
                  unless mode == 'scheduled'
                    Formatters::ProgressFormatter.warn("Agent '#{name}' is not a scheduled agent (mode: #{mode})")
                    puts
                    puts 'Only scheduled agents can be resumed.'
                    exit 1
                  end

                  # Resume the CronJob by setting spec.suspend = false
                  cronjob_name = name

                  Formatters::ProgressFormatter.with_spinner("Resuming agent '#{name}'") do
                    # Use kubectl to patch the cronjob
                    cmd = "#{ctx.kubectl_prefix} patch cronjob #{cronjob_name} -p '{\"spec\":{\"suspend\":false}}'"
                    _, stderr, status = Open3.capture3(cmd)

                    unless status.success?
                      error_msg = "Failed to resume agent '#{name}': kubectl command failed (exit code: #{status.exitstatus})"
                      error_msg += "\nError: #{stderr.strip}" unless stderr.nil? || stderr.strip.empty?
                      raise error_msg
                    end
                  end

                  Formatters::ProgressFormatter.success("Agent '#{name}' resumed")
                  puts
                  puts 'The agent will now execute according to its schedule.'
                  puts
                  puts 'View next execution time with:'
                  puts "  aictl agent inspect #{name}"
                end
              end
            end
          end
        end
      end
    end
  end
end
