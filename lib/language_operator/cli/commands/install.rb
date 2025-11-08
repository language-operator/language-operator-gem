# frozen_string_literal: true

require 'thor'
require 'open3'
require_relative '../formatters/progress_formatter'
require_relative '../helpers/cluster_validator'
require_relative '../helpers/user_prompts'

module LanguageOperator
  module CLI
    module Commands
      # Install, upgrade, and uninstall commands for the language-operator
      class Install < Thor
        HELM_REPO_NAME = 'git.theryans.io'
        HELM_REPO_URL = 'https://git.theryans.io/api/packages/language-operator/helm'
        CHART_NAME = 'git.theryans.io/language-operator'
        RELEASE_NAME = 'language-operator'
        DEFAULT_NAMESPACE = 'language-operator-system'

        # Helper method to get long descriptions for commands
        def self.long_desc_for(command)
          case command
          when :install
            <<-DESC
              Install the language-operator into your Kubernetes cluster using Helm.

              This command will:
              1. Add the language-operator Helm repository
              2. Update Helm repositories
              3. Install the language-operator chart
              4. Verify the installation

              Examples:
                # Install with defaults
                aictl install

                # Install with custom values
                aictl install --values my-values.yaml

                # Install specific version
                aictl install --version 0.1.0

                # Dry run to see what would be installed
                aictl install --dry-run
            DESC
          when :upgrade
            <<-DESC
              Upgrade the language-operator to a newer version using Helm.

              This command will:
              1. Update Helm repositories
              2. Upgrade the language-operator release
              3. Wait for the rollout to complete
              4. Verify the operator is running

              Examples:
                # Upgrade to latest version
                aictl upgrade

                # Upgrade with custom values
                aictl upgrade --values my-values.yaml

                # Upgrade to specific version
                aictl upgrade --version 0.2.0
            DESC
          when :uninstall
            <<-DESC
              Uninstall the language-operator from your Kubernetes cluster.

              WARNING: This will remove the operator but NOT the CRDs or custom resources.
              Agents, tools, models, and personas will remain in the cluster.

              Examples:
                # Uninstall with confirmation
                aictl uninstall

                # Force uninstall without confirmation
                aictl uninstall --force

                # Uninstall from specific namespace
                aictl uninstall --namespace my-namespace
            DESC
          end
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
            aictl install

            # Install with custom values
            aictl install --values my-values.yaml

            # Install specific version
            aictl install --version 0.1.0

            # Dry run to see what would be installed
            aictl install --dry-run
        DESC
        option :values, type: :string, desc: 'Path to custom Helm values file'
        option :namespace, type: :string, default: DEFAULT_NAMESPACE, desc: 'Kubernetes namespace'
        option :version, type: :string, desc: 'Specific chart version to install'
        option :dry_run, type: :boolean, default: false, desc: 'Preview installation without applying'
        option :wait, type: :boolean, default: true, desc: 'Wait for deployment to complete'
        option :create_namespace, type: :boolean, default: true, desc: 'Create namespace if it does not exist'
        def install
          # Check if helm is available
          check_helm_installed!

          # Check if operator is already installed
          if operator_installed? && !options[:dry_run]
            Formatters::ProgressFormatter.warn('Language operator is already installed')
            puts
            puts 'To upgrade, use:'
            puts '  aictl upgrade'
            return
          end

          namespace = options[:namespace]

          puts 'Installing language-operator...'
          puts "  Namespace: #{namespace}"
          puts "  Chart: #{CHART_NAME}"
          puts

          # Add Helm repository
          add_helm_repo unless options[:dry_run]

          # Build helm install command
          cmd = build_helm_command('install', namespace)

          # Execute helm install
          if options[:dry_run]
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

            Formatters::ProgressFormatter.success('Language operator installed successfully!')
            puts
            puts 'Next steps:'
            puts '  1. Create a cluster: aictl cluster create my-cluster'
            puts '  2. Create a model: aictl model create gpt4 --provider openai --model gpt-4-turbo'
            puts '  3. Create an agent: aictl agent create "your agent description"'
          end
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Installation failed: #{e.message}")
          raise if ENV['DEBUG']

          exit 1
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
            aictl upgrade

            # Upgrade with custom values
            aictl upgrade --values my-values.yaml

            # Upgrade to specific version
            aictl upgrade --version 0.2.0
        DESC
        option :values, type: :string, desc: 'Path to custom Helm values file'
        option :namespace, type: :string, default: DEFAULT_NAMESPACE, desc: 'Kubernetes namespace'
        option :version, type: :string, desc: 'Specific chart version to upgrade to'
        option :dry_run, type: :boolean, default: false, desc: 'Preview upgrade without applying'
        option :wait, type: :boolean, default: true, desc: 'Wait for deployment to complete'
        def upgrade
          # Check if helm is available
          check_helm_installed!

          # Check if operator is installed
          unless operator_installed?
            Formatters::ProgressFormatter.error('Language operator is not installed')
            puts
            puts 'To install, use:'
            puts '  aictl install'
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
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Upgrade failed: #{e.message}")
          raise if ENV['DEBUG']

          exit 1
        end

        desc 'uninstall', 'Uninstall the language-operator using Helm'
        long_desc <<-DESC
          Uninstall the language-operator from your Kubernetes cluster.

          WARNING: This will remove the operator but NOT the CRDs or custom resources.
          Agents, tools, models, and personas will remain in the cluster.

          Examples:
            # Uninstall with confirmation
            aictl uninstall

            # Force uninstall without confirmation
            aictl uninstall --force

            # Uninstall from specific namespace
            aictl uninstall --namespace my-namespace
        DESC
        option :namespace, type: :string, default: DEFAULT_NAMESPACE, desc: 'Kubernetes namespace'
        option :force, type: :boolean, default: false, desc: 'Skip confirmation prompt'
        def uninstall
          # Check if helm is available
          check_helm_installed!

          # Check if operator is installed
          unless operator_installed?
            Formatters::ProgressFormatter.warn('Language operator is not installed')
            return
          end

          namespace = options[:namespace]

          # Confirm deletion unless --force
          unless options[:force]
            puts "This will uninstall the language-operator from namespace '#{namespace}'"
            puts
            puts 'WARNING: This will NOT delete:'
            puts '  - CRDs (CustomResourceDefinitions)'
            puts '  - LanguageAgent resources'
            puts '  - LanguageTool resources'
            puts '  - LanguageModel resources'
            puts '  - LanguagePersona resources'
            puts
            return unless Helpers::UserPrompts.confirm('Continue with uninstall?')
          end

          # Build helm uninstall command
          cmd = "helm uninstall #{RELEASE_NAME} --namespace #{namespace}"

          # Execute helm uninstall
          Formatters::ProgressFormatter.with_spinner('Uninstalling language-operator') do
            success, output = run_helm_command(cmd)
            raise "Helm uninstall failed: #{output}" unless success
          end

          Formatters::ProgressFormatter.success('Language operator uninstalled successfully!')
          puts
          puts 'Note: CRDs and custom resources remain in the cluster.'
          puts 'To completely remove all resources, you must manually delete them.'
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Uninstall failed: #{e.message}")
          raise if ENV['DEBUG']

          exit 1
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
          cmd = ['helm', action, RELEASE_NAME]

          # Add chart name for install
          cmd << CHART_NAME if action == 'install'

          # Add namespace
          cmd << '--namespace' << namespace

          # Add create-namespace for install
          cmd << '--create-namespace' if action == 'install' && options[:create_namespace]

          # Add values file
          cmd << '--values' << options[:values] if options[:values]

          # Add version
          cmd << '--version' << options[:version] if options[:version]

          # Add wait
          cmd << '--wait' if options[:wait]

          # Add dry-run
          cmd << '--dry-run' if options[:dry_run]

          cmd.join(' ')
        end

        def run_helm_command(cmd)
          stdout, stderr, status = Open3.capture3(cmd)
          output = stdout + stderr
          [status.success?, output.strip]
        end
      end
    end
  end
end
