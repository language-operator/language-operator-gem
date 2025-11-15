# frozen_string_literal: true

require 'k8s-ruby'
require_relative 'base'
require_relative '../cli/formatters/progress_formatter'
require_relative '../config/cluster_config'
require_relative '../kubernetes/client'
require_relative '../kubernetes/resource_builder'

module LanguageOperator
  module Ux
    # Interactive quickstart wizard for first-time setup
    #
    # Special case: Does not require cluster selection (creates/selects cluster during flow).
    #
    # @example
    #   Ux::Quickstart.execute
    #
    # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Naming/PredicateMethod
    class Quickstart < Base
      # Execute the quickstart flow
      #
      # @return [Boolean] true if quickstart completed successfully
      def execute
        show_welcome

        # Step 1: Cluster setup
        cluster_info = setup_cluster
        return false unless cluster_info

        # Step 2: Model configuration
        model_info = configure_model(cluster_info)
        return false unless model_info

        # Step 3: Example agent
        agent_created = create_example_agent(cluster_info, model_info)

        # Show next steps
        show_next_steps(agent_created: agent_created)

        true
      end

      private

      # Override: Quickstart does not require pre-selected cluster
      def requires_cluster?
        false
      end

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
          CLI::Formatters::ProgressFormatter.error('No kubectl contexts found')
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
        CLI::Formatters::ProgressFormatter.error("Failed to load kubeconfig: #{e.message}")
        []
      end

      def create_cluster_config(name, context)
        kubeconfig_path = ENV.fetch('KUBECONFIG', File.expand_path('~/.kube/config'))

        CLI::Formatters::ProgressFormatter.with_spinner("Creating cluster '#{name}'") do
          # Create Kubernetes client to verify connection
          k8s = Kubernetes::Client.new(kubeconfig: kubeconfig_path, context: context)

          # Get namespace from context or use default
          namespace = k8s.current_namespace || 'default'

          # Check if operator is installed
          unless k8s.operator_installed?
            puts
            CLI::Formatters::ProgressFormatter.warn('Language Operator not found in cluster')
            puts
            puts 'The operator needs to be installed first.'
            puts 'Install with:'
            puts '  aictl install'
            puts
            exit 1
          end

          # Save cluster config
          Config::ClusterConfig.add_cluster(name, namespace, kubeconfig_path, context)
          Config::ClusterConfig.set_current_cluster(name)

          { name: name, namespace: namespace, kubeconfig: kubeconfig_path, context: context, k8s: k8s }
        end

        {
          name: name,
          namespace: (kubeconfig_path && K8s::Config.load_file(kubeconfig_path).context(context).namespace) || 'default',
          kubeconfig: kubeconfig_path,
          context: context
        }
      rescue StandardError => e
        puts
        CLI::Formatters::ProgressFormatter.error("Failed to connect: #{e.message}")
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
        test_result = CLI::Formatters::ProgressFormatter.with_spinner('Testing connection') do
          test_anthropic_connection(api_key)
        end

        unless test_result[:success]
          CLI::Formatters::ProgressFormatter.error("Connection failed: #{test_result[:error]}")
          return nil
        end

        # Create model resource
        model_name = 'claude'
        model_id = 'claude-3-5-sonnet-20241022'

        create_model_resource(cluster_info, model_name, 'anthropic', model_id, api_key)

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
        test_result = CLI::Formatters::ProgressFormatter.with_spinner('Testing connection') do
          test_openai_connection(api_key)
        end

        unless test_result[:success]
          CLI::Formatters::ProgressFormatter.error("Connection failed: #{test_result[:error]}")
          return nil
        end

        # Create model resource
        model_name = 'gpt4'
        model_id = 'gpt-4-turbo'

        create_model_resource(cluster_info, model_name, 'openai', model_id, api_key)

        { name: model_name, provider: 'openai', model: model_id }
      end

      def setup_ollama_model(cluster_info)
        puts
        puts 'Ollama runs LLMs locally on your machine.'
        puts

        endpoint = prompt.ask('Ollama endpoint:', default: 'http://localhost:11434')
        model_id = prompt.ask('Model name:', default: 'llama3')

        # Test connection
        test_result = CLI::Formatters::ProgressFormatter.with_spinner('Testing connection') do
          test_ollama_connection(endpoint, model_id)
        end

        unless test_result[:success]
          CLI::Formatters::ProgressFormatter.error("Connection failed: #{test_result[:error]}")
          puts
          puts 'Make sure Ollama is running and the model is pulled:'
          puts "  ollama pull #{model_id}"
          return nil
        end

        # Create model resource
        model_name = 'local'

        create_model_resource(cluster_info, model_name, 'openai-compatible', model_id, nil, endpoint)

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

        requires_auth = prompt.yes?('Does this endpoint require authentication?')

        api_key = nil
        api_key = prompt.mask('Enter API key:') if requires_auth

        # Try to fetch available models from the endpoint
        puts
        available_models = fetch_available_models(endpoint, api_key)

        model_id = if available_models && !available_models.empty?
                     prompt.select('Select a model:', available_models, per_page: 10)
                   else
                     prompt.ask('Model identifier:') do |q|
                       q.required true
                     end
                   end

        puts
        CLI::Formatters::ProgressFormatter.info('Skipping connection test for custom endpoint')

        # Create model resource
        model_name = 'custom'

        create_model_resource(cluster_info, model_name, 'openai-compatible', model_id, api_key, endpoint)

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

      def fetch_available_models(endpoint, api_key = nil)
        require 'net/http'
        require 'json'
        require 'uri'

        models_url = URI.join(endpoint, '/v1/models').to_s

        models = nil
        count = 0

        CLI::Formatters::ProgressFormatter.with_spinner('Fetching available models') do
          uri = URI(models_url)
          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Bearer #{api_key}" if api_key
          request['Content-Type'] = 'application/json'

          response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(request)
          end

          if response.is_a?(Net::HTTPSuccess)
            data = JSON.parse(response.body)
            # Extract model IDs from the response
            models = data['data']&.map { |m| m['id'] } || []
            count = models.size
          else
            CLI::Formatters::ProgressFormatter.warn("Could not fetch models (HTTP #{response.code})")
          end
        end

        # Show count after spinner completes
        puts pastel.dim("Found #{count} models") if count.positive?
        models
      rescue StandardError => e
        CLI::Formatters::ProgressFormatter.warn("Could not fetch models: #{e.message}")
        nil
      end

      def create_model_resource(cluster_info, name, provider, model, api_key = nil, endpoint = nil)
        CLI::Formatters::ProgressFormatter.with_spinner("Creating model '#{name}'") do
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

        # Ask if user wants to create an example agent
        create_agent = prompt.yes?('Would you like to create a simple agent to see how things work?')

        unless create_agent
          puts
          puts pastel.dim('Skipping example agent creation.')
          puts
          return false
        end

        puts
        puts "I'll create an agent that tells you fun facts about Ruby."
        puts

        agent_name = 'ruby-facts'
        description = 'Tell me an interesting fun fact about the Ruby programming language'

        k8s = Kubernetes::Client.new(
          kubeconfig: cluster_info[:kubeconfig],
          context: cluster_info[:context]
        )

        # Create agent
        CLI::Formatters::ProgressFormatter.with_spinner("Creating agent '#{agent_name}'") do
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

        # Wait for synthesis
        wait_for_synthesis(k8s, agent_name, cluster_info[:namespace])

        true
      end
      # rubocop:enable Naming/PredicateMethod

      def wait_for_synthesis(k8s, agent_name, namespace)
        max_wait = 300 # 5 minutes for quickstart
        interval = 2
        elapsed = 0

        CLI::Formatters::ProgressFormatter.with_spinner('Synthesizing code') do
          loop do
            agent = k8s.get_resource('LanguageAgent', agent_name, namespace)
            conditions = agent.dig('status', 'conditions') || []
            synthesized = conditions.find { |c| c['type'] == 'Synthesized' }

            if synthesized
              if synthesized['status'] == 'True'
                break # Success
              elsif synthesized['status'] == 'False'
                raise StandardError, "Synthesis failed: #{synthesized['message']}"
              end
            end

            if elapsed >= max_wait
              CLI::Formatters::ProgressFormatter.warn('Synthesis is taking longer than expected, continuing in background')
              break
            end

            sleep interval
            elapsed += interval
          end
        end

        puts
      rescue K8s::Error::NotFound
        # Agent not found yet, retry
        retry if elapsed < max_wait
        raise
      end

      def show_next_steps(agent_created: false)
        puts
        puts pastel.cyan("What's Next?")
        puts

        if agent_created
          puts '1. Check your agent status:'
          puts "   #{pastel.dim('aictl agent inspect ruby-facts')}"
          puts
          puts '2. View the agent output:'
          puts "   #{pastel.dim('aictl agent logs ruby-facts')}"
          puts
          puts '3. Create another agent:'
          puts "   #{pastel.dim('aictl agent create "your task here"')}"
          puts
          puts '4. View all your agents:'
          puts "   #{pastel.dim('aictl agent list')}"
        else
          puts '1. Create your own agent:'
          puts "   #{pastel.dim('aictl agent create "your task here"')}"
          puts
          puts '2. Use the interactive wizard:'
          puts "   #{pastel.dim('aictl agent create --wizard')}"
          puts
          puts '3. View your agents:'
          puts "   #{pastel.dim('aictl agent list')}"
          puts
          puts '4. Check agent status:'
          puts "   #{pastel.dim('aictl agent inspect <agent-name>')}"
        end

        puts
        puts pastel.green('Welcome to autonomous automation! 🚀')
        puts
      end
    end
    # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize
  end
end
