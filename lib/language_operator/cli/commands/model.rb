# frozen_string_literal: true

require 'yaml'
require 'json'
require 'English'
require 'shellwords'
require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../formatters/table_formatter'
require_relative '../helpers/cluster_validator'
require_relative '../helpers/user_prompts'
require_relative '../helpers/resource_dependency_checker'
require_relative '../helpers/editor_helper'
require_relative '../../config/cluster_config'
require_relative '../../kubernetes/client'
require_relative '../../kubernetes/resource_builder'
require_relative '../../ux/create_model'

module LanguageOperator
  module CLI
    module Commands
      # Model management commands
      class Model < BaseCommand
        include Helpers::ClusterValidator

        desc 'list', 'List all models in current cluster'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def list
          handle_command_error('list models') do
            models = list_resources_or_empty('LanguageModel') do
              puts
              puts 'Models define LLM configurations for agents.'
              puts
              puts 'Create a model with:'
              puts '  aictl model create <name> --provider <provider> --model <model>'
            end

            return if models.empty?

            table_data = models.map do |model|
              name = model.dig('metadata', 'name')
              provider = model.dig('spec', 'provider') || 'unknown'
              model_name = model.dig('spec', 'modelName') || 'unknown'
              status = model.dig('status', 'phase') || 'Unknown'

              {
                name: name,
                provider: provider,
                model: model_name,
                status: status
              }
            end

            Formatters::TableFormatter.models(table_data)
          end
        end

        desc 'create [NAME]', 'Create a new model'
        long_desc <<-DESC
          Create a new LanguageModel resource in the cluster.

          If NAME is omitted and no options are provided, an interactive wizard will guide you.

          Examples:
            aictl model create                  # Launch interactive wizard
            aictl model create gpt4 --provider openai --model gpt-4-turbo
            aictl model create claude --provider anthropic --model claude-3-opus-20240229
            aictl model create local --provider openai_compatible --model llama-3 --endpoint http://localhost:8080
        DESC
        option :provider, type: :string, required: false, desc: 'LLM provider (e.g., openai, anthropic, openai_compatible)'
        option :model, type: :string, required: false, desc: 'Model identifier (e.g., gpt-4, claude-3-opus)'
        option :endpoint, type: :string, desc: 'Custom endpoint URL (for openai_compatible or self-hosted)'
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :dry_run, type: :boolean, default: false, desc: 'Output the manifest without creating'
        def create(name = nil)
          handle_command_error('create model') do
            # Launch interactive wizard if no arguments provided
            if name.nil? && options[:provider].nil? && options[:model].nil?
              Ux::CreateModel.execute(ctx)
              return
            end

            # Validate required options for non-interactive mode
            if options[:provider].nil? || options[:model].nil?
              Formatters::ProgressFormatter.error(
                'Must provide both --provider and --model, or use interactive mode (run without arguments)'
              )
              exit 1
            end

            # Build LanguageModel resource
            resource = Kubernetes::ResourceBuilder.language_model(
              name,
              provider: options[:provider],
              model: options[:model],
              endpoint: options[:endpoint],
              cluster: ctx.namespace
            )

            # Handle dry-run: output manifest and exit
            if options[:dry_run]
              puts resource.to_yaml
              return
            end

            # Check if model already exists
            begin
              ctx.client.get_resource('LanguageModel', name, ctx.namespace)
              Formatters::ProgressFormatter.error("Model '#{name}' already exists in cluster '#{ctx.name}'")
              exit 1
            rescue K8s::Error::NotFound
              # Model doesn't exist, proceed with creation
            end

            # Create model
            Formatters::ProgressFormatter.with_spinner("Creating model '#{name}'") do
              ctx.client.apply_resource(resource)
            end

            Formatters::ProgressFormatter.success("Model '#{name}' created successfully")
            puts
            puts 'Model Details:'
            puts "  Name:     #{name}"
            puts "  Provider: #{options[:provider]}"
            puts "  Model:    #{options[:model]}"
            puts "  Endpoint: #{options[:endpoint]}" if options[:endpoint]
            puts "  Cluster:  #{ctx.name}"
          end
        end

        desc 'inspect NAME', 'Show detailed model information'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def inspect(name)
          handle_command_error('inspect model') do
            model = get_resource_or_exit('LanguageModel', name)

            puts "Model: #{name}"
            puts "  Cluster:   #{ctx.name}"
            puts "  Namespace: #{ctx.namespace}"
            puts "  Provider:  #{model.dig('spec', 'provider')}"
            puts "  Model:     #{model.dig('spec', 'modelName')}"
            puts "  Endpoint:  #{model.dig('spec', 'endpoint')}" if model.dig('spec', 'endpoint')
            puts "  Status:    #{model.dig('status', 'phase') || 'Unknown'}"
            puts

            # Get agents using this model
            agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)
            agents_using = Helpers::ResourceDependencyChecker.agents_using_model(agents, name)

            if agents_using.any?
              puts "Agents using this model (#{agents_using.count}):"
              agents_using.each do |agent|
                puts "  - #{agent.dig('metadata', 'name')}"
              end
            else
              puts 'No agents using this model'
            end

            puts
            puts 'Labels:'
            labels = model.dig('metadata', 'labels') || {}
            if labels.empty?
              puts '  (none)'
            else
              labels.each do |key, value|
                puts "  #{key}: #{value}"
              end
            end
          end
        end

        desc 'delete NAME', 'Delete a model'
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :force, type: :boolean, default: false, desc: 'Skip confirmation'
        def delete(name)
          handle_command_error('delete model') do
            model = get_resource_or_exit('LanguageModel', name)

            # Check dependencies and get confirmation
            return unless check_dependencies_and_confirm('model', name, force: options[:force])

            # Confirm deletion unless --force
            if confirm_deletion(
              'model', name, ctx.name,
              details: {
                'Provider' => model.dig('spec', 'provider'),
                'Model' => model.dig('spec', 'modelName'),
                'Status' => model.dig('status', 'phase')
              },
              force: options[:force]
            )
              # Delete model
              Formatters::ProgressFormatter.with_spinner("Deleting model '#{name}'") do
                ctx.client.delete_resource('LanguageModel', name, ctx.namespace)
              end

              Formatters::ProgressFormatter.success("Model '#{name}' deleted successfully")
            end
          end
        end

        desc 'edit NAME', 'Edit model configuration'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def edit(name)
          handle_command_error('edit model') do
            model = get_resource_or_exit('LanguageModel', name)

            # Edit model YAML in user's editor
            edited_yaml = Helpers::EditorHelper.edit_content(
              model.to_yaml,
              'model-',
              '.yaml',
              default_editor: 'vim'
            )
            edited_model = YAML.safe_load(edited_yaml)

            # Apply changes
            Formatters::ProgressFormatter.with_spinner("Updating model '#{name}'") do
              ctx.client.apply_resource(edited_model)
            end

            Formatters::ProgressFormatter.success("Model '#{name}' updated successfully")
          end
        end

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
