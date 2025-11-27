# frozen_string_literal: true

require_relative '../../../../constants/kubernetes_labels'

module LanguageOperator
  module CLI
    module Commands
      module System
        module Helpers
          # Pod management utilities for exec command
          module PodManager
            # Create a ConfigMap with agent code
            def create_agent_configmap(name, code)
              configmap = {
                'apiVersion' => 'v1',
                'kind' => 'ConfigMap',
                'metadata' => {
                  'name' => name,
                  'namespace' => ctx.namespace
                },
                'data' => {
                  'agent.rb' => code
                }
              }

              ctx.client.create_resource(configmap)
            end

            # Create a test pod for running the agent
            def create_test_pod(name, configmap_name, image)
              # Detect available models in the cluster
              model_env = detect_model_config

              if model_env.nil?
                Formatters::ProgressFormatter.warn('Could not detect model configuration from cluster')
                Formatters::ProgressFormatter.warn('Agent may fail without MODEL_ENDPOINTS configured')
              end

              env_vars = [
                { 'name' => 'AGENT_NAME', 'value' => name },
                { 'name' => 'AGENT_MODE', 'value' => 'autonomous' },
                { 'name' => 'AGENT_CODE_PATH', 'value' => '/etc/agent/code/agent.rb' },
                { 'name' => 'CONFIG_PATH', 'value' => '/nonexistent/config.yaml' }
              ]

              # Add model configuration if available
              env_vars += model_env if model_env

              pod = {
                'apiVersion' => 'v1',
                'kind' => 'Pod',
                'metadata' => {
                  'name' => name,
                  'namespace' => ctx.namespace,
                  'labels' => Constants::KubernetesLabels.test_agent_labels(name).merge(
                    Constants::KubernetesLabels::KIND_LABEL => 'LanguageAgent'
                  )
                },
                'spec' => {
                  'restartPolicy' => 'Never',
                  'containers' => [
                    {
                      'name' => 'agent',
                      'image' => image,
                      'imagePullPolicy' => 'Always',
                      'env' => env_vars,
                      'volumeMounts' => [
                        {
                          'name' => 'agent-code',
                          'mountPath' => '/etc/agent/code',
                          'readOnly' => true
                        }
                      ]
                    }
                  ],
                  'volumes' => [
                    {
                      'name' => 'agent-code',
                      'configMap' => {
                        'name' => configmap_name
                      }
                    }
                  ]
                }
              }

              ctx.client.create_resource(pod)
            end

            # Detect model configuration from the cluster
            def detect_model_config
              models = ctx.client.list_resources('LanguageModel', namespace: ctx.namespace)
              return nil if models.empty?

              # Use first available model
              model = models.first
              model_name = model.dig('metadata', 'name')
              model_id = model.dig('spec', 'modelName')

              # Build endpoint URL (port 8000 is the model service port)
              endpoint = "http://#{model_name}.#{ctx.namespace}.svc.cluster.local:8000"

              [
                { 'name' => 'MODEL_ENDPOINTS', 'value' => endpoint },
                { 'name' => 'LLM_MODEL', 'value' => model_id },
                { 'name' => 'OPENAI_API_KEY', 'value' => 'sk-dummy-key-for-local-proxy' }
              ]
            rescue StandardError => e
              Formatters::ProgressFormatter.error("Failed to detect model configuration: #{e.message}")
              nil
            end

            # Wait for pod to start (running or terminated)
            def wait_for_pod_start(name, timeout: 60)
              start_time = Time.now
              loop do
                pod = ctx.client.get_resource('Pod', name, ctx.namespace)
                phase = pod.dig('status', 'phase')

                return if %w[Running Succeeded Failed].include?(phase)

                raise "Pod #{name} did not start within #{timeout} seconds" if Time.now - start_time > timeout

                sleep 1
              end
            end

            # Stream pod logs until completion
            def stream_pod_logs(name, timeout: 300)
              require 'open3'

              cmd = "kubectl logs -f -n #{ctx.namespace} #{name} 2>&1"
              Open3.popen3(cmd) do |_stdin, stdout, _stderr, wait_thr|
                # Set up timeout
                start_time = Time.now

                # Stream logs
                stdout.each_line do |line|
                  puts line

                  # Check timeout
                  if Time.now - start_time > timeout
                    Process.kill('TERM', wait_thr.pid)
                    raise "Log streaming timed out after #{timeout} seconds"
                  end
                end

                # Wait for process to complete
                wait_thr.value
              end
            rescue Errno::EPIPE
              # Pod terminated, logs finished
            end

            # Wait for pod to terminate and get exit code
            def wait_for_pod_termination(name, timeout: 10)
              # Give the pod a moment to fully transition after logs complete
              sleep 2

              start_time = Time.now
              loop do
                pod = ctx.client.get_resource('Pod', name, ctx.namespace)
                phase = pod.dig('status', 'phase')
                container_status = pod.dig('status', 'containerStatuses', 0)

                # Pod completed successfully or failed
                if %w[Succeeded Failed].include?(phase) && container_status && (terminated = container_status.dig('state', 'terminated'))
                  return terminated['exitCode']
                end

                # Check timeout
                if Time.now - start_time > timeout
                  # Try one last time
                  if container_status && (terminated = container_status.dig('state', 'terminated'))
                    return terminated['exitCode']
                  end

                  return nil
                end

                sleep 0.5
              rescue K8s::Error::NotFound
                # Pod was deleted before we could get status
                return nil
              end
            end

            # Get pod status
            def get_pod_status(name)
              pod = ctx.client.get_resource('Pod', name, ctx.namespace)
              pod.to_h.fetch('status', {})
            end

            # Delete a pod
            def delete_pod(name)
              ctx.client.delete_resource('Pod', name, ctx.namespace)
            rescue K8s::Error::NotFound
              # Already deleted
            end

            # Delete a ConfigMap
            def delete_configmap(name)
              ctx.client.delete_resource('ConfigMap', name, ctx.namespace)
            rescue K8s::Error::NotFound
              # Already deleted
            end
          end
        end
      end
    end
  end
end
