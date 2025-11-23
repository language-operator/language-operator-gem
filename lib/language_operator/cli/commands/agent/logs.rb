# frozen_string_literal: true

require 'open3'

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
            end
          end
        end
      end
    end
  end
end
