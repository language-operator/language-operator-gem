# frozen_string_literal: true

require_relative '../base_command'
require 'open3'
require_relative '../formatters/progress_formatter'
require_relative '../helpers/cluster_validator'
require_relative '../helpers/user_prompts'

module LanguageOperator
  module CLI
    module Commands
      # Install, upgrade, and uninstall commands for the language-operator
      class Install < BaseCommand
        HELM_REPO_NAME = 'language-operator'
        HELM_REPO_URL = 'https://language-operator.github.io/charts'
        CHART_NAME = 'language-operator/language-operator'
        RELEASE_NAME = 'language-operator'
        DEFAULT_NAMESPACE = 'language-operator'

        # Long descriptions for commands
        LONG_DESCRIPTIONS = {
          install: <<-DESC,
            Install the language-operator into your Kubernetes cluster using Helm.

            This command will:
            1. Add the language-operator Helm repository
            2. Update Helm repositories
            3. Install the language-operator chart
            4. Verify the installation

            Examples:
              # Install with defaults
              langop install

              # Install with custom values
              langop install --values my-values.yaml

              # Install specific version
              langop install --version 0.1.0

              # Dry run to see what would be installed
              langop install --dry-run
          DESC
          upgrade: <<-DESC,
            Upgrade the language-operator to a newer version using Helm.

            This command will:
            1. Update Helm repositories
            2. Upgrade the language-operator release
            3. Wait for the rollout to complete
            4. Verify the operator is running

            Examples:
              # Upgrade to latest version
              langop upgrade

              # Upgrade with custom values
              langop upgrade --values my-values.yaml

              # Upgrade to specific version
              langop upgrade --version 0.2.0
          DESC
          uninstall: <<-DESC
            Completely uninstall the language-operator from your Kubernetes cluster.

            This will:
            1. Delete all custom resources (agents, tools, models, personas, clusters)
            2. Uninstall the operator using Helm
            3. Remove all CRDs (CustomResourceDefinitions)

            WARNING: This will completely remove all language-operator resources from the cluster.

            Examples:
              # Complete uninstall with confirmation
              langop uninstall

              # Force uninstall without confirmation
              langop uninstall --force

              # Uninstall from specific namespace
              langop uninstall --namespace my-namespace
          DESC
        }.freeze

        # Helper method to get long descriptions for commands
        def self.long_desc_for(command)
          LONG_DESCRIPTIONS[command]
        end

        desc 'install', 'Install the language-operator using Helm'
        long_desc <<-DESC
          Install the language-operator into your Kubernetes cluster using Helm.

          This command will:
          1. Add the language-operator Helm repository
          2. Update Helm repositories
          3. Install the language-operator chart
          4. Verify the installation

          Examples:
            # Install with defaults
            langop install

            # Install with custom values
            langop install --values my-values.yaml

            # Install specific version
            langop install --version 0.1.0

            # Dry run to see what would be installed
            langop install --dry-run
        DESC
        option :values, type: :string, desc: 'Path to custom Helm values file'
        option :namespace, type: :string, default: DEFAULT_NAMESPACE, desc: 'Kubernetes namespace'
        option :version, type: :string, desc: 'Specific chart version to install'
        option :dry_run, type: :boolean, default: false, desc: 'Preview installation without applying'
        option :wait, type: :boolean, default: true, desc: 'Wait for deployment to complete'
        option :create_namespace, type: :boolean, default: true, desc: 'Create namespace if it does not exist'
        option :non_interactive, type: :boolean, default: false, desc: 'Skip interactive prompts and use defaults'
        def install
          handle_command_error('install') do
            # Check if helm is available
            check_helm_installed!

            # Check if operator is already installed
            if operator_installed? && !options[:dry_run]
              Formatters::ProgressFormatter.warn('Language operator is already installed')
              puts
              puts 'To upgrade, use:'
              puts '  langop upgrade'
              return
            end

            namespace = options[:namespace]

            # Interactive configuration unless non-interactive mode or custom values provided
            unless options[:non_interactive] || options[:values]
              logo(title: 'language operator installer')
              puts 'This installer will help you configure the Language Operator for your cluster.'
              puts

              config = collect_interactive_configuration
              values_file = generate_values_file(config)
              # Create a mutable copy of options to avoid frozen hash error
              @options = options.dup
              @options[:values] = values_file
            end

            # Add Helm repository
            add_helm_repo unless (@options || options)[:dry_run]

            # Build helm install command (use @options if we created a mutable copy)
            cmd = build_helm_command('install', namespace)

            # Execute helm install
            if (@options || options)[:dry_run]
              puts 'Dry run - would execute:'
              puts "  #{cmd}"
              puts
              success, output = run_helm_command(cmd)
              puts output
            else
              Formatters::ProgressFormatter.with_spinner('Installing language-operator') do
                success, output = run_helm_command(cmd)
                raise "Helm install failed: #{output}" unless success
              end
            end
          end
        end

        desc 'upgrade', 'Upgrade the language-operator using Helm'
        long_desc <<-DESC
          Upgrade the language-operator to a newer version using Helm.

          This command will:
          1. Update Helm repositories
          2. Upgrade the language-operator release
          3. Wait for the rollout to complete
          4. Verify the operator is running

          Examples:
            # Upgrade to latest version
            langop upgrade

            # Upgrade with custom values
            langop upgrade --values my-values.yaml

            # Upgrade to specific version
            langop upgrade --version 0.2.0
        DESC
        option :values, type: :string, desc: 'Path to custom Helm values file'
        option :namespace, type: :string, default: DEFAULT_NAMESPACE, desc: 'Kubernetes namespace'
        option :version, type: :string, desc: 'Specific chart version to upgrade to'
        option :dry_run, type: :boolean, default: false, desc: 'Preview upgrade without applying'
        option :wait, type: :boolean, default: true, desc: 'Wait for deployment to complete'
        def upgrade
          handle_command_error('upgrade') do
            # Check if helm is available
            check_helm_installed!

            # Check if operator is installed
            unless operator_installed?
              Formatters::ProgressFormatter.error('Language operator is not installed')
              puts
              puts 'To install, use:'
              puts '  langop install'
              exit 1
            end

            namespace = options[:namespace]

            puts 'Upgrading language-operator...'
            puts "  Namespace: #{namespace}"
            puts "  Chart: #{CHART_NAME}"
            puts

            # Update Helm repository
            update_helm_repo unless options[:dry_run]

            # Build helm upgrade command
            cmd = build_helm_command('upgrade', namespace)

            # Execute helm upgrade
            if options[:dry_run]
              puts 'Dry run - would execute:'
              puts "  #{cmd}"
              puts
              success, output = run_helm_command(cmd)
              puts output
            else
              Formatters::ProgressFormatter.with_spinner('Upgrading language-operator') do
                success, output = run_helm_command(cmd)
                raise "Helm upgrade failed: #{output}" unless success
              end

              Formatters::ProgressFormatter.success('Language operator upgraded successfully!')
            end
          end
        end

        desc 'uninstall', 'Uninstall the language-operator using Helm'
        long_desc <<-DESC
          Completely uninstall the language-operator from your Kubernetes cluster.

          This will:
          1. Delete all custom resources (agents, tools, models, personas, clusters)
          2. Uninstall the operator using Helm
          3. Remove all CRDs (CustomResourceDefinitions)

          WARNING: This will completely remove all language-operator resources from the cluster.

          Examples:
            # Complete uninstall with confirmation
            langop uninstall

            # Force uninstall without confirmation
            langop uninstall --force

            # Uninstall from specific namespace
            langop uninstall --namespace my-namespace
        DESC
        option :namespace, type: :string, default: DEFAULT_NAMESPACE, desc: 'Kubernetes namespace'
        option :force, type: :boolean, default: false, desc: 'Skip confirmation prompt'
        def uninstall
          handle_command_error('uninstall') do
            # Check if helm is available
            check_helm_installed!

            # Check if operator is installed but proceed with cleanup regardless

            namespace = options[:namespace]

            # Confirm deletion unless --force
            unless options[:force]
              puts 'This will completely uninstall the language-operator from your cluster:'
              puts
              puts '  - The language-operator Helm release'
              puts '  - All existing clusters, agents, models, tools and personas'
              puts '  - Persistent volumes (ClickHouse, PostgreSQL data)'
              puts
              puts "#{pastel.bold.red('WARNING')}: #{pastel.white.bold('This action cannot be undone!')}"
              puts
              return unless CLI::Helpers::UserPrompts.confirm('Continue with complete uninstall?')
            end

            # Step 1: Delete all custom resources
            delete_all_custom_resources

            # Step 2: Uninstall Helm release if it exists
            if operator_installed?
              cmd = "helm uninstall #{RELEASE_NAME} --namespace #{namespace}"

              Formatters::ProgressFormatter.with_spinner('Uninstalling language-operator Helm release') do
                success, output = run_helm_command(cmd)
                raise "Helm uninstall failed: #{output}" unless success
              end
            end

            # Step 3: Delete PVCs
            delete_persistent_volumes

            # Step 4: Delete CRDs
            delete_language_operator_crds
          end
        end

        private

        def check_helm_installed!
          _, _, status = Open3.capture3('which helm')
          return if status.success?

          Formatters::ProgressFormatter.error('Helm is not installed')
          puts
          puts 'Install Helm from: https://helm.sh/docs/intro/install/'
          exit 1
        end

        def operator_installed?
          namespace = options[:namespace] || DEFAULT_NAMESPACE
          cmd = "helm list --namespace #{namespace} --filter #{RELEASE_NAME} --output json"
          success, output = run_helm_command(cmd)
          return false unless success

          require 'json'
          releases = JSON.parse(output)
          releases.any? { |r| r['name'] == RELEASE_NAME }
        rescue StandardError
          false
        end

        def add_helm_repo
          Formatters::ProgressFormatter.with_spinner('Adding Helm repository') do
            # Check if repo already exists
            cmd = 'helm repo list --output json'
            success, output = run_helm_command(cmd)

            if success
              require 'json'
              repos = JSON.parse(output)
              repo_exists = repos.any? { |r| r['name'] == HELM_REPO_NAME }

              unless repo_exists
                cmd = "helm repo add #{HELM_REPO_NAME} #{HELM_REPO_URL}"
                success, output = run_helm_command(cmd)
                raise "Failed to add Helm repo: #{output}" unless success
              end
            else
              # helm repo list failed, try adding anyway
              cmd = "helm repo add #{HELM_REPO_NAME} #{HELM_REPO_URL}"
              success, output = run_helm_command(cmd)
              raise "Failed to add Helm repo: #{output}" unless success
            end

            # Update repo
            cmd = "helm repo update #{HELM_REPO_NAME}"
            success, output = run_helm_command(cmd)
            raise "Failed to update Helm repo: #{output}" unless success
          end
        end

        def update_helm_repo
          Formatters::ProgressFormatter.with_spinner('Updating Helm repository') do
            cmd = "helm repo update #{HELM_REPO_NAME}"
            success, output = run_helm_command(cmd)
            raise "Failed to update Helm repo: #{output}" unless success
          end
        end

        def build_helm_command(action, namespace)
          # Use @options if available (from interactive mode), otherwise use options
          opts = @options || options

          cmd = ['helm', action, RELEASE_NAME]

          # Add chart name for install
          cmd << CHART_NAME if action == 'install'

          # Add namespace
          cmd << '--namespace' << namespace

          # Add create-namespace for install
          cmd << '--create-namespace' if action == 'install' && opts[:create_namespace]

          # Add values file
          cmd << '--values' << opts[:values] if opts[:values]

          # Add version
          cmd << '--version' << opts[:version] if opts[:version]

          # Add wait
          cmd << '--wait' if opts[:wait]

          # Add dry-run
          cmd << '--dry-run' if opts[:dry_run]

          cmd.join(' ')
        end

        def run_helm_command(cmd)
          stdout, stderr, status = Open3.capture3(cmd)
          output = stdout + stderr
          [status.success?, output.strip]
        end

        # Delete all language-operator custom resources from all namespaces
        def delete_all_custom_resources
          require_relative '../../kubernetes/client'
          require_relative '../../constants'

          k8s = Kubernetes::Client.new

          resource_types = [
            Constants::RESOURCE_AGENT,
            Constants::RESOURCE_AGENT_VERSION,
            Constants::RESOURCE_TOOL,
            Constants::RESOURCE_MODEL,
            Constants::RESOURCE_PERSONA,
            'LanguageCluster'
          ]

          resource_types.each do |resource_type|
            Formatters::ProgressFormatter.with_spinner("Deleting all #{resource_type} resources") do
              # Get resources from all namespaces
              resources = k8s.list_resources(resource_type, namespace: nil)

              resources.each do |resource|
                name = resource.dig('metadata', 'name')
                namespace = resource.dig('metadata', 'namespace')

                begin
                  k8s.delete_resource(resource_type, name, namespace)
                rescue StandardError => e
                  # Continue deleting other resources even if one fails
                  warn "Failed to delete #{resource_type} #{name}: #{e.message}" if ENV['DEBUG']
                end
              end
            end
          rescue StandardError => e
            # Continue with other resource types if one fails
            Formatters::ProgressFormatter.warn("Failed to delete #{resource_type} resources: #{e.message}")
          end
        end

        # Delete language-operator CRDs
        def delete_language_operator_crds
          require_relative '../../kubernetes/client'
          require_relative '../../constants'

          k8s = Kubernetes::Client.new

          crd_names = [
            'languageagents.language-operator.dev',
            'languagetools.language-operator.dev',
            'languagemodels.language-operator.dev',
            'languagepersonas.language-operator.dev',
            'languageclusters.language-operator.dev',
            'languageagentversions.language-operator.dev'
          ]

          Formatters::ProgressFormatter.with_spinner('Deleting language-operator CRDs') do
            crd_names.each do |crd_name|
              k8s.delete_resource('CustomResourceDefinition', crd_name)
            rescue StandardError => e
              # Continue deleting other CRDs even if one fails
              warn "Failed to delete CRD #{crd_name}: #{e.message}" if ENV['DEBUG']
            end
          end
        end

        # Collect interactive configuration from user
        def collect_interactive_configuration
          config = {}

          # Generate a random password as default
          require 'securerandom'
          default_password = SecureRandom.alphanumeric(12)

          puts pastel.white.bold('Create a Login')
          config[:admin_name] = prompt.ask('Full Name:', default:  'Default')
          config[:admin_email] = prompt.ask('Email:', default: 'admin@example.com')
          config[:admin_password] = prompt.ask('Password:', default: default_password)

          puts
          puts pastel.white.bold('Gateway')

          # Check if gateways are available first
          gateways = get_available_gateways

          if gateways.empty?
            puts 'No gateways found in the cluster.'
            puts 'You can configure gateway access later after creating a gateway resource.'
          else
            create_gateway = prompt.yes?('Do you want to configure a gateway for external access?')
            config[:gateway] = collect_gateway_configuration if create_gateway
          end

          puts
          config
        end

        # Collect gateway configuration
        def collect_gateway_configuration
          gateway_config = {}

          # Get available gateways (we know there are some since we checked before calling this)
          gateways = get_available_gateways

          # Create choices for the select menu
          choices = gateways.map { |gw| { name: "#{gw[:name]} (#{gw[:namespace]})", value: gw } }

          selected_gateway = prompt.select('Select a gateway:', choices)
          gateway_config[:gateway_name] = selected_gateway[:name]
          gateway_config[:gateway_namespace] = selected_gateway[:namespace]

          gateway_config[:hostname] = prompt.ask('Hostname for the gateway:', default: 'langop.local')
          gateway_config[:tls] = prompt.yes?('Enable TLS/HTTPS?')

          gateway_config
        end

        # Get available gateways from the cluster
        def get_available_gateways
          require_relative '../../kubernetes/client'

          begin
            k8s = Kubernetes::Client.new
            gateways = k8s.list_resources('Gateway', namespace: nil, api_version: 'gateway.networking.k8s.io/v1')
            gateways.map do |gw|
              {
                name: gw.dig('metadata', 'name'),
                namespace: gw.dig('metadata', 'namespace')
              }
            end.compact
          rescue StandardError => e
            warn "Failed to list gateways: #{e.message}" if ENV['DEBUG']
            []
          end
        end

        # Generate values.yaml file from configuration
        def generate_values_file(config)
          require 'tempfile'
          require 'bcrypt'
          require 'yaml'

          # Hash the password and convert to string
          password_hash = BCrypt::Password.create(config[:admin_password]).to_s

          values = {
            'dashboard' => {
              'initialSetup' => {
                'enabled' => true,
                'adminUser' => {
                  'name' => config[:admin_name],
                  'email' => config[:admin_email],
                  'passwordHash' => password_hash
                }
              }
            }
          }

          # Add gateway configuration if provided
          if config[:gateway]
            values['gateway'] = {
              'enabled' => true,
              'gatewayName' => config[:gateway][:gateway_name],
              'gatewayNamespace' => config[:gateway][:gateway_namespace],
              'hostname' => config[:gateway][:hostname],
              'tls' => {
                'enabled' => config[:gateway][:tls]
              }
            }
          end

          # Create temporary values file
          values_file = Tempfile.new(['langop-values', '.yaml'])
          values_file.write(YAML.dump(values))
          values_file.close

          values_file.path
        end

        # Delete all language-operator persistent volumes
        def delete_persistent_volumes
          require_relative '../../kubernetes/client'

          k8s = Kubernetes::Client.new

          Formatters::ProgressFormatter.with_spinner('Deleting persistent volumes') do
            # Use label selector to find language-operator PVCs
            label_selector = 'app.kubernetes.io/instance=language-operator'

            begin
              all_pvcs = k8s.list_resources('PersistentVolumeClaim', namespace: nil, label_selector: label_selector)

              all_pvcs.each do |pvc|
                name = pvc.dig('metadata', 'name')
                namespace = pvc.dig('metadata', 'namespace')

                begin
                  k8s.delete_resource('PersistentVolumeClaim', name, namespace)
                rescue StandardError => e
                  warn "Failed to delete PVC #{name}: #{e.message}" if ENV['DEBUG']
                end
              end
            rescue StandardError => e
              warn "Failed to list/delete PVCs: #{e.message}" if ENV['DEBUG']
            end
          end
        end
      end
    end
  end
end
