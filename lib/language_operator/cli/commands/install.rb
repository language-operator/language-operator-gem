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

              # Post-installation verification
              verify_installation(config)
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

              # Restart the language-operator deployment to ensure new version is running
              restart_language_operator_deployment(namespace)
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
              puts '  - All organization namespaces and their resources'
              puts '  - Persistent volumes (ClickHouse, PostgreSQL data)'
              puts '  - Cluster-scoped resources (RBAC, webhooks, CRDs)'
              puts "  - The operator namespace (#{namespace})"
              puts
              puts "#{pastel.bold.red('WARNING')}: #{pastel.white.bold('This action cannot be undone!')}"
              puts
              return unless CLI::Helpers::UserPrompts.confirm('Continue with complete uninstall?')
            end

            # Step 1: Delete all custom resources
            delete_all_custom_resources

            # Step 2: Delete organization namespaces
            delete_organization_namespaces

            # Step 3: Uninstall Helm release if it exists
            if operator_installed?
              cmd = "helm uninstall #{RELEASE_NAME} --namespace #{namespace}"

              Formatters::ProgressFormatter.with_spinner('Uninstalling language-operator Helm release') do
                success, output = run_helm_command(cmd)
                raise "Helm uninstall failed: #{output}" unless success
              end
            end

            # Step 4: Delete PVCs
            delete_persistent_volumes

            # Step 5: Clean up cluster-scoped resources
            delete_cluster_scoped_resources

            # Step 6: Delete CRDs
            delete_language_operator_crds

            # Step 7: Delete the operator namespace
            delete_operator_namespace(namespace)
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

          # Add chart name for install and upgrade
          cmd << CHART_NAME if %w[install upgrade].include?(action)

          # Add namespace
          cmd << '--namespace' << namespace

          # Add create-namespace for install
          cmd << '--create-namespace' if action == 'install' && opts[:create_namespace]

          # Add values file or reuse existing values for upgrade
          if opts[:values]
            cmd << '--values' << opts[:values]
          elsif action == 'upgrade'
            cmd << '--reuse-values'
          end

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
            begin
              # Delete and wait for all resources of this type to be completely removed
              Formatters::ProgressFormatter.with_spinner("Deleting all #{resource_type} resources") do
                # First, get resources from all namespaces
                resources = k8s.list_resources(resource_type, namespace: nil)

                # Trigger deletion of each resource
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

                # Then wait for all resources of this type to be completely removed
                wait_for_resources_deletion_inline(resource_type, k8s, timeout: 300)
              end
            rescue StandardError => e
              # If API group doesn't exist (CRDs already deleted), show success anyway
              if e.message.include?('404') || e.message.include?('Not Found')
                puts "  - #{resource_type} API not available (CRDs likely already deleted)" if ENV['DEBUG']
                Formatters::ProgressFormatter.success("Deleting all #{resource_type} resources... done")
              else
                Formatters::ProgressFormatter.warn("Failed to delete #{resource_type} resources: #{e.message}")
              end
            end
          end
        end

        # Delete language-operator CRDs
        def delete_language_operator_crds
          require_relative '../../kubernetes/client'
          require_relative '../../constants'

          k8s = Kubernetes::Client.new

          Formatters::ProgressFormatter.with_spinner('Deleting language-operator CRDs') do
            # Find all CRDs with langop.io domain (CRDs are in apiextensions.k8s.io/v1)
            all_crds = k8s.list_resources('CustomResourceDefinition', namespace: nil, api_version: 'apiextensions.k8s.io/v1')
            langop_crds = all_crds.select do |crd|
              name = crd.dig('metadata', 'name')
              name&.end_with?('.langop.io')
            end

            puts "Found #{langop_crds.length} langop.io CRDs to delete" if ENV['DEBUG']

            langop_crds.each do |crd|
              crd_name = crd.dig('metadata', 'name')
              puts "Deleting CRD: #{crd_name}" if ENV['DEBUG']
              begin
                k8s.delete_resource('CustomResourceDefinition', crd_name, nil, 'apiextensions.k8s.io/v1')
                puts "Successfully deleted CRD: #{crd_name}" if ENV['DEBUG']
              rescue StandardError => e
                # Continue deleting other CRDs even if one fails
                puts "Failed to delete CRD #{crd_name}: #{e.message}"
              end
            end

            puts 'No langop.io CRDs found to delete' if langop_crds.empty? && ENV.fetch('DEBUG', nil)
          rescue StandardError => e
            puts "Failed to list/delete langop.io CRDs: #{e.message}"
          end
        end

        # Delete the operator namespace
        def delete_operator_namespace(namespace)
          require_relative '../../kubernetes/client'

          k8s = Kubernetes::Client.new

          Formatters::ProgressFormatter.with_spinner("Deleting operator namespace: #{namespace}") do
            # Check if namespace exists before trying to delete
            if k8s.namespace_exists?(namespace)
              k8s.delete_resource('Namespace', namespace)
            elsif ENV['DEBUG']
              puts "Namespace #{namespace} doesn't exist, skipping"
            end
          rescue StandardError => e
            warn "Failed to delete namespace #{namespace}: #{e.message}" if ENV['DEBUG']
          end
        end

        # Restart the language-operator deployment to ensure new version is running
        def restart_language_operator_deployment(namespace)
          Formatters::ProgressFormatter.with_spinner('Restarting language-operator deployment') do
            # Use kubectl rollout restart for the deployment
            cmd = "kubectl rollout restart deployment/language-operator --namespace #{namespace}"

            output = `#{cmd} 2>&1`
            success = $?.success?

            raise "Failed to restart deployment: #{output}" unless success
          rescue StandardError => e
            # Don't fail the entire upgrade if restart fails
            warn "Warning: Could not restart language-operator deployment: #{e.message}"
          end
        end

        # Collect interactive configuration from user
        def collect_interactive_configuration
          config = {}

          # Generate a random password as default
          require 'securerandom'
          default_password = SecureRandom.alphanumeric(12)

          puts pastel.white.bold('Create a Login')
          config[:admin_name] = prompt.ask('Full Name:', default: 'Default')
          config[:admin_email] = prompt.ask('Email:', default: 'admin@example.com')
          config[:admin_password] = prompt.ask('Password:', default: default_password)

          puts
          puts pastel.white.bold('Configure a Gateway')

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
          # Check CNI support first to determine header color
          cni_info = detect_cni_support
          if cni_info[:supports_network_policies]
            puts pastel.white.bold('Network Isolation')
          elsif cni_info[:name] == 'Unknown'
            puts pastel.yellow.bold('Warning: network isolation support not detected')
          else
            puts pastel.yellow.bold("Warning: #{cni_info[:name]} does not support network policies")
          end
          config[:network_isolation] = collect_network_isolation_configuration(cni_info)

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

        # Collect network isolation configuration
        def collect_network_isolation_configuration(cni_info)
          if cni_info[:supports_network_policies]
            enable_isolation = prompt.yes?("Enforce network isolation policies with #{cni_info[:name]}?")
            { enabled: enable_isolation }
          else
            proceed = prompt.yes?('Continue without network isolation?')
            exit 1 unless proceed
            { enabled: false }
          end
        end

        # Detect CNI and NetworkPolicy support
        def detect_cni_support
          require_relative '../../kubernetes/client'

          begin
            k8s = Kubernetes::Client.new

            # Try to detect CNI by checking nodes for CNI annotations or by looking for specific resources
            nodes = k8s.list_resources('Node', namespace: nil)

            # Check for common CNI indicators
            cni_info = detect_cni_from_nodes(nodes)

            # Only test API availability if we couldn't determine CNI-specific support
            if cni_info[:name] == 'Unknown'
              begin
                k8s.list_resources('NetworkPolicy', namespace: 'kube-system', api_version: 'networking.k8s.io/v1')
                cni_info[:supports_network_policies] = true
              rescue StandardError
                cni_info[:supports_network_policies] = false
              end
            end

            cni_info
          rescue StandardError => e
            warn "Failed to detect CNI: #{e.message}" if ENV['DEBUG']
            { name: 'Unknown', supports_network_policies: false }
          end
        end

        # Detect CNI from CRDs (most reliable method)
        def detect_cni_from_nodes(_nodes)
          require_relative '../../kubernetes/client'
          k8s = Kubernetes::Client.new

          # Check for CNI-specific CRDs - this is the most reliable method
          begin
            crds = k8s.list_resources('CustomResourceDefinition', namespace: nil, api_version: 'apiextensions.k8s.io/v1')

            crd_names = crds.map { |crd| crd.dig('metadata', 'name') }.compact.join(' ')

            # Check for specific CNI CRDs
            if crd_names.match?(/cilium/i)
              return { name: 'Cilium', supports_network_policies: true }
            elsif crd_names.match?(/(calico|projectcalico)/i)
              return { name: 'Calico', supports_network_policies: true }
            elsif crd_names.match?(/weave/i)
              return { name: 'Weave Net', supports_network_policies: true }
            elsif crd_names.match?(/antrea/i)
              return { name: 'Antrea', supports_network_policies: true }
            elsif crd_names.match?(/flannel/i)
              return { name: 'Flannel', supports_network_policies: false }
            end
          rescue StandardError => e
            warn "Failed to check CRDs for CNI detection: #{e.message}" if ENV['DEBUG']
          end

          # Fallback: Check for CNI-specific pods in kube-system
          begin
            pods = k8s.list_resources('Pod', namespace: 'kube-system')
            pod_names = pods.map { |pod| pod.dig('metadata', 'name') }.compact.join(' ')

            if pod_names.match?(/cilium/i)
              return { name: 'Cilium', supports_network_policies: true }
            elsif pod_names.match?(/calico/i)
              return { name: 'Calico', supports_network_policies: true }
            elsif pod_names.match?(/weave/i)
              return { name: 'Weave Net', supports_network_policies: true }
            elsif pod_names.match?(/antrea/i)
              return { name: 'Antrea', supports_network_policies: true }
            elsif pod_names.match?(/flannel/i)
              return { name: 'Flannel', supports_network_policies: false }
            elsif pod_names.match?(/aws-node/i)
              return { name: 'AWS VPC CNI', supports_network_policies: false }
            end
          rescue StandardError => e
            warn "Failed to check pods for CNI detection: #{e.message}" if ENV['DEBUG']
          end

          # Final fallback - we couldn't identify the CNI
          { name: 'Unknown', supports_network_policies: false }
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
              },
              'features' => {
                'signupsDisabled' => true
              }
            },
            'networkIsolation' => {
              'enabled' => config.dig(:network_isolation, :enabled) || false
            }
          }

          # Add gateway configuration if provided
          if config[:gateway]
            values['dashboard']['gateway'] = {
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

        # Delete all organization namespaces
        def delete_organization_namespaces
          require_relative '../../kubernetes/client'

          k8s = Kubernetes::Client.new
          namespace_names = []

          # Delete and wait for all organization namespaces to be completely removed
          Formatters::ProgressFormatter.with_spinner('Deleting organization namespaces') do
            begin
              # Find all namespaces with organization label
              org_namespaces = k8s.list_namespaces(
                label_selector: 'langop.io/type=organization'
              )

              # Trigger deletion of each namespace
              org_namespaces.each do |namespace|
                name = namespace.dig('metadata', 'name')
                namespace_names << name
                org_id = namespace.dig('metadata', 'labels', 'langop.io/organization-id')

                begin
                  k8s.delete_resource('Namespace', name)
                rescue StandardError => e
                  # Continue deleting other namespaces even if one fails
                  warn "Failed to delete organization namespace #{name} (#{org_id}): #{e.message}" if ENV['DEBUG']
                end
              end

              # Then wait for all organization namespaces to be completely deleted
              wait_for_namespaces_deletion_inline(namespace_names, k8s, timeout: 300) if namespace_names.any?
            rescue StandardError => e
              warn "Failed to list/delete organization namespaces: #{e.message}" if ENV['DEBUG']
            end
          end
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

        # Delete cluster-scoped resources that Helm doesn't automatically remove
        def delete_cluster_scoped_resources
          require_relative '../../kubernetes/client'

          k8s = Kubernetes::Client.new

          Formatters::ProgressFormatter.with_spinner('Cleaning up cluster-scoped resources') do
            # 1. Delete ClusterRoles
            delete_cluster_roles(k8s)

            # 2. Delete ClusterRoleBindings
            delete_cluster_role_bindings(k8s)

            # 3. Delete webhook configurations
            delete_webhook_configurations(k8s)

            # 4. Remove finalizers from stuck resources
            remove_stuck_finalizers(k8s)
          end
        end

        # Delete language-operator ClusterRoles
        def delete_cluster_roles(k8s)
          # Find ClusterRoles with language-operator labels
          cluster_roles = k8s.list_resources('ClusterRole',
                                             namespace: nil,
                                             api_version: 'rbac.authorization.k8s.io/v1',
                                             label_selector: 'app.kubernetes.io/name=language-operator')

          cluster_roles.each do |cr|
            name = cr.dig('metadata', 'name')
            begin
              k8s.delete_resource('ClusterRole', name, nil, 'rbac.authorization.k8s.io/v1')
            rescue StandardError => e
              warn "Failed to delete ClusterRole #{name}: #{e.message}" if ENV['DEBUG']
            end
          end
        rescue StandardError => e
          warn "Failed to list/delete ClusterRoles: #{e.message}" if ENV['DEBUG']
        end

        # Delete language-operator ClusterRoleBindings
        def delete_cluster_role_bindings(k8s)
          # Find ClusterRoleBindings with language-operator labels
          crbs = k8s.list_resources('ClusterRoleBinding',
                                    namespace: nil,
                                    api_version: 'rbac.authorization.k8s.io/v1',
                                    label_selector: 'app.kubernetes.io/name=language-operator')

          crbs.each do |crb|
            name = crb.dig('metadata', 'name')
            begin
              k8s.delete_resource('ClusterRoleBinding', name, nil, 'rbac.authorization.k8s.io/v1')
            rescue StandardError => e
              warn "Failed to delete ClusterRoleBinding #{name}: #{e.message}" if ENV['DEBUG']
            end
          end

          # Get all ClusterRoleBindings to find agent-specific ones and ServiceAccount references
          all_crbs = k8s.list_resources('ClusterRoleBinding', namespace: nil, api_version: 'rbac.authorization.k8s.io/v1')
          all_crbs.each do |crb|
            name = crb.dig('metadata', 'name')
            should_delete = false

            # Check if this is an agent-specific ClusterRoleBinding (pattern: language-agent-*)
            if name&.start_with?('language-agent-')
              should_delete = true
              puts "Found agent-specific ClusterRoleBinding: #{name}" if ENV['DEBUG']
            end

            # Also check if CRB references language-operator ServiceAccounts
            unless should_delete
              subjects = crb.dig('subjects') || []
              has_langop_subject = subjects.any? do |subject|
                subject['name']&.include?('language-operator')
              end

              if has_langop_subject
                should_delete = true
                puts "Found ClusterRoleBinding referencing language-operator ServiceAccount: #{name}" if ENV['DEBUG']
              end
            end

            # Also check if CRB references non-existent ClusterRoles that we know about
            unless should_delete
              role_ref = crb.dig('roleRef')
              if role_ref && role_ref['kind'] == 'ClusterRole' && role_ref['name'] == 'language-operator'
                should_delete = true
                puts "Found ClusterRoleBinding referencing deleted ClusterRole 'language-operator': #{name}" if ENV['DEBUG']
              end
            end

            # Delete if we found a reason to
            next unless should_delete

            begin
              k8s.delete_resource('ClusterRoleBinding', name, nil, 'rbac.authorization.k8s.io/v1')
              puts "Successfully deleted ClusterRoleBinding: #{name}" if ENV['DEBUG']
            rescue StandardError => e
              warn "Failed to delete ClusterRoleBinding #{name}: #{e.message}" if ENV['DEBUG']
            end
          end
        rescue StandardError => e
          warn "Failed to list/delete ClusterRoleBindings: #{e.message}" if ENV['DEBUG']
        end

        # Delete webhook configurations
        def delete_webhook_configurations(k8s)
          # Delete ValidatingWebhookConfigurations
          begin
            vwcs = k8s.list_resources('ValidatingWebhookConfiguration',
                                      namespace: nil,
                                      label_selector: 'app.kubernetes.io/name=language-operator')

            vwcs.each do |vwc|
              name = vwc.dig('metadata', 'name')
              begin
                k8s.delete_resource('ValidatingWebhookConfiguration', name)
              rescue StandardError => e
                warn "Failed to delete ValidatingWebhookConfiguration #{name}: #{e.message}" if ENV['DEBUG']
              end
            end
          rescue StandardError => e
            warn "Failed to list/delete ValidatingWebhookConfigurations: #{e.message}" if ENV['DEBUG']
          end

          # Delete MutatingWebhookConfigurations
          begin
            mwcs = k8s.list_resources('MutatingWebhookConfiguration',
                                      namespace: nil,
                                      label_selector: 'app.kubernetes.io/name=language-operator')

            mwcs.each do |mwc|
              name = mwc.dig('metadata', 'name')
              begin
                k8s.delete_resource('MutatingWebhookConfiguration', name)
              rescue StandardError => e
                warn "Failed to delete MutatingWebhookConfiguration #{name}: #{e.message}" if ENV['DEBUG']
              end
            end
          rescue StandardError => e
            warn "Failed to list/delete MutatingWebhookConfigurations: #{e.message}" if ENV['DEBUG']
          end
        end

        # Remove finalizers from stuck resources
        def remove_stuck_finalizers(k8s)
          # Remove finalizers from LanguageOperator CRDs if they're stuck
          crd_names = [
            'languageagents.langop.io',
            'languagetools.langop.io',
            'languagemodels.langop.io',
            'languagepersonas.langop.io',
            'languageclusters.langop.io',
            'languageagentversions.langop.io'
          ]

          crd_names.each do |crd_name|
            crd = k8s.get_resource('CustomResourceDefinition', crd_name, nil, 'apiextensions.k8s.io/v1')

            # Check if CRD has finalizers
            finalizers = crd.dig('metadata', 'finalizers')
            if finalizers && !finalizers.empty?
              # Remove finalizers to allow deletion
              patch = {
                'metadata' => {
                  'finalizers' => []
                }
              }
              k8s.patch_resource('CustomResourceDefinition', crd_name, patch, namespace: nil, api_version: 'apiextensions.k8s.io/v1')
            end
          rescue K8s::Error::NotFound
            # CRD doesn't exist, skip
          rescue StandardError => e
            warn "Failed to remove finalizers from CRD #{crd_name}: #{e.message}" if ENV['DEBUG']
          end

          # Remove finalizers from stuck custom resources
          resource_types = %w[LanguageAgent LanguageTool LanguageModel LanguagePersona LanguageCluster LanguageAgentVersion]
          resource_types.each do |resource_type|
            resources = k8s.list_resources(resource_type, namespace: nil)
            resources.each do |resource|
              finalizers = resource.dig('metadata', 'finalizers')
              next unless finalizers && !finalizers.empty?

              name = resource.dig('metadata', 'name')
              namespace = resource.dig('metadata', 'namespace')

              patch = {
                'metadata' => {
                  'finalizers' => []
                }
              }
              k8s.patch_resource(resource_type, name, patch, namespace: namespace)
            end
          rescue StandardError => e
            warn "Failed to remove finalizers from #{resource_type} resources: #{e.message}" if ENV['DEBUG']
          end
        rescue StandardError => e
          warn "Failed to remove stuck finalizers: #{e.message}" if ENV['DEBUG']
        end

        # Verify installation and setup
        def verify_installation(config)
          # Wait a moment for pods to start
          sleep 3

          # Verify account setup
          account_ready = verify_account_setup

          # Verify gateway setup if configured
          gateway_ready = false
          gateway_url = nil

          gateway_ready, gateway_url = verify_gateway_setup(config[:gateway]) if config&.dig(:gateway)

          # Determine next steps based on verification results
          show_post_install_message(config, account_ready, gateway_ready, gateway_url)
        end

        # Verify that the admin account was created successfully
        def verify_account_setup
          Formatters::ProgressFormatter.with_spinner('Verifying account setup') do
            # Check if dashboard pod is ready
            require_relative '../../kubernetes/client'
            k8s = Kubernetes::Client.new

            begin
              # Check if dashboard deployment is ready
              deployment = k8s.get_resource('Deployment', 'language-operator-dashboard', 'language-operator')
              ready_replicas = deployment.dig('status', 'readyReplicas') || 0
              desired_replicas = deployment.dig('spec', 'replicas') || 1

              ready_replicas >= desired_replicas
            rescue StandardError
              false
            end
          end
        end

        # Verify gateway configuration and HTTPRoute creation
        def verify_gateway_setup(gateway_config)
          gateway_url = nil

          success = Formatters::ProgressFormatter.with_spinner('Verifying gateway setup') do
            require_relative '../../kubernetes/client'
            k8s = Kubernetes::Client.new

            begin
              # Check if HTTPRoute was created (it should be in the gateway namespace)
              httproute_namespace = gateway_config[:gateway_namespace]
              k8s.get_resource('HTTPRoute', 'language-operator-dashboard', httproute_namespace, 'gateway.networking.k8s.io/v1')

              # Build the public URL
              protocol = gateway_config[:tls] ? 'https' : 'http'
              gateway_url = "#{protocol}://#{gateway_config[:hostname]}"

              true
            rescue StandardError => e
              warn "Gateway verification failed: #{e.message}" if ENV['DEBUG']
              false
            end
          end

          [success, gateway_url]
        end

        # Show appropriate post-installation message and actions
        def show_post_install_message(config, _account_ready, gateway_ready, gateway_url)
          if gateway_ready && gateway_url
            # Gateway configured successfully - open public URL
            puts
            puts 'Your Language Operator dashboard is available at:'
            puts pastel.cyan.bold(gateway_url)
            puts

            # Open browser to public URL
            open_browser(gateway_url) unless (@options || options)[:no_open]

          elsif config&.dig(:gateway) && !gateway_ready
            # Gateway was configured but failed
            puts pastel.yellow('⚠') + ' Installation completed with warnings'
            puts
            puts pastel.yellow('Gateway configuration had issues. You can access the dashboard locally:')
            puts "Run: #{pastel.cyan('langop ui')}"

          else
            # No gateway configured - show local access instructions
            puts
            puts "Run #{pastel.cyan.bold('langop ui')} to get started!"
          end
        end

        # Open browser to URL (delegates to UI command implementation)
        def open_browser(url)
          require_relative 'ui'
          ui_command = Ui.new
          ui_command.send(:open_browser, url)
        end

        # Wait for custom resources of a specific type to be completely deleted (inline with existing operation)
        def wait_for_resources_deletion_inline(resource_type, k8s, timeout: 300)
          start_time = Time.now

          loop do
            resources = k8s.list_resources(resource_type, namespace: nil)
            return true if resources.empty?

            # Check timeout
            if Time.now - start_time > timeout
              remaining_count = resources.length
              warn "Timeout waiting for #{resource_type} resources to be deleted (#{remaining_count} remaining)" if ENV['DEBUG']
              return false
            end

            # Sleep before next check
            sleep 2
          rescue StandardError => e
            # If API group doesn't exist (CRDs already deleted), consider it success
            return true if e.message.include?('404') || e.message.include?('Not Found')

            # Check timeout for other errors too
            if Time.now - start_time > timeout
              warn "Timeout waiting for #{resource_type} resources: #{e.message}" if ENV['DEBUG']
              return false
            end

            sleep 2
          end
        end

        # Wait for specific namespaces to be completely deleted (inline with existing operation)
        def wait_for_namespaces_deletion_inline(namespace_names, k8s, timeout: 300)
          start_time = Time.now
          remaining_namespaces = namespace_names.dup

          loop do
            remaining_namespaces = remaining_namespaces.select do |name|
              k8s.namespace_exists?(name)
            rescue StandardError
              # If we can't check, assume it's gone
              false
            end

            return true if remaining_namespaces.empty?

            # Check timeout
            if Time.now - start_time > timeout
              warn "Timeout waiting for namespaces to be deleted: #{remaining_namespaces.join(', ')}" if ENV['DEBUG']
              return false
            end

            # Sleep before next check
            sleep 2
          end
        end
      end
    end
  end
end
