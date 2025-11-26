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
        option :namespace, type: :string, desc: 'Kubernetes namespace (defaults to current context namespace)'
        option :kubeconfig, type: :string, desc: 'Path to kubeconfig file'
        option :context, type: :string, desc: 'Kubernetes context to use'
        option :switch, type: :boolean, default: true, desc: 'Switch to new cluster context'
        option :dry_run, type: :boolean, default: false, desc: 'Output the manifest without creating'
        option :domain, type: :string, desc: 'Base domain for webhook routing (e.g., example.com)'
        def create(name)
          handle_command_error('create cluster') do
            kubeconfig = options[:kubeconfig]
            context = options[:context]

            # Handle dry-run: output manifest and exit early
            if options[:dry_run]
              namespace = options[:namespace] || 'default'
              resource = Kubernetes::ResourceBuilder.language_cluster(name, namespace: namespace, domain: options[:domain])
              puts resource.to_yaml
              return
            end

            # Check if cluster already exists
            if Config::ClusterConfig.cluster_exists?(name)
              Formatters::ProgressFormatter.error("Cluster '#{name}' already exists")
              exit 1
            end

            # Create Kubernetes client
            k8s = Formatters::ProgressFormatter.with_spinner('Connecting to Kubernetes cluster') do
              Kubernetes::Client.new(kubeconfig: kubeconfig, context: context)
            end

            # Determine namespace: use --namespace flag, or current context namespace, or 'default'
            namespace = options[:namespace] || k8s.current_namespace || 'default'

            # Check if operator is installed
            unless k8s.operator_installed?
              Formatters::ProgressFormatter.error('Language Operator not found in cluster')
              puts "\nInstall the operator first:"
              puts '  aictl install'
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
              resource = Kubernetes::ResourceBuilder.language_cluster(name, namespace: namespace, domain: options[:domain])
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
              status: 'Ready',
              created: Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')
            )

            # Show usage instructions if not auto-switched
            unless options[:switch]
              puts
              puts 'Switch to this cluster with:'
              puts pastel.dim("  aictl use #{name}")
            end
          end
        end

        desc 'list', 'List all clusters'
        option :all, type: :boolean, default: false, desc: 'Show all clusters including inactive'
        def list
          handle_command_error('list clusters') do
            clusters = Config::ClusterConfig.list_clusters
            current = Config::ClusterConfig.current_cluster

            if clusters.empty?
              Formatters::ProgressFormatter.info('No clusters found')
              puts "\nCreate a cluster with:"
              puts '  aictl cluster create <name>'
              return
            end

            # Cache clients by kubeconfig:context to prevent resource leaks
            clients_cache = {}

            # Build table data
            table_data = clusters.map do |cluster|
              begin
                # Get cluster config for cache key and reuse clients
                cluster_config = Config::ClusterConfig.get_cluster(cluster[:name])
                cache_key = "#{cluster_config[:kubeconfig]}:#{cluster_config[:context]}"

                # Reuse existing client or create new one
                k8s = clients_cache[cache_key] ||= begin
                  # Validate kubeconfig exists before creating client
                  Helpers::ClusterValidator.validate_kubeconfig!(cluster_config)
                  require_relative '../../kubernetes/client'
                  Kubernetes::Client.new(
                    kubeconfig: cluster_config[:kubeconfig],
                    context: cluster_config[:context]
                  )
                end
              rescue StandardError
                # Handle cluster config or client creation errors
                name_display = cluster[:name]
                name_display += ' *' if cluster[:name] == current

                next {
                  name: name_display,
                  namespace: cluster[:namespace],
                  agents: '?',
                  tools: '?',
                  models: '?',
                  status: 'Config Error',
                  domain: '?'
                }
              end

              # Get cluster stats
              agents = k8s.list_resources(RESOURCE_AGENT, namespace: cluster[:namespace])
              tools = k8s.list_resources(RESOURCE_TOOL, namespace: cluster[:namespace])
              models = k8s.list_resources(RESOURCE_MODEL, namespace: cluster[:namespace])

              # Get cluster status and domain
              cluster_resource = k8s.get_resource('LanguageCluster', cluster[:name], cluster[:namespace])
              status = cluster_resource.dig('status', 'phase') || 'Unknown'
              domain = cluster_resource.dig('spec', 'domain')

              name_display = cluster[:name]
              name_display = "#{pastel.bold(cluster[:name])} (selected)" if cluster[:name] == current

              {
                name: name_display,
                namespace: cluster[:namespace],
                agents: agents.count,
                tools: tools.count,
                models: models.count,
                status: status,
                domain: domain
              }
            rescue K8s::Error::NotFound
              # Cluster exists in local config but not in Kubernetes
              name_display = cluster[:name]
              name_display += ' *' if cluster[:name] == current

              {
                name: name_display,
                namespace: cluster[:namespace],
                agents: '-',
                tools: '-',
                models: '-',
                status: 'Not Found',
                domain: '-'
              }
            rescue StandardError
              # Other errors (connection issues, auth problems, etc.)
              name_display = cluster[:name]
              name_display += ' *' if cluster[:name] == current

              {
                name: name_display,
                namespace: cluster[:namespace],
                agents: '?',
                tools: '?',
                models: '?',
                status: 'Error',
                domain: '?'
              }
            end

            Formatters::TableFormatter.clusters(table_data)

            puts "\nNo cluster selected. Use 'aictl use <cluster>' to select one." unless current

            # Show helpful message if any clusters are not found
            not_found_clusters = table_data.select { |c| c[:status] == 'Not Found' }
            if not_found_clusters.any?
              puts
              Formatters::ProgressFormatter.warn('Some clusters exist in local config but not in Kubernetes')
              puts
              puts 'Clusters with "Not Found" status are defined in ~/.aictl/config.yaml'
              puts 'but the corresponding LanguageCluster resource does not exist in Kubernetes.'
              puts
              puts 'To fix this:'
              not_found_clusters.each do |cluster|
                cluster_name = cluster[:name].gsub(' *', '')
                puts "  • Remove from config:  aictl cluster delete #{cluster_name}"
                puts "  • Or recreate:         aictl cluster create #{cluster_name}"
              end
            end
          end
        end

        desc 'current', 'Show current cluster context'
        def current
          handle_command_error('show current cluster') do
            cluster_name = Config::ClusterConfig.current_cluster

            unless cluster_name
              Formatters::ProgressFormatter.info('No cluster selected')
              puts "\nSelect a cluster with:"
              puts '  aictl use <cluster>'
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
                puts pastel.dim("  aictl cluster delete #{name} --force-local")
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
      end
    end
  end
end
