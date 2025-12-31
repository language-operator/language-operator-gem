# frozen_string_literal: true

require 'open3'
require_relative '../../helpers/label_utils'

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Log streaming for agents
        module Logs
          def self.included(base)
            base.class_eval do
              desc 'logs NAME', 'Show agent execution logs'
              long_desc <<-DESC
                Stream agent execution logs in real-time.

                Use -f to follow logs continuously (like tail -f).

                Examples:
                  langop agent logs my-agent
                  langop agent logs my-agent -f
              DESC
              option :cluster, type: :string, desc: 'Override current cluster context'
              option :follow, type: :boolean, aliases: '-f', default: false, desc: 'Follow logs'
              option :tail, type: :numeric, default: 100, desc: 'Number of lines to show from the end'
              def logs(name)
                handle_command_error('get logs') do
                  ctx = CLI::Helpers::ClusterContext.from_options(options)

                  # Get agent to determine the pod name
                  agent = get_resource_or_exit(LanguageOperator::Constants::RESOURCE_AGENT, name)

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
                  # Use normalized label selector for pod discovery
                  label_selector = CLI::Helpers::LabelUtils.agent_pod_selector(name)

                  # Use kubectl logs with label selector
                  cmd = "#{ctx.kubectl_prefix} logs -l #{label_selector} #{tail_arg} #{follow_arg} --all-containers"

                  Formatters::ProgressFormatter.info("Streaming logs for agent '#{name}'...")
                  puts

                  # Track threads and interruption state for cleanup
                  stdout_thread = nil
                  stderr_thread = nil
                  interrupted = false

                  # Install signal handler for graceful interruption
                  original_int_handler = Signal.trap('INT') do
                    interrupted = true
                    stdout_thread&.terminate
                    stderr_thread&.terminate
                    puts "\n[Interrupted]"
                    exit(0)
                  end

                  begin
                    # Stream raw logs in real-time without formatting
                    Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
                      # Close unused stdin immediately to prevent resource leak
                      stdin.close

                      # Handle stdout (logs)
                      stdout_thread = Thread.new do
                        stdout.each_line do |line|
                          break if interrupted

                          puts line
                          $stdout.flush
                        end
                      rescue IOError
                        # Expected when stream is closed during interruption
                      end

                      # Handle stderr (errors)
                      stderr_thread = Thread.new do
                        stderr.each_line do |line|
                          break if interrupted

                          warn line
                        end
                      rescue IOError
                        # Expected when stream is closed during interruption
                      end

                      # Wait for both streams to complete or interruption
                      stdout_thread.join unless interrupted
                      stderr_thread.join unless interrupted

                      # Check exit status if not interrupted
                      unless interrupted
                        exit_status = wait_thr.value
                        exit exit_status.exitstatus unless exit_status.success?
                      end
                    end
                  ensure
                    # Restore original signal handler
                    Signal.trap('INT', original_int_handler)

                    # Cleanup threads if they're still running
                    stdout_thread&.terminate
                    stderr_thread&.terminate
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
