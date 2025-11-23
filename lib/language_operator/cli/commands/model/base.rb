# frozen_string_literal: true

require 'yaml'
require_relative '../../base_command'
require_relative '../../formatters/progress_formatter'
require_relative '../../formatters/table_formatter'
require_relative '../../helpers/cluster_validator'
require_relative '../../helpers/user_prompts'
require_relative '../../helpers/resource_dependency_checker'
require_relative '../../helpers/editor_helper'
require_relative '../../../config/cluster_config'
require_relative '../../../kubernetes/client'
require_relative '../../../kubernetes/resource_builder'
require_relative '../../wizards/model_wizard'
require_relative 'test'

module LanguageOperator
  module CLI
    module Commands
      module Model
        # Model management commands
        class Base < BaseCommand
          include Helpers::ClusterValidator
          include Test

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
                wizard = Wizards::ModelWizard.new(ctx)
                wizard.run
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

              puts
              highlighted_box(
                title: 'LanguageModel',
                rows: {
                  'Name' => pastel.white.bold(name),
                  'Namespace' => ctx.namespace,
                  'Cluster' => ctx.name,
                  'Status' => model.dig('status', 'phase') || 'Unknown',
                  'Provider' => model.dig('spec', 'provider'),
                  'Model' => model.dig('spec', 'modelName'),
                  'Endpoint' => model.dig('spec', 'endpoint')
                }
              )
              puts

              # Get agents using this model
              agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)
              agents_using = Helpers::ResourceDependencyChecker.agents_using_model(agents, name)
              agent_names = agents_using.map { |agent| agent.dig('metadata', 'name') }

              list_box(
                title: 'Agents using this model',
                items: agent_names,
                empty_message: 'No agents using this model'
              )

              puts
              labels = model.dig('metadata', 'labels') || {}
              list_box(
                title: 'Labels',
                items: labels,
                style: :key_value
              )
            end
          end

          desc 'delete NAME', 'Delete a model'
          option :cluster, type: :string, desc: 'Override current cluster context'
          option :force, type: :boolean, default: false, desc: 'Skip confirmation'
          def delete(name)
            handle_command_error('delete model') do
              get_resource_or_exit('LanguageModel', name)

              # Check dependencies and get confirmation
              return unless check_dependencies_and_confirm('model', name, force: options[:force])

              # Confirm deletion unless --force
              return unless confirm_deletion_with_force('model', name, ctx.name, force: options[:force])

              # Delete model
              Formatters::ProgressFormatter.with_spinner("Deleting model '#{name}'") do
                ctx.client.delete_resource('LanguageModel', name, ctx.namespace)
              end

              Formatters::ProgressFormatter.success("Model '#{name}' deleted successfully")
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
        end
      end
    end
  end
end
