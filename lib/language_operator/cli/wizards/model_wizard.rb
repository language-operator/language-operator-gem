# frozen_string_literal: true

require_relative '../helpers/ux_helper'
require_relative '../helpers/validation_helper'
require_relative '../helpers/provider_helper'
require_relative '../formatters/progress_formatter'
require_relative '../../kubernetes/client'
require_relative '../../kubernetes/resource_builder'

module LanguageOperator
  module CLI
    module Wizards
      # Interactive wizard for creating language models
      #
      # Guides users through provider selection, credential input,
      # model selection, and resource creation.
      #
      # @example
      #   wizard = Wizards::ModelWizard.new(ctx)
      #   wizard.run
      class ModelWizard
        include Helpers::UxHelper
        include Helpers::ValidationHelper
        include Helpers::ProviderHelper

        attr_reader :ctx

        def initialize(ctx)
          @ctx = ctx
        end

        # Run the wizard and create the model
        #
        # @return [Boolean] true if model was created successfully
        def run
          show_welcome

          # Step 1: Provider selection
          provider_info = select_provider
          return false unless provider_info

          # Step 2: Get credentials
          credentials = get_credentials(provider_info)
          return false unless credentials

          # Step 3: Test connection
          test_result = test_connection(provider_info, credentials)
          return false unless test_result[:success]

          # Step 4: Select model
          model_id = select_model(provider_info, credentials)
          return false unless model_id

          # Step 5: Get display name
          model_name = get_model_name(model_id)
          return false unless model_name

          # Create resources
          success = create_model_resource(model_name, provider_info, credentials, model_id)
          return false unless success

          # Show success
          show_success(model_name, model_id, provider_info)

          true
        end

        private

        def show_welcome
          logo(title: "add a model to cluster '#{ctx.name}'")
        end

        def select_provider
          provider = prompt.select('Select a provider:') do |menu|
            menu.choice 'Anthropic', :anthropic
            menu.choice 'OpenAI', :openai
            menu.choice 'Other (OpenAI-compatible)', :openai_compatible
          end

          case provider
          when :anthropic
            { provider: :anthropic, provider_key: 'anthropic', display_name: 'Anthropic' }
          when :openai
            { provider: :openai, provider_key: 'openai', display_name: 'OpenAI' }
          when :openai_compatible
            endpoint = ask_url('API endpoint URL (e.g., http://localhost:11434):')
            return nil unless endpoint

            { provider: :openai_compatible, provider_key: 'openai-compatible',
              display_name: 'OpenAI-Compatible', endpoint: endpoint }
          end
        rescue TTY::Reader::InputInterrupt
          Formatters::ProgressFormatter.error('Cancelled')
          nil
        end

        def get_credentials(provider_info)
          case provider_info[:provider]
          when :anthropic
            show_credential_help('Anthropic', 'https://console.anthropic.com')
            api_key = ask_secret('Enter your Anthropic API key:')
            return nil unless api_key

            { api_key: api_key }
          when :openai
            show_credential_help('OpenAI', 'https://platform.openai.com/api-keys')
            api_key = ask_secret('Enter your OpenAI API key:')
            return nil unless api_key

            { api_key: api_key }
          when :openai_compatible
            needs_auth = ask_yes_no('Does this endpoint require authentication?', default: false)
            return nil if needs_auth.nil?

            api_key = needs_auth ? ask_secret('Enter API key:') : nil
            { api_key: api_key, endpoint: provider_info[:endpoint] }
          end
        end

        def show_credential_help(_provider_name, url)
          puts "If you need to, get your API key at #{pastel.cyan(url)}."
          puts
        end

        def test_connection(provider_info, credentials)
          puts
          test_result = Formatters::ProgressFormatter.with_spinner('Testing connection') do
            test_provider_connection(
              provider_info[:provider],
              api_key: credentials[:api_key],
              endpoint: provider_info[:endpoint]
            )
          end

          unless test_result[:success]
            Formatters::ProgressFormatter.error("Connection failed: #{test_result[:error]}")
            puts
            retry_choice = ask_yes_no('Try again with different credentials?', default: false)
            if retry_choice
              new_credentials = get_credentials(provider_info)
              return { success: false } unless new_credentials

              return test_connection(provider_info, new_credentials)
            end
            return { success: false }
          end

          puts
          { success: true }
        end

        def select_model(provider_info, credentials)
          available_models = fetch_provider_models(
            provider_info[:provider],
            api_key: credentials[:api_key],
            endpoint: provider_info[:endpoint]
          )

          if available_models.nil? || available_models.empty?
            Formatters::ProgressFormatter.warn('Could not fetch available models')
            puts
            model_id = prompt.ask('Enter model identifier manually:') do |q|
              q.required true
            end
            return model_id
          end

          ask_select('Select a model:', available_models, per_page: 10)
        rescue TTY::Reader::InputInterrupt
          Formatters::ProgressFormatter.error('Cancelled')
          nil
        end

        def get_model_name(model_id)
          # Generate smart default from model_id
          # Examples: "gpt-4-turbo" -> "gpt-4-turbo", "claude-3-opus-20240229" -> "claude-3-opus-20240229"
          #           "mistralai/magistral-small-2509" -> "magistral-small-2509"
          default_name = model_id.split('/').last.downcase.gsub(/[^0-9a-z]/i, '-').gsub(/-+/, '-')
          default_name = default_name[0..62] if default_name.length > 63 # K8s limit is 63 chars

          ask_k8s_name('Your name for this model:', default: default_name)
        rescue TTY::Reader::InputInterrupt
          Formatters::ProgressFormatter.error('Cancelled')
          nil
        end

        def create_model_resource(model_name, provider_info, credentials, model_id)
          # Check if model already exists
          begin
            ctx.client.get_resource('LanguageModel', model_name, ctx.namespace)
            Formatters::ProgressFormatter.error("Model '#{model_name}' already exists in cluster '#{ctx.name}'")
            puts
            puts "Use 'langop model inspect #{model_name}' to view details"
            puts "Use 'langop model edit #{model_name}' to modify it"
            return false
          rescue K8s::Error::NotFound
            # Expected - model doesn't exist yet
          end

          puts
          Formatters::ProgressFormatter.with_spinner("Creating model '#{model_name}'") do
            # Create API key secret if provided
            if credentials[:api_key]
              secret_name = "#{model_name}-api-key"
              secret = {
                'apiVersion' => 'v1',
                'kind' => 'Secret',
                'metadata' => {
                  'name' => secret_name,
                  'namespace' => ctx.namespace
                },
                'type' => 'Opaque',
                'stringData' => {
                  'api-key' => credentials[:api_key]
                }
              }
              ctx.client.apply_resource(secret)
            end

            # Create LanguageModel resource
            resource = Kubernetes::ResourceBuilder.language_model(
              model_name,
              provider: provider_info[:provider_key],
              model: model_id,
              endpoint: provider_info[:endpoint],
              cluster: ctx.namespace
            )

            # Add API key reference if secret was created
            if credentials[:api_key]
              resource['spec']['apiKeySecret'] = {
                'name' => "#{model_name}-api-key",
                'key' => 'api-key'
              }
            end

            ctx.client.apply_resource(resource)
          end

          true
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to create model: #{e.message}")
          false
        end

        def show_success(model_name, model_id, provider_info)
          puts
          highlighted_box(
            title: 'LanguageModel Details',
            rows: {
              'Name' => model_name,
              'Provider' => provider_info[:display_name],
              'Model' => model_id,
              'Endpoint' => provider_info[:endpoint],
              'Cluster' => ctx.name
            }
          )
          puts
          puts 'Next steps:'
          puts
          puts '1. Use this model in an agent:'
          puts "   #{pastel.dim("langop agent create --model #{model_name}")}"
          puts '2. View model details:'
          puts "   #{pastel.dim("langop model inspect #{model_name}")}"
          puts
        end
      end
    end
  end
end
