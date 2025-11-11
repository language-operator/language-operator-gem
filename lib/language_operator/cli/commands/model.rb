# frozen_string_literal: true

require 'thor'
require 'yaml'
require_relative '../formatters/progress_formatter'
require_relative '../formatters/table_formatter'
require_relative '../helpers/cluster_validator'
require_relative '../helpers/cluster_context'
require_relative '../helpers/user_prompts'
require_relative '../helpers/resource_dependency_checker'
require_relative '../helpers/editor_helper'
require_relative '../../config/cluster_config'
require_relative '../../kubernetes/client'
require_relative '../../kubernetes/resource_builder'

module LanguageOperator
  module CLI
    module Commands
      # Model management commands
      class Model < Thor
        include Helpers::ClusterValidator

        desc 'list', 'List all models in current cluster'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def list
          ctx = Helpers::ClusterContext.from_options(options)

          models = ctx.client.list_resources('LanguageModel', namespace: ctx.namespace)

          if models.empty?
            Formatters::ProgressFormatter.info("No models found in cluster '#{ctx.name}'")
            puts
            puts 'Models define LLM configurations for agents.'
            puts
            puts 'Create a model with:'
            puts '  aictl model create <name> --provider <provider> --model <model>'
            return
          end

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
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to list models: #{e.message}")
          raise if ENV['DEBUG']

          exit 1
        end

        desc 'create NAME', 'Create a new model'
        long_desc <<-DESC
          Create a new LanguageModel resource in the cluster.

          Examples:
            aictl model create gpt4 --provider openai --model gpt-4-turbo
            aictl model create claude --provider anthropic --model claude-3-opus-20240229
            aictl model create local --provider openai_compatible --model llama-3 --endpoint http://localhost:8080
        DESC
        option :provider, type: :string, required: true, desc: 'LLM provider (e.g., openai, anthropic, openai_compatible)'
        option :model, type: :string, required: true, desc: 'Model identifier (e.g., gpt-4, claude-3-opus)'
        option :endpoint, type: :string, desc: 'Custom endpoint URL (for openai_compatible or self-hosted)'
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :dry_run, type: :boolean, default: false, desc: 'Output the manifest without creating'
        def create(name)
          ctx = Helpers::ClusterContext.from_options(options)

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
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to create model: #{e.message}")
          raise if ENV['DEBUG']

          exit 1
        end

        desc 'inspect NAME', 'Show detailed model information'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def inspect(name)
          ctx = Helpers::ClusterContext.from_options(options)

          # Get model
          begin
            model = ctx.client.get_resource('LanguageModel', name, ctx.namespace)
          rescue K8s::Error::NotFound
            Formatters::ProgressFormatter.error("Model '#{name}' not found in cluster '#{ctx.name}'")
            exit 1
          end

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
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to inspect model: #{e.message}")
          raise if ENV['DEBUG']

          exit 1
        end

        desc 'delete NAME', 'Delete a model'
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :force, type: :boolean, default: false, desc: 'Skip confirmation'
        def delete(name)
          ctx = Helpers::ClusterContext.from_options(options)

          # Get model
          begin
            model = ctx.client.get_resource('LanguageModel', name, ctx.namespace)
          rescue K8s::Error::NotFound
            Formatters::ProgressFormatter.error("Model '#{name}' not found in cluster '#{ctx.name}'")
            exit 1
          end

          # Check for agents using this model
          agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)
          agents_using = Helpers::ResourceDependencyChecker.agents_using_model(agents, name)

          if agents_using.any? && !options[:force]
            Formatters::ProgressFormatter.warn("Model '#{name}' is in use by #{agents_using.count} agent(s)")
            puts
            puts 'Agents using this model:'
            agents_using.each do |agent|
              puts "  - #{agent.dig('metadata', 'name')}"
            end
            puts
            puts 'Delete these agents first, or use --force to delete anyway.'
            puts
            return unless Helpers::UserPrompts.confirm('Are you sure?')
          end

          # Confirm deletion unless --force
          unless options[:force] || agents_using.any?
            puts "This will delete model '#{name}' from cluster '#{ctx.name}':"
            puts "  Provider: #{model.dig('spec', 'provider')}"
            puts "  Model:    #{model.dig('spec', 'modelName')}"
            puts "  Status:   #{model.dig('status', 'phase')}"
            puts
            return unless Helpers::UserPrompts.confirm('Are you sure?')
          end

          # Delete model
          Formatters::ProgressFormatter.with_spinner("Deleting model '#{name}'") do
            ctx.client.delete_resource('LanguageModel', name, ctx.namespace)
          end

          Formatters::ProgressFormatter.success("Model '#{name}' deleted successfully")
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to delete model: #{e.message}")
          raise if ENV['DEBUG']

          exit 1
        end

        desc 'edit NAME', 'Edit model configuration'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def edit(name)
          ctx = Helpers::ClusterContext.from_options(options)

          # Get current model
          begin
            model = ctx.client.get_resource('LanguageModel', name, ctx.namespace)
          rescue K8s::Error::NotFound
            Formatters::ProgressFormatter.error("Model '#{name}' not found in cluster '#{ctx.name}'")
            exit 1
          end

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
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to edit model: #{e.message}")
          raise if ENV['DEBUG']

          exit 1
        end
      end
    end
  end
end
