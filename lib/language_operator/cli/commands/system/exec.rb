# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module System
        # Agent execution in test pod
        module Exec
          def self.included(base)
            base.class_eval do
              desc 'exec [AGENT_FILE]', 'Execute an agent file in a test pod on the cluster'
              long_desc <<-DESC
                Deploy and execute an agent file in a temporary test pod on the Kubernetes cluster.

                This command creates a ConfigMap with the agent code, deploys a test pod,
                streams the logs until completion, and cleans up all resources.

                The agent code is mounted at /etc/agent/code/agent.rb as expected by the agent runtime.

                Agent code can be provided either as a file path or via STDIN.
                If no file path is provided, the command will read from STDIN.

                Examples:
                  # Execute a synthesized agent file
                  aictl system exec agent.rb

                  # Execute with a custom agent name
                  aictl system exec agent.rb --agent-name my-test

                  # Keep the pod after execution for debugging
                  aictl system exec agent.rb --keep-pod

                  # Use a different agent image
                  aictl system exec agent.rb --image ghcr.io/language-operator/agent:v0.1.0

                  # Read agent code from STDIN
                  cat agent.rb | aictl system exec

                  # Pipe synthesized code directly to execution
                  cat agent.txt | aictl system synthesize | aictl system exec
              DESC
              option :agent_name, type: :string, default: 'test-agent', desc: 'Name for the test agent pod'
              option :keep_pod, type: :boolean, default: false, desc: 'Keep the pod after execution (for debugging)'
              option :image, type: :string, default: 'ghcr.io/language-operator/agent:latest', desc: 'Agent container image'
              option :timeout, type: :numeric, default: 300, desc: 'Timeout in seconds for agent execution'
              def exec(agent_file = nil)
                handle_command_error('exec agent') do
                  # Verify cluster is selected
                  unless ctx.client
                    Formatters::ProgressFormatter.error('No cluster context available')
                    puts
                    puts 'Please configure kubectl with a valid cluster context:'
                    puts '  kubectl config get-contexts'
                    puts '  kubectl config use-context <context-name>'
                    exit 1
                  end

                  # Read agent code from file or STDIN
                  agent_code = if agent_file && !agent_file.strip.empty?
                                 # Read from file
                                 unless File.exist?(agent_file)
                                   Formatters::ProgressFormatter.error("Agent file not found: #{agent_file}")
                                   exit 1
                                 end
                                 File.read(agent_file)
                               elsif $stdin.tty?
                                 # Read from STDIN
                                 Formatters::ProgressFormatter.error('No agent code provided')
                                 puts
                                 puts 'Provide agent code either as a file or via STDIN:'
                                 puts '  aictl system exec agent.rb'
                                 puts '  cat agent.rb | aictl system exec'
                                 exit 1
                               else
                                 code = $stdin.read.strip
                                 if code.empty?
                                   Formatters::ProgressFormatter.error('No agent code provided')
                                   puts
                                   puts 'Provide agent code either as a file or via STDIN:'
                                   puts '  aictl system exec agent.rb'
                                   puts '  cat agent.rb | aictl system exec'
                                   exit 1
                                 end
                                 code
                               end

                  # Generate unique names
                  timestamp = Time.now.to_i
                  configmap_name = "#{options[:agent_name]}-code-#{timestamp}"
                  pod_name = "#{options[:agent_name]}-#{timestamp}"

                  begin
                    # Create ConfigMap with agent code
                    Formatters::ProgressFormatter.with_spinner('Creating ConfigMap with agent code') do
                      create_agent_configmap(configmap_name, agent_code)
                    end

                    # Create test pod
                    Formatters::ProgressFormatter.with_spinner('Creating test pod') do
                      create_test_pod(pod_name, configmap_name, options[:image])
                    end

                    # Wait for pod to be ready or running
                    Formatters::ProgressFormatter.with_spinner('Waiting for pod to start') do
                      wait_for_pod_start(pod_name, timeout: 60)
                    end

                    # Stream logs until pod completes
                    stream_pod_logs(pod_name, timeout: options[:timeout])

                    # Wait for pod to fully terminate and get final status
                    exit_code = wait_for_pod_termination(pod_name)

                    if exit_code&.zero?
                      Formatters::ProgressFormatter.success('Agent completed successfully')
                    elsif exit_code
                      Formatters::ProgressFormatter.error("Agent failed with exit code: #{exit_code}")
                    else
                      Formatters::ProgressFormatter.warn('Unable to determine pod exit status')
                    end
                  ensure
                    # Clean up resources unless --keep-pod
                    puts
                    puts
                    if options[:keep_pod]
                      Formatters::ProgressFormatter.info('Resources kept for debugging:')
                      puts "  Pod: #{pod_name}"
                      puts "  ConfigMap: #{configmap_name}"
                      puts
                      puts "To view logs: kubectl logs -n #{ctx.namespace} #{pod_name}"
                      puts "To delete:    kubectl delete pod,configmap -n #{ctx.namespace} #{pod_name} #{configmap_name}"
                    else
                      Formatters::ProgressFormatter.with_spinner('Cleaning up resources') do
                        delete_pod(pod_name)
                        delete_configmap(configmap_name)
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
  end
end
