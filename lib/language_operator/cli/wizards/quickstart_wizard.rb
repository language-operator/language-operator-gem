# frozen_string_literal: true

require 'tty-prompt'
require 'pastel'
require 'k8s-ruby'
require_relative '../formatters/progress_formatter'
require_relative '../../config/cluster_config'
require_relative '../../kubernetes/client'
require_relative '../../kubernetes/resource_builder'

module LanguageOperator
  module CLI
    module Wizards
      # Interactive quickstart wizard for first-time setup
      class QuickstartWizard
        def initialize
          @prompt = TTY::Prompt.new
          @pastel = Pastel.new
        end

        def run
          show_welcome

          # Step 1: Cluster setup
          cluster_info = setup_cluster
          return unless cluster_info

          # Step 2: Model configuration
          model_info = configure_model(cluster_info)
          return unless model_info

          # Step 3: Example agent
          create_example_agent(cluster_info, model_info)

          # Show next steps
          show_next_steps
        end

        private

        attr_reader :prompt, :pastel

        def show_welcome
          puts
          puts pastel.cyan('╭────────────────────────────────────────────────╮')
          puts "#{pastel.cyan('│')}  Welcome to Language Operator! 🎉              #{pastel.cyan('│')}"
          puts "#{pastel.cyan('│')}  Let's get you set up (takes ~5 minutes)       #{pastel.cyan('│')}"
          puts pastel.cyan('╰────────────────────────────────────────────────╯')
          puts
          puts 'This wizard will help you:'
          puts '  1. Connect to your Kubernetes cluster'
          puts '  2. Configure a language model'
          puts '  3. Create your first autonomous agent'
          puts
          puts pastel.dim('Press Enter to begin...')
          $stdin.gets
        end

        def setup_cluster
          puts
          puts '─' * 50
          puts pastel.cyan('Step 1/3: Connect to Kubernetes')
          puts '─' * 50
          puts

          # Check if user has kubectl configured
          has_kubectl = prompt.yes?('Do you have kubectl configured?')

          unless has_kubectl
            show_kubernetes_setup_guide
            return nil
          end

          # Get available contexts
          contexts = get_kubectl_contexts

          if contexts.empty?
            Formatters::ProgressFormatter.error('No kubectl contexts found')
            puts
            puts 'Configure kubectl first, then run quickstart again.'
            return nil
          end

          puts
          puts 'Great! I found these contexts in your kubeconfig:'
          puts

          # Let user select context
          context = prompt.select('Which context should we use?', contexts)

          # Generate cluster name
          cluster_name = prompt.ask('Name for this cluster:', default: 'my-cluster') do |q|
            q.required true
            q.validate(/^[a-z0-9-]+$/, 'Name must be lowercase alphanumeric with hyphens')
          end

          # Create cluster configuration
          create_cluster_config(cluster_name, context)
        end

        def get_kubectl_contexts
          kubeconfig_path = ENV.fetch('KUBECONFIG', File.expand_path('~/.kube/config'))

          return [] unless File.exist?(kubeconfig_path)

          config = K8s::Config.load_file(kubeconfig_path)
          config.contexts.map(&:name)
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to load kubeconfig: #{e.message}")
          []
        end

        def create_cluster_config(name, context)
          kubeconfig_path = ENV.fetch('KUBECONFIG', File.expand_path('~/.kube/config'))

          Formatters::ProgressFormatter.with_spinner("Creating cluster '#{name}'") do
            # Create Kubernetes client to verify connection
            k8s = Kubernetes::Client.new(kubeconfig: kubeconfig_path, context: context)

            # Get namespace from context or use default
            namespace = k8s.current_namespace || 'default'

            # Check if operator is installed
            unless k8s.operator_installed?
              puts
              Formatters::ProgressFormatter.warn('Language Operator not found in cluster')
              puts
              puts 'The operator needs to be installed first.'
              puts 'Install with:'
              puts '  helm install language-operator oci://git.theryans.io/langop/charts/language-operator'
              puts
              exit 1
            end

            # Save cluster config
            Config::ClusterConfig.add_cluster(name, namespace, kubeconfig_path, context)
            Config::ClusterConfig.set_current_cluster(name)

            { name: name, namespace: namespace, kubeconfig: kubeconfig_path, context: context, k8s: k8s }
          end

          puts
          Formatters::ProgressFormatter.success("✓ Connected to #{context}")
          Formatters::ProgressFormatter.success("✓ Cluster '#{name}' created")
          puts

          {
            name: name,
            namespace: (kubeconfig_path && K8s::Config.load_file(kubeconfig_path).context(context).namespace) || 'default',
            kubeconfig: kubeconfig_path,
            context: context
          }
        rescue StandardError => e
          puts
          Formatters::ProgressFormatter.error("Failed to connect: #{e.message}")
          nil
        end

        def show_kubernetes_setup_guide
          puts
          puts pastel.yellow('Kubernetes Setup Required')
          puts
          puts 'Language Operator needs a Kubernetes cluster to run.'
          puts
          puts 'Quick options:'
          puts
          puts '  1. Docker Desktop (easiest for local development)'
          puts '     • Enable Kubernetes in Docker Desktop settings'
          puts '     • kubectl will be configured automatically'
          puts
          puts '  2. Minikube (lightweight local cluster)'
          puts '     • Install: brew install minikube'
          puts '     • Start: minikube start'
          puts
          puts '  3. Kind (Kubernetes in Docker)'
          puts '     • Install: brew install kind'
          puts '     • Create cluster: kind create cluster'
          puts
          puts 'After setting up kubectl, run quickstart again:'
          puts '  aictl quickstart'
          puts
        end

        def configure_model(cluster_info)
          puts
          puts '─' * 50
          puts pastel.cyan('Step 2/3: Configure Language Model')
          puts '─' * 50
          puts
          puts 'Agents need an LLM to understand instructions.'
          puts

          # Provider selection
          provider = prompt.select('Which provider do you want to use?') do |menu|
            menu.choice 'Anthropic (Claude)', :anthropic
            menu.choice 'OpenAI (GPT-4)', :openai
            menu.choice 'Local model (Ollama)', :ollama
            menu.choice 'Other', :other
          end

          case provider
          when :anthropic
            setup_anthropic_model(cluster_info)
          when :openai
            setup_openai_model(cluster_info)
          when :ollama
            setup_ollama_model(cluster_info)
          when :other
            setup_custom_model(cluster_info)
          end
        end

        def setup_anthropic_model(cluster_info)
          puts
          has_key = prompt.yes?('Do you have an Anthropic API key?')

          unless has_key
            puts
            puts "Get an API key at: #{pastel.cyan('https://console.anthropic.com')}"
            puts
            puts pastel.dim('Press Enter when you have your key...')
            $stdin.gets
          end

          puts
          api_key = prompt.mask('Enter your Anthropic API key:')

          # Test connection
          test_result = Formatters::ProgressFormatter.with_spinner('Testing connection') do
            test_anthropic_connection(api_key)
          end

          unless test_result[:success]
            Formatters::ProgressFormatter.error("Connection failed: #{test_result[:error]}")
            return nil
          end

          puts
          Formatters::ProgressFormatter.success('✓ Connected to Anthropic API')

          # Create model resource
          model_name = 'claude'
          model_id = 'claude-3-5-sonnet-20241022'

          create_model_resource(cluster_info, model_name, 'anthropic', model_id, api_key)

          Formatters::ProgressFormatter.success("✓ Using model: #{model_id}")
          puts

          { name: model_name, provider: 'anthropic', model: model_id }
        end

        def setup_openai_model(cluster_info)
          puts
          has_key = prompt.yes?('Do you have an OpenAI API key?')

          unless has_key
            puts
            puts "Get an API key at: #{pastel.cyan('https://platform.openai.com/api-keys')}"
            puts
            puts pastel.dim('Press Enter when you have your key...')
            $stdin.gets
          end

          puts
          api_key = prompt.mask('Enter your OpenAI API key:')

          # Test connection
          test_result = Formatters::ProgressFormatter.with_spinner('Testing connection') do
            test_openai_connection(api_key)
          end

          unless test_result[:success]
            Formatters::ProgressFormatter.error("Connection failed: #{test_result[:error]}")
            return nil
          end

          puts
          Formatters::ProgressFormatter.success('✓ Connected to OpenAI API')

          # Create model resource
          model_name = 'gpt4'
          model_id = 'gpt-4-turbo'

          create_model_resource(cluster_info, model_name, 'openai', model_id, api_key)

          Formatters::ProgressFormatter.success("✓ Using model: #{model_id}")
          puts

          { name: model_name, provider: 'openai', model: model_id }
        end

        def setup_ollama_model(cluster_info)
          puts
          puts 'Ollama runs LLMs locally on your machine.'
          puts

          endpoint = prompt.ask('Ollama endpoint:', default: 'http://localhost:11434')
          model_id = prompt.ask('Model name:', default: 'llama3')

          # Test connection
          test_result = Formatters::ProgressFormatter.with_spinner('Testing connection') do
            test_ollama_connection(endpoint, model_id)
          end

          unless test_result[:success]
            Formatters::ProgressFormatter.error("Connection failed: #{test_result[:error]}")
            puts
            puts 'Make sure Ollama is running and the model is pulled:'
            puts "  ollama pull #{model_id}"
            return nil
          end

          puts
          Formatters::ProgressFormatter.success('✓ Connected to Ollama')

          # Create model resource
          model_name = 'local'

          create_model_resource(cluster_info, model_name, 'openai_compatible', model_id, nil, endpoint)

          Formatters::ProgressFormatter.success("✓ Using model: #{model_id}")
          puts

          { name: model_name, provider: 'ollama', model: model_id }
        end

        def setup_custom_model(cluster_info)
          puts
          puts 'Configure a custom OpenAI-compatible endpoint.'
          puts

          endpoint = prompt.ask('API endpoint URL:') do |q|
            q.required true
            q.validate(%r{^https?://})
            q.messages[:valid?] = 'Must be a valid HTTP(S) URL'
          end

          model_id = prompt.ask('Model identifier:') do |q|
            q.required true
          end

          requires_auth = prompt.yes?('Does this endpoint require authentication?')

          api_key = nil
          api_key = prompt.mask('Enter API key:') if requires_auth

          puts
          Formatters::ProgressFormatter.info('Skipping connection test for custom endpoint')

          # Create model resource
          model_name = 'custom'

          create_model_resource(cluster_info, model_name, 'openai_compatible', model_id, api_key, endpoint)

          Formatters::ProgressFormatter.success("✓ Model configured: #{model_id}")
          puts

          { name: model_name, provider: 'custom', model: model_id }
        end

        def test_anthropic_connection(api_key)
          require 'ruby_llm'

          client = RubyLLM.new(provider: :anthropic, api_key: api_key)
          client.chat([{ role: 'user', content: 'Test' }], model: 'claude-3-5-sonnet-20241022', max_tokens: 10)

          { success: true }
        rescue StandardError => e
          { success: false, error: e.message }
        end

        def test_openai_connection(api_key)
          require 'ruby_llm'

          client = RubyLLM.new(provider: :openai, api_key: api_key)
          client.chat([{ role: 'user', content: 'Test' }], model: 'gpt-4-turbo', max_tokens: 10)

          { success: true }
        rescue StandardError => e
          { success: false, error: e.message }
        end

        def test_ollama_connection(endpoint, model)
          require 'ruby_llm'

          client = RubyLLM.new(provider: :openai_compatible, url: endpoint)
          client.chat([{ role: 'user', content: 'Test' }], model: model, max_tokens: 10)

          { success: true }
        rescue StandardError => e
          { success: false, error: e.message }
        end

        def create_model_resource(cluster_info, name, provider, model, api_key = nil, endpoint = nil)
          # rubocop:disable Metrics/BlockLength
          Formatters::ProgressFormatter.with_spinner("Creating model '#{name}'") do
            k8s = Kubernetes::Client.new(
              kubeconfig: cluster_info[:kubeconfig],
              context: cluster_info[:context]
            )

            # Create API key secret if provided
            if api_key
              secret_name = "#{name}-api-key"
              secret = {
                'apiVersion' => 'v1',
                'kind' => 'Secret',
                'metadata' => {
                  'name' => secret_name,
                  'namespace' => cluster_info[:namespace]
                },
                'type' => 'Opaque',
                'stringData' => {
                  'api-key' => api_key
                }
              }
              k8s.apply_resource(secret)
            end

            # Create LanguageModel resource
            resource = Kubernetes::ResourceBuilder.language_model(
              name,
              provider: provider,
              model: model,
              endpoint: endpoint,
              cluster: cluster_info[:namespace]
            )

            # Add API key reference if we created a secret
            if api_key
              resource['spec']['apiKeySecret'] = {
                'name' => "#{name}-api-key",
                'key' => 'api-key'
              }
            end

            k8s.apply_resource(resource)
          end
          # rubocop:enable Metrics/BlockLength
        end

        def create_example_agent(cluster_info, model_info)
          puts
          puts '─' * 50
          puts pastel.cyan('Step 3/3: Create Your First Agent')
          puts '─' * 50
          puts
          puts "Let's create a simple agent to see how it works."
          puts
          puts "I'll create an agent that tells you fun facts about Ruby."
          puts 'This agent will run once to show you how it works.'
          puts

          agent_name = 'ruby-facts'
          description = 'Tell me an interesting fun fact about the Ruby programming language'

          # Create agent
          Formatters::ProgressFormatter.with_spinner("Creating agent '#{agent_name}'") do
            k8s = Kubernetes::Client.new(
              kubeconfig: cluster_info[:kubeconfig],
              context: cluster_info[:context]
            )

            resource = Kubernetes::ResourceBuilder.language_agent(
              agent_name,
              instructions: description,
              cluster: cluster_info[:namespace],
              persona: nil,
              tools: [],
              models: [model_info[:name]]
            )

            k8s.apply_resource(resource)
          end

          puts
          Formatters::ProgressFormatter.success("✓ Agent '#{agent_name}' created")

          # NOTE: In a real implementation, we would watch for synthesis and trigger execution
          # For now, just inform the user
          puts
          puts pastel.dim('Note: The agent has been created and will start synthesizing.')
          puts pastel.dim('Check its status with: aictl agent inspect ruby-facts')
          puts
        end

        def show_next_steps
          puts
          Formatters::ProgressFormatter.success('✓ Success! Your setup is complete.')
          puts
          puts pastel.cyan("╭─ What's Next? #{'─' * 30}╮")
          puts '│'
          puts '│  1. Create your own agent:'
          puts "│     #{pastel.dim('aictl agent create "your task here"')}"
          puts '│'
          puts '│  2. Use the interactive wizard:'
          puts "│     #{pastel.dim('aictl agent create --wizard')}"
          puts '│'
          puts '│  3. View your agents:'
          puts "│     #{pastel.dim('aictl agent list')}"
          puts '│'
          puts '│  4. Check agent status:'
          puts "│     #{pastel.dim('aictl agent inspect ruby-facts')}"
          puts '│'
          puts pastel.cyan("╰#{'─' * 48}╯")
          puts
          puts pastel.green('Welcome to autonomous automation! 🚀')
          puts
        end
      end
    end
  end
end
