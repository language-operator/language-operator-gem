# frozen_string_literal: true

require_relative '../formatters/progress_formatter'
require_relative '../errors/handler'
require_relative 'kubeconfig_validator'
require_relative '../../config/cluster_config'

module LanguageOperator
  module CLI
    module Helpers
      # Validates that a cluster is selected before executing commands
      module ClusterValidator
        class << self
          # Ensure a cluster is selected, exit with helpful message if not
          def ensure_cluster_selected!
            return current_cluster if current_cluster

            Errors::Handler.handle_no_cluster_selected
          end

          # Get current cluster, or allow override via --cluster flag
          def get_cluster(cluster_override = nil)
            if cluster_override
              validate_cluster_exists!(cluster_override)
              cluster_override
            else
              ensure_cluster_selected!
            end
          end

          # Validate that a specific cluster exists
          def validate_cluster_exists!(name)
            return if Config::ClusterConfig.cluster_exists?(name)

            # Build context with available clusters for fuzzy matching
            clusters = Config::ClusterConfig.list_clusters
            available_names = clusters.map { |c| c[:name] }

            # Use error handler with fuzzy matching
            error = K8s::Error::NotFound.new(404, 'Not Found', 'cluster')
            Errors::Handler.handle_not_found(error,
                                             resource_type: 'cluster',
                                             resource_name: name,
                                             available_resources: available_names)
          end

          # Get current cluster name
          def current_cluster
            Config::ClusterConfig.current_cluster
          end

          # Get current cluster config
          def current_cluster_config
            cluster_name = ensure_cluster_selected!
            Config::ClusterConfig.get_cluster(cluster_name)
          end

          # Get cluster config by name (with validation)
          def get_cluster_config(name)
            validate_cluster_exists!(name)
            config = Config::ClusterConfig.get_cluster(name)

            # Validate kubeconfig exists and is accessible
            validate_kubeconfig!(config)

            config
          end

          # Validate kubeconfig for the given cluster config
          def validate_kubeconfig!(cluster_config)
            # Check if kubeconfig file exists
            kubeconfig_path = cluster_config[:kubeconfig]
            return if kubeconfig_path && File.exist?(kubeconfig_path)

            Formatters::ProgressFormatter.error("Kubeconfig not found: #{kubeconfig_path}")
            puts
            puts 'The kubeconfig file for this cluster does not exist.'
            puts
            puts 'To fix this issue:'
            puts '  1. Verify the kubeconfig path in ~/.aictl/config.yaml'
            puts '  2. Re-create the cluster configuration:'
            puts "     aictl cluster create #{cluster_config[:name]}"
            exit 1
          end

          # Create a Kubernetes client for the given cluster
          def kubernetes_client(cluster_override = nil)
            cluster = get_cluster(cluster_override)
            cluster_config = get_cluster_config(cluster)

            require_relative '../../kubernetes/client'
            Kubernetes::Client.new(
              kubeconfig: cluster_config[:kubeconfig],
              context: cluster_config[:context]
            )
          end
        end
      end
    end
  end
end
