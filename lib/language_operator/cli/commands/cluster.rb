# frozen_string_literal: true

require 'yaml'
require_relative '../command_loader'
require_relative '../../utils/secure_path'

module LanguageOperator
  module CLI
    module Commands
      # Cluster management commands
      class Cluster < BaseCommand
        include Constants
        include Helpers::UxHelper

        desc 'create NAME', 'Create a new language cluster'
        option :organization_id, type: :string, desc: 'Organization ID for the cluster (auto-detected if only one exists)'
        option :kubeconfig, type: :string, desc: 'Path to kubeconfig file'
        option :context, type: :string, desc: 'Kubernetes context to use'
        option :switch, type: :boolean, default: true, desc: 'Switch to new cluster context'
        option :dry_run, type: :boolean, default: false, desc: 'Output the manifest without creating'
        option :domain, type: :string, desc: 'Base domain for webhook routing (e.g., example.com)'
        def create(name)
          handle_command_error('create cluster') do
            kubeconfig = options[:kubeconfig]
            context = options[:context]
            org_id = options[:organization_id]

            # Create Kubernetes client to find organization namespace
            k8s = Formatters::ProgressFormatter.with_spinner('Connecting to Kubernetes cluster') do
              Kubernetes::Client.new(kubeconfig: kubeconfig, context: context)
            end

            # Auto-detect organization if not provided
            unless org_id
              org_id = detect_organization_id(k8s)
              exit 1 unless org_id
            end

            # Find the organization namespace
            namespace = Formatters::ProgressFormatter.with_spinner("Finding namespace for organization #{org_id[0..7]}") do
              find_org_namespace(k8s, org_id)
            end

            unless namespace
              Formatters::ProgressFormatter.error("Organization namespace not found for ID: #{org_id}")
              puts "\nMake sure the organization exists and you have access to it."
              puts "Available organization namespaces:"
              list_org_namespaces(k8s)
              exit 1
            end

            # Handle dry-run: output manifest and exit early
            if options[:dry_run]
              # Create a mock client to pass org context for dry run
              mock_client = Object.new
              def mock_client.current_org_id; @org_id; end
              mock_client.instance_variable_set(:@org_id, org_id)
              
              resource = Kubernetes::ResourceBuilder.language_cluster(name, namespace: namespace, domain: options[:domain], k8s_client: mock_client)
              puts resource.to_yaml
              return
            end

            # Check if cluster already exists in Kubernetes
            begin
              existing_cluster = k8s.get_resource('LanguageCluster', name, namespace)
              if existing_cluster
                Formatters::ProgressFormatter.error("Cluster '#{name}' already exists in namespace '#{namespace}'")
                exit 1
              end
            rescue StandardError => e
              # If we get a 404 or API error, the cluster doesn't exist - that's fine
              unless e.message.include?('404') || e.message.include?('Not Found')
                warn "Warning: Could not check for existing cluster: #{e.message}" if ENV['DEBUG']
              end
            end

            # Check if operator is installed
            unless k8s.operator_installed?
              Formatters::ProgressFormatter.error('Language Operator not found in cluster')
              puts "\nInstall the operator first:"
              puts '  langop install'
              exit 1
            end

            # Create namespace if it doesn't exist
            unless k8s.namespace_exists?(namespace)
              Formatters::ProgressFormatter.with_spinner("Creating namespace '#{namespace}'") do
                k8s.create_namespace(namespace, labels: Constants::KubernetesLabels.cluster_management_labels.merge(
                  Constants::KubernetesLabels::CLUSTER_LABEL => name
                ))
              end
            end

            # Create LanguageCluster resource
            Formatters::ProgressFormatter.with_spinner('Creating LanguageCluster resource') do
              labels = { 'langop.io/organization-id' => org_id }
              resource = Kubernetes::ResourceBuilder.language_cluster(name, namespace: namespace, domain: options[:domain], labels: labels, k8s_client: k8s)
              k8s.apply_resource(resource)
              resource
            end

            # Get the actual Kubernetes context being used
            actual_context = k8s.current_context

            # Save cluster to config
            Formatters::ProgressFormatter.with_spinner('Saving cluster configuration') do
              Config::ClusterConfig.add_cluster(
                name,
                namespace,
                kubeconfig || ENV.fetch('KUBECONFIG', LanguageOperator::Utils::SecurePath.expand_home_path('.kube/config')),
                actual_context
              )
            end

            # Switch to new cluster if requested
            Config::ClusterConfig.set_current_cluster(name) if options[:switch]

            puts
            format_cluster_details(
              name: name,
              namespace: namespace,
              context: actual_context,
              domain: options[:domain],
              org_id: org_id,
              status: 'Ready',
              created: Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')
            )

            # Show usage instructions if not auto-switched
            unless options[:switch]
              puts
              puts 'Switch to this cluster with:'
              puts pastel.dim("  langop use #{name}")
            end
          end
        end

        desc 'list', 'List all clusters'
        option :all, type: :boolean, default: false, desc: 'Show all clusters including inactive'
        def list
          handle_command_error('list clusters') do
            # Query Kubernetes directly for all LanguageCluster resources (like kubectl get languageclusters -A)
            k8s = Kubernetes::Client.new
            
            # List all LanguageCluster resources across all namespaces
            language_clusters = k8s.list_resources('LanguageCluster', namespace: nil)

            if language_clusters.empty?
              Formatters::ProgressFormatter.info('No clusters found')
              puts "\nCreate a cluster with:"
              puts '  langop cluster create <name>'
              return
            end

            current = Config::ClusterConfig.current_cluster

            # Build table data from LanguageCluster resources
            table_data = language_clusters.map do |cluster_resource|
              begin
                name = cluster_resource.dig('metadata', 'name')
                namespace = cluster_resource.dig('metadata', 'namespace')
                status = cluster_resource.dig('status', 'phase') || 'Unknown'
                domain = cluster_resource.dig('spec', 'domain')
                
                # Get organization information from the cluster resource itself
                org_id = cluster_resource.dig('metadata', 'labels', 'langop.io/organization-id')
                organization = org_id ? org_id[0..7] : 'legacy'
                
                # Check if this cluster matches the current selection
                name_display = name
                name_display = "#{pastel.bold(name)} (selected)" if name == current

                # Get related resources in the same namespace
                agents = k8s.list_resources(RESOURCE_AGENT, namespace: namespace)
                tools = k8s.list_resources(RESOURCE_TOOL, namespace: namespace)  
                models = k8s.list_resources(RESOURCE_MODEL, namespace: namespace)

                {
                  name: name_display,
                  namespace: namespace,
                  organization: organization,
                  agents: agents.count,
                  tools: tools.count,
                  models: models.count,
                  status: status,
                  domain: domain || ''
                }
              rescue StandardError => e
                # Handle any errors gracefully
                name = cluster_resource.dig('metadata', 'name') || 'unknown'
                namespace = cluster_resource.dig('metadata', 'namespace') || 'unknown'
                
                {
                  name: name,
                  namespace: namespace,
                  organization: '?',
                  agents: '?',
                  tools: '?',
                  models: '?',
                  status: 'Error',
                  domain: '?'
                }
              end
            end

            Formatters::TableFormatter.clusters(table_data)

            puts "\nNo cluster selected. Use 'langop use <cluster>' to select one." unless current
          end
        end

        desc 'current', 'Show current cluster context'
        def current
          handle_command_error('show current cluster') do
            cluster_name = Config::ClusterConfig.current_cluster

            unless cluster_name
              Formatters::ProgressFormatter.info('No cluster selected')
              puts "\nSelect a cluster with:"
              puts '  langop use <cluster>'
              return
            end

            cluster = Config::ClusterConfig.get_cluster(cluster_name)

            unless cluster
              Formatters::ProgressFormatter.error("Cluster '#{cluster_name}' not found in config")
              exit 1
            end

            puts 'Current Cluster:'
            puts "  Name:      #{cluster[:name]}"
            puts "  Namespace: #{cluster[:namespace]}"
            puts "  Context:   #{cluster[:context] || 'default'}"
            puts "  Created:   #{cluster[:created]}"

            # Check cluster health
            begin
              k8s = Helpers::ClusterValidator.kubernetes_client(cluster_name)

              if k8s.operator_installed?
                version = k8s.operator_version
                Formatters::ProgressFormatter.success("Operator: #{version || 'installed'}")
              else
                Formatters::ProgressFormatter.warn('Operator: not found')
              end
            rescue StandardError => e
              Formatters::ProgressFormatter.error("Connection: #{e.message}")
            end
          end
        end

        desc 'delete NAME', 'Delete a cluster'
        option :force, type: :boolean, default: false, desc: 'Skip confirmation'
        option :force_local, type: :boolean, default: false, desc: 'Force removal from local config only (skip Kubernetes deletion)'
        def delete(name)
          handle_command_error('delete cluster') do
            unless Config::ClusterConfig.cluster_exists?(name)
              Formatters::ProgressFormatter.error("Cluster '#{name}' not found")
              exit 1
            end

            cluster = Config::ClusterConfig.get_cluster(name)

            # Confirm deletion
            return if !options[:force] && !confirm_deletion('cluster', name, name)

            # Delete LanguageCluster resource from Kubernetes (unless --force-local)
            if options[:force_local]
              Formatters::ProgressFormatter.warn('Skipping Kubernetes resource deletion (--force-local specified)')
            else
              begin
                k8s = Helpers::ClusterValidator.kubernetes_client(name)

                Formatters::ProgressFormatter.with_spinner('Deleting LanguageCluster resource') do
                  k8s.delete_resource('LanguageCluster', name, cluster[:namespace])
                end
              rescue StandardError => e
                Formatters::ProgressFormatter.error("Failed to delete cluster resource: #{e.message}")
                puts
                puts 'Cluster deletion failed. The LanguageCluster resource could not be removed from Kubernetes.'
                puts 'This may be due to:'
                puts '  • Network connectivity issues'
                puts '  • Insufficient permissions'
                puts '  • The cluster resource no longer exists'
                puts
                puts 'To force removal from local configuration only, use:'
                puts pastel.dim("  langop cluster delete #{name} --force-local")
                exit 1
              end
            end

            # Remove from config only after successful Kubernetes deletion
            Formatters::ProgressFormatter.with_spinner('Removing cluster from configuration') do
              Config::ClusterConfig.remove_cluster(name)
            end

            # Clear current cluster if this was it
            Config::ClusterConfig.set_current_cluster(nil) if Config::ClusterConfig.current_cluster == name
          end
        end

        desc 'inspect NAME', 'Show detailed cluster information'
        def inspect(name)
          handle_command_error('inspect cluster') do
            unless Config::ClusterConfig.cluster_exists?(name)
              Formatters::ProgressFormatter.error("Cluster '#{name}' not found")
              exit 1
            end

            cluster = Config::ClusterConfig.get_cluster(name)

            # Get detailed cluster info
            begin
              k8s = Helpers::ClusterValidator.kubernetes_client(name)

              # Get cluster resource
              cluster_resource = k8s.get_resource('LanguageCluster', name, cluster[:namespace])
              status = cluster_resource.dig('status', 'phase') || 'Unknown'
              domain = cluster_resource.dig('spec', 'domain')

              # Main cluster information
              puts
              highlighted_box(
                title: 'LanguageCluster',
                rows: {
                  'Name' => pastel.white.bold(name),
                  'Namespace' => cluster[:namespace],
                  'Cluster' => name,
                  'Context' => cluster[:context] || 'default',
                  'Domain' => domain,
                  'Status' => status,
                  'Created' => cluster[:created]
                }.compact
              )
              puts

              # Get agents
              agents = k8s.list_resources(RESOURCE_AGENT, namespace: cluster[:namespace])
              agent_items = agents.map do |agent|
                { name: agent.dig('metadata', 'name'), status: agent.dig('status', 'phase') || 'Unknown' }
              end
              list_box(title: 'Agents', items: agent_items, style: :detailed)
              puts

              # Get tools
              tools = k8s.list_resources(RESOURCE_TOOL, namespace: cluster[:namespace])
              tool_items = tools.map do |tool|
                { name: tool.dig('metadata', 'name') }
              end
              list_box(title: 'Tools', items: tool_items, style: :detailed)
              puts

              # Get models
              models = k8s.list_resources(RESOURCE_MODEL, namespace: cluster[:namespace])
              model_items = models.map do |model|
                provider = model.dig('spec', 'provider')
                model_name = model.dig('spec', 'modelName')
                { name: model.dig('metadata', 'name'), meta: "#{provider}/#{model_name}" }
              end
              list_box(title: 'Models', items: model_items, style: :detailed)
              puts

              # Get personas
              personas = k8s.list_resources('LanguagePersona', namespace: cluster[:namespace])
              persona_items = personas.map do |persona|
                { name: persona.dig('metadata', 'name'), meta: persona.dig('spec', 'tone') }
              end
              list_box(title: 'Personas', items: persona_items, style: :detailed)
            rescue StandardError => e
              Formatters::ProgressFormatter.error("Failed to get cluster details: #{e.message}")
              raise if ENV['DEBUG']
            end
          end
        end

        private

        # Auto-detect organization ID when not provided
        # @param k8s_client [Kubernetes::Client] Kubernetes client  
        # @return [String, nil] Organization ID or nil if detection failed
        def detect_organization_id(k8s_client)
          # List all organization namespaces
          org_namespaces = k8s_client.list_namespaces(
            label_selector: 'langop.io/type=organization'
          )

          case org_namespaces.length
          when 0
            Formatters::ProgressFormatter.error('No organizations found in cluster')
            puts "\nRun 'langop organization list' to see available organizations."
            nil
          when 1
            org_id = org_namespaces.first.dig('metadata', 'labels', 'langop.io/organization-id')
            org_id
          else
            Formatters::ProgressFormatter.error('Multiple organizations found')
            puts "\nPlease specify which organization to use:"
            puts "  langop cluster create #{ARGV.last} --organization-id <ORG_ID>"
            puts
            puts "Available organizations:"
            list_org_namespaces(k8s_client)
            nil
          end
        end

        # Find the namespace for a given organization ID
        #
        # @param k8s_client [Kubernetes::Client] Kubernetes client
        # @param org_id [String] Organization ID
        # @return [String, nil] Namespace name or nil if not found
        def find_org_namespace(k8s_client, org_id)
          # List all namespaces with organization labels
          namespaces = k8s_client.list_namespaces(
            label_selector: "langop.io/organization-id=#{org_id}"
          )

          # Find the first namespace for this org ID
          org_namespace = namespaces.find do |ns|
            ns.dig('metadata', 'labels', 'langop.io/organization-id') == org_id
          end

          org_namespace&.dig('metadata', 'name')
        rescue StandardError => e
          warn "Warning: Could not find organization namespace: #{e.message}" if ENV['DEBUG']
          nil
        end

        # List available organization namespaces for error messages
        #
        # @param k8s_client [Kubernetes::Client] Kubernetes client
        def list_org_namespaces(k8s_client)
          namespaces = k8s_client.list_namespaces(
            label_selector: 'langop.io/type=organization'
          )

          if namespaces.any?
            namespaces.each do |ns|
              name = ns.dig('metadata', 'name')
              org_id = ns.dig('metadata', 'labels', 'langop.io/organization-id')
              plan = ns.dig('metadata', 'labels', 'langop.io/plan')
              puts "  • #{name} (#{org_id}) [#{plan}]"
            end
          else
            puts "  None found"
          end
        rescue StandardError => e
          puts "  Error listing namespaces: #{e.message}"
        end
      end
    end
  end
end
