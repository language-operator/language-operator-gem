# frozen_string_literal: true

require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../../config/cluster_config'
require_relative '../helpers/cluster_validator'
require_relative '../../utils/secure_path'

module LanguageOperator
  module CLI
    module Commands
      # Switch cluster context command
      class Use < BaseCommand
        include Helpers::UxHelper

        desc 'use CLUSTER', 'Switch to a different cluster context'
        def self.exit_on_failure?
          true
        end

        def switch(cluster_name)
          handle_command_error('switch cluster') do
            # First check if cluster exists in local config
            if Config::ClusterConfig.cluster_exists?(cluster_name)
              Config::ClusterConfig.set_current_cluster(cluster_name)
              cluster = Config::ClusterConfig.get_cluster(cluster_name)
            else
              # If not in local config, check if it exists in Kubernetes
              k8s_cluster = find_cluster_in_kubernetes(cluster_name)
              
              if k8s_cluster
                # Auto-import the cluster to local config with current kubectl context
                import_cluster_to_config(k8s_cluster)
                Config::ClusterConfig.set_current_cluster(cluster_name)
                cluster = Config::ClusterConfig.get_cluster(cluster_name)
              else
                show_cluster_not_found_error(cluster_name)
                exit 1
              end
            end

            Formatters::ProgressFormatter.success("Switched to cluster '#{cluster_name}'")

            # Get cluster details from Kubernetes for complete information
            begin
              k8s = Helpers::ClusterValidator.kubernetes_client(cluster_name)
              cluster_resource = k8s.get_resource('LanguageCluster', cluster[:name], cluster[:namespace])
              status = cluster_resource.dig('status', 'phase') || 'Unknown'
              domain = cluster_resource.dig('spec', 'domain')

              puts
              format_cluster_details(
                name: cluster[:name],
                namespace: cluster[:namespace],
                context: cluster[:context] || 'default',
                domain: domain,
                status: status,
                created: cluster[:created]
              )
            rescue StandardError
              # Fallback to basic display if K8s access fails
              puts
              format_cluster_details(
                name: cluster[:name],
                namespace: cluster[:namespace],
                context: cluster[:context] || 'default',
                status: 'Connection Error'
              )
            end
          end
        end

        private

        def find_cluster_in_kubernetes(cluster_name)
          require_relative '../../kubernetes/client'
          
          k8s = Kubernetes::Client.new
          language_clusters = k8s.list_resources('LanguageCluster', namespace: nil)
          
          language_clusters.find { |cluster| cluster.dig('metadata', 'name') == cluster_name }
        rescue StandardError => e
          # If we can't query Kubernetes, return nil
          warn "Warning: Could not query Kubernetes: #{e.message}" if ENV['DEBUG']
          nil
        end

        def import_cluster_to_config(k8s_cluster)
          name = k8s_cluster.dig('metadata', 'name')
          namespace = k8s_cluster.dig('metadata', 'namespace')
          
          # Use current kubectl context and config
          kubeconfig = ENV.fetch('KUBECONFIG', LanguageOperator::Utils::SecurePath.expand_home_path('.kube/config'))
          
          require_relative '../../kubernetes/client'
          k8s_client = Kubernetes::Client.new
          current_context = k8s_client.current_context
          
          
          Config::ClusterConfig.add_cluster(
            name,
            namespace,
            kubeconfig,
            current_context
          )
        end

        def show_cluster_not_found_error(cluster_name)
          Formatters::ProgressFormatter.error("Cluster '#{cluster_name}' not found")
          
          # Show clusters from both local config and Kubernetes
          local_clusters = Config::ClusterConfig.list_clusters
          
          require_relative '../../kubernetes/client'
          begin
            k8s = Kubernetes::Client.new
            k8s_clusters = k8s.list_resources('LanguageCluster', namespace: nil)
            k8s_cluster_names = k8s_clusters.map { |c| c.dig('metadata', 'name') }
          rescue StandardError
            k8s_cluster_names = []
          end
          
          all_cluster_names = (local_clusters.map { |c| c[:name] } + k8s_cluster_names).uniq
          
          if all_cluster_names.any?
            puts "\nAvailable clusters:"
            all_cluster_names.each do |name|
              puts "  - #{name}"
            end
          else
            puts "\nNo clusters found. Create one with:"
            puts "  langop cluster create <name>"
          end
        end
      end
    end
  end
end
