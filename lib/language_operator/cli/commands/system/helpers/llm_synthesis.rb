# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module System
        module Helpers
          # LLM synthesis utilities
          module LlmSynthesis
            # Call LLM to generate code from synthesis prompt using cluster model
            def call_llm_for_synthesis(prompt, model_name)
              require 'json'
              require 'faraday'

              # Get model resource
              model = get_resource_or_exit('LanguageModel', model_name)
              model_id = model.dig('spec', 'modelName')

              # Get the model's pod
              pod = get_model_pod(model_name)
              pod_name = pod.dig('metadata', 'name')

              # Set up port-forward to access the model pod
              port_forward_pid = nil
              local_port = find_available_port

              begin
                # Start kubectl port-forward in background
                port_forward_pid = start_port_forward(pod_name, local_port, 4000)

                # Wait for port-forward to be ready
                wait_for_port(local_port)

                # Build the JSON payload for the chat completion request
                payload = {
                  model: model_id,
                  messages: [{ role: 'user', content: prompt }],
                  max_tokens: 4000,
                  temperature: 0.3
                }

                # Make HTTP request using Faraday
                conn = Faraday.new(url: "http://localhost:#{local_port}") do |f|
                  f.request :json
                  f.response :json
                  f.adapter Faraday.default_adapter
                  f.options.timeout = 120
                  f.options.open_timeout = 10
                end

                response = conn.post('/v1/chat/completions', payload)

                # Parse response
                result = response.body

                if result['error']
                  error_msg = result['error']['message'] || result['error']
                  raise "Model error: #{error_msg}"
                elsif !result['choices'] || result['choices'].empty?
                  raise "Unexpected response format: #{result.inspect}"
                end

                # Extract the content from the first choice
                result.dig('choices', 0, 'message', 'content')
              rescue Faraday::TimeoutError
                raise 'LLM request timed out after 120 seconds'
              rescue Faraday::ConnectionFailed => e
                raise "Failed to connect to model: #{e.message}"
              rescue StandardError => e
                Formatters::ProgressFormatter.error("LLM call failed: #{e.message}")
                puts
                puts "Make sure the model '#{model_name}' is running: kubectl get pods -n #{ctx.namespace}"
                exit 1
              ensure
                # Clean up port-forward process
                cleanup_port_forward(port_forward_pid) if port_forward_pid
              end
            end

            # Get the pod for a model
            def get_model_pod(model_name)
              # Get the deployment for the model
              deployment = ctx.client.get_resource('Deployment', model_name, ctx.namespace)
              labels = deployment.dig('spec', 'selector', 'matchLabels')

              raise "Deployment '#{model_name}' has no selector labels" if labels.nil?

              # Convert to hash if needed
              labels_hash = labels.respond_to?(:to_h) ? labels.to_h : labels
              raise "Deployment '#{model_name}' has empty selector labels" if labels_hash.empty?

              label_selector = labels_hash.map { |k, v| "#{k}=#{v}" }.join(',')

              # Find a running pod
              pods = ctx.client.list_resources('Pod', namespace: ctx.namespace, label_selector: label_selector)
              raise "No pods found for model '#{model_name}'" if pods.empty?

              running_pod = pods.find do |pod|
                pod.dig('status', 'phase') == 'Running' &&
                  pod.dig('status', 'conditions')&.any? { |c| c['type'] == 'Ready' && c['status'] == 'True' }
              end

              if running_pod.nil?
                pod_phases = pods.map { |p| p.dig('status', 'phase') }.join(', ')
                raise "No running pods found. Pod phases: #{pod_phases}"
              end

              running_pod
            rescue K8s::Error::NotFound
              raise "Model deployment '#{model_name}' not found"
            end

            # Find an available local port for port-forwarding
            def find_available_port
              require 'socket'

              # Try ports in the range 14000-14999
              (14_000..14_999).each do |port|
                server = TCPServer.new('127.0.0.1', port)
                server.close
                return port
              rescue Errno::EADDRINUSE
                # Port in use, try next
                next
              end

              raise 'No available ports found in range 14000-14999'
            end

            # Start kubectl port-forward in background
            def start_port_forward(pod_name, local_port, remote_port)
              require 'English'

              cmd = "kubectl port-forward -n #{ctx.namespace} #{pod_name} #{local_port}:#{remote_port}"
              pid = spawn(cmd, out: '/dev/null', err: '/dev/null')

              # Detach so it runs in background
              Process.detach(pid)

              pid
            end

            # Wait for port-forward to be ready
            def wait_for_port(port, max_attempts: 30)
              require 'socket'

              max_attempts.times do
                socket = TCPSocket.new('127.0.0.1', port)
                socket.close
                return true
              rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
                sleep 0.1
              end

              raise "Port-forward to localhost:#{port} failed to become ready after #{max_attempts} attempts"
            end

            # Clean up port-forward process
            def cleanup_port_forward(pid)
              return unless pid

              begin
                Process.kill('TERM', pid)
                Process.wait(pid, Process::WNOHANG)
              rescue Errno::ESRCH
                # Process already gone
              rescue Errno::ECHILD
                # Process already reaped
              end
            end

            # Extract Ruby code from LLM response
            # Looks for ```ruby ... ``` blocks
            def extract_ruby_code(response)
              # Match ```ruby ... ``` blocks
              match = response.match(/```ruby\n(.*?)```/m)
              return match[1].strip if match

              # Try without language specifier
              match = response.match(/```\n(.*?)```/m)
              return match[1].strip if match

              # If no code blocks, return nil
              nil
            end
          end
        end
      end
    end
  end
end
