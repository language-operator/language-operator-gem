# frozen_string_literal: true

require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../../config/cluster_config'
require_relative '../helpers/cluster_validator'

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
            unless Config::ClusterConfig.cluster_exists?(cluster_name)
              Formatters::ProgressFormatter.error("Cluster '#{cluster_name}' not found")
              puts "\nAvailable clusters:"
              Config::ClusterConfig.list_clusters.each do |cluster|
                puts "  - #{cluster[:name]}"
              end
              exit 1
            end

            Config::ClusterConfig.set_current_cluster(cluster_name)
            cluster = Config::ClusterConfig.get_cluster(cluster_name)

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
      end
    end
  end
end
