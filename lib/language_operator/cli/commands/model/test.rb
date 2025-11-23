# frozen_string_literal: true

require 'json'
require 'English'
require 'shellwords'

module LanguageOperator
  module CLI
    module Commands
      module Model
        module Test
          def self.included(base)
            base.class_eval do
              desc 'test NAME', 'Test model connectivity and functionality'
              long_desc <<-DESC
                Test that a model is operational by:
                1. Verifying the pod is running
                2. Testing the chat completion endpoint with a simple message

                This command helps diagnose model deployment issues.
              DESC
              option :cluster, type: :string, desc: 'Override current cluster context'
              option :timeout, type: :numeric, default: 30, desc: 'Timeout in seconds for endpoint test'
              def test(name)
                handle_command_error('test model') do
                  # 1. Get model resource
                  model = get_resource_or_exit('LanguageModel', name)
                  model_name = model.dig('spec', 'modelName')
                  model.dig('spec', 'provider')

                  # 2. Check deployment status
                  deployment = check_deployment_status(name)

                  # 3. Check pod status
                  pod = check_pod_status(name, deployment)

                  # 4. Test chat completion endpoint
                  test_chat_completion(name, model_name, pod, options[:timeout])
                end
              end

              private

              def check_deployment_status(name)
                Formatters::ProgressFormatter.with_spinner('Verifying deployment') do
                  deployment = ctx.client.get_resource('Deployment', name, ctx.namespace)
                  replicas = deployment.dig('spec', 'replicas') || 1
                  ready_replicas = deployment.dig('status', 'readyReplicas') || 0

                  unless ready_replicas >= replicas
                    raise "Deployment not ready (#{ready_replicas}/#{replicas}). " \
                          "Run 'kubectl get deployment #{name} -n #{ctx.namespace}' for details."
                  end

                  deployment
                end
              rescue K8s::Error::NotFound
                Formatters::ProgressFormatter.error("Deployment '#{name}' not found")
                exit 1
              end

              def check_pod_status(name, deployment)
                Formatters::ProgressFormatter.with_spinner('Verifying pod') do
                  labels = deployment.dig('spec', 'selector', 'matchLabels')
                  raise "Deployment '#{name}' has no selector labels" if labels.nil?

                  # Convert K8s::Resource to hash if needed
                  labels_hash = labels.respond_to?(:to_h) ? labels.to_h : labels
                  raise "Deployment '#{name}' has empty selector labels" if labels_hash.empty?

                  label_selector = labels_hash.map { |k, v| "#{k}=#{v}" }.join(',')

                  pods = ctx.client.list_resources('Pod', namespace: ctx.namespace, label_selector: label_selector)
                  raise "No pods found for model '#{name}'" if pods.empty?

                  # Find a running pod
                  running_pod = pods.find do |pod|
                    pod.dig('status', 'phase') == 'Running' &&
                      pod.dig('status', 'conditions')&.any? { |c| c['type'] == 'Ready' && c['status'] == 'True' }
                  end

                  if running_pod.nil?
                    pod_phases = pods.map { |p| p.dig('status', 'phase') }.join(', ')
                    raise "No running pods found. Pod phases: #{pod_phases}. " \
                          "Run 'kubectl get pods -l #{label_selector} -n #{ctx.namespace}' for details."
                  end

                  running_pod
                end
              end

              def test_chat_completion(_name, model_name, pod, timeout)
                Formatters::ProgressFormatter.with_spinner('Verifying chat completion requests') do
                  pod_name = pod.dig('metadata', 'name')

                  # Build the JSON payload
                  payload = JSON.generate({
                                            model: model_name,
                                            messages: [{ role: 'user', content: 'hello' }],
                                            max_tokens: 10
                                          })

                  # Build the curl command using echo to pipe JSON
                  # This avoids shell escaping issues with -d flag
                  curl_command = "echo '#{payload}' | curl -s -X POST http://localhost:4000/v1/chat/completions " \
                                 "-H 'Content-Type: application/json' -d @- --max-time #{timeout}"

                  # Execute the curl command inside the pod
                  result = execute_in_pod(pod_name, curl_command)

                  # Parse the response
                  response = JSON.parse(result)

                  if response['error']
                    error_msg = response['error']['message'] || response['error']
                    raise error_msg
                  elsif !response['choices']
                    raise "Unexpected response format: #{result.lines.first.strip}"
                  end

                  response
                rescue JSON::ParserError => e
                  raise "Failed to parse response: #{e.message}"
                end
              rescue StandardError => e
                # Display error in bold red
                puts
                puts Formatters::ProgressFormatter.pastel.bold.red(e.message)
                exit 1
              end

              def execute_in_pod(pod_name, command)
                # Use kubectl exec to run command in pod
                # command can be a string or array
                kubectl_command = if command.is_a?(String)
                                    "kubectl exec -n #{ctx.namespace} #{pod_name} -- sh -c #{Shellwords.escape(command)}"
                                  else
                                    (['kubectl', 'exec', '-n', ctx.namespace, pod_name, '--'] + command).join(' ')
                                  end

                output = `#{kubectl_command} 2>&1`
                exit_code = $CHILD_STATUS.exitstatus

                if exit_code != 0
                  Formatters::ProgressFormatter.error("Failed to execute command in pod: #{output}")
                  exit 1
                end

                output
              end
            end
          end
        end
      end
    end
  end
end
