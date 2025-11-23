# frozen_string_literal: true

require 'socket'
require 'faraday'
require 'json'

module LanguageOperator
  module CLI
    module Commands
      module Agent
        module Helpers
          # LLM client that uses port-forwarding to cluster model deployments (LiteLLM proxy)
          class ClusterLLMClient
            def initialize(ctx:, model_name:, model_id:, agent_command:)
              @ctx = ctx
              @model_name = model_name
              @model_id = model_id
              @agent_command = agent_command
            end

            def chat(prompt)
              pod = get_model_pod
              pod_name = pod.dig('metadata', 'name')

              local_port = find_available_port
              port_forward_pid = nil

              begin
                port_forward_pid = start_port_forward(pod_name, local_port, 4000)
                wait_for_port(local_port)

                conn = Faraday.new(url: "http://localhost:#{local_port}") do |f|
                  f.request :json
                  f.response :json
                  f.adapter Faraday.default_adapter
                  f.options.timeout = 120
                  f.options.open_timeout = 10
                end

                payload = {
                  model: @model_id,
                  messages: [{ role: 'user', content: prompt }],
                  max_tokens: 4000,
                  temperature: 0.3
                }

                response = conn.post('/v1/chat/completions', payload)
                result = response.body

                raise "LLM error: #{result['error']['message'] || result['error']}" if result['error']

                result.dig('choices', 0, 'message', 'content')
              ensure
                cleanup_port_forward(port_forward_pid) if port_forward_pid
              end
            end

            private

            def get_model_pod
              # Get the deployment for the model
              deployment = @ctx.client.get_resource('Deployment', @model_name, @ctx.namespace)
              raise "Deployment '#{@model_name}' not found in namespace '#{@ctx.namespace}'" if deployment.nil?

              labels = deployment.dig('spec', 'selector', 'matchLabels')
              raise "Deployment '#{@model_name}' has no selector labels" if labels.nil?

              # Convert to hash if needed (K8s API may return K8s::Resource)
              labels_hash = labels.respond_to?(:to_h) ? labels.to_h : labels
              raise "Deployment '#{@model_name}' has empty selector labels" if labels_hash.empty?

              label_selector = labels_hash.map { |k, v| "#{k}=#{v}" }.join(',')

              # Find a running pod
              pods = @ctx.client.list_resources('Pod', namespace: @ctx.namespace, label_selector: label_selector)
              raise "No pods found for model '#{@model_name}'" if pods.empty?

              running_pods = pods.select { |p| p.dig('status', 'phase') == 'Running' }
              raise "No running pods found for model '#{@model_name}'" if running_pods.empty?

              running_pods.first
            end

            def find_available_port
              server = TCPServer.new('127.0.0.1', 0)
              port = server.addr[1]
              server.close
              port
            end

            def start_port_forward(pod_name, local_port, remote_port)
              pid = spawn(
                'kubectl', 'port-forward',
                '-n', @ctx.namespace,
                "pod/#{pod_name}",
                "#{local_port}:#{remote_port}",
                %i[out err] => '/dev/null'
              )
              Process.detach(pid)
              pid
            end

            def wait_for_port(port, max_attempts: 30)
              max_attempts.times do
                TCPSocket.new('127.0.0.1', port).close
                return true
              rescue Errno::ECONNREFUSED
                sleep 0.1
              end
              raise "Port #{port} not available after #{max_attempts} attempts"
            end

            def cleanup_port_forward(pid)
              Process.kill('TERM', pid)
            rescue Errno::ESRCH
              # Process already gone
            end
          end
        end
      end
    end
  end
end
