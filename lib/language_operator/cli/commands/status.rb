# frozen_string_literal: true

require_relative '../command_loader'
require_relative '../helpers/health_checker'

module LanguageOperator
  module CLI
    module Commands
      # System status and overview command
      class Status < BaseCommand
        include Constants
        include Helpers::UxHelper

        desc 'overview', 'Show system status and overview'
        def overview
          handle_command_error('retrieve cluster status') do
            current_cluster = Config::ClusterConfig.current_cluster
            clusters = Config::ClusterConfig.list_clusters

            # Current cluster context
            if current_cluster
              cluster_config = Config::ClusterConfig.get_cluster(current_cluster)

              # Check cluster health
              k8s = Helpers::ClusterValidator.kubernetes_client(current_cluster)

              # Try to get actual cluster resource from Kubernetes
              cluster_resource = nil
              if k8s.operator_installed?
                begin
                  cluster_resource = k8s.get_resource('LanguageCluster', current_cluster, cluster_config[:namespace])
                rescue StandardError
                  # Cluster resource might not exist yet
                end
              end

              # Early exit if operator not installed
              unless k8s.operator_installed?
                logo(title: 'cluster status')
                puts
                puts 'Install the operator with:'
                puts '  langop install'
                puts
                return
              end

              # Run health checks first
              logo(title: 'cluster status')
              begin
                # Use 'language-operator' namespace for system components, not the cluster namespace
                health_checker = Helpers::HealthChecker.new(k8s, 'language-operator', current_cluster, cluster_config[:namespace])
                health_results = health_checker.run_all_checks

                # Display any health check failures
                display_health_summary(health_results)
              rescue StandardError => e
                Formatters::ProgressFormatter.error("Health check failed: #{e.message}")
                puts e.backtrace.first(3).join("\n") if ENV['DEBUG']
              end

              # Then show cluster details
              puts

              if cluster_resource
                # Use actual cluster resource data
                status = cluster_resource.dig('status', 'phase') || 'Unknown'
                domain = cluster_resource.dig('spec', 'domain')
                created = cluster_resource.dig('metadata', 'creationTimestamp')
                org_id = cluster_resource.dig('metadata', 'labels', 'langop.io/organization-id')

                format_cluster_details(
                  name: current_cluster,
                  namespace: cluster_config[:namespace],
                  context: cluster_config[:context],
                  status: status,
                  domain: domain,
                  created: created,
                  org_id: org_id
                )
              else
                # Fallback to local config and operator status
                format_cluster_details(
                  name: current_cluster,
                  namespace: cluster_config[:namespace],
                  context: cluster_config[:context],
                  status: k8s.operator_installed? ? (k8s.operator_version || 'installed') : 'operator not installed'
                )
              end

            else
              Formatters::ProgressFormatter.warn('No cluster selected')
              puts
              if clusters.any?
                puts 'Available clusters:'
                clusters.each do |cluster|
                  puts "  - #{cluster[:name]}"
                end
                puts
                puts 'Select a cluster with:'
                puts '  langop use <cluster>'
              else
                puts 'No clusters found. Create one with:'
                puts '  langop cluster create <name>'
              end
            end

            puts
          end
        end

        default_task :overview

        private

        def format_status(status)
          Formatters::StatusFormatter.format(status)
        end

        def categorize_by_status(resources)
          stats = Hash.new(0)
          resources.each do |resource|
            status = resource.dig('status', 'phase') || 'Unknown'
            stats[status] += 1
          end
          stats
        end

        def display_health_summary(results)
          # Show any health issues
          issues = []

          results.each do |component, result|
            next if result[:healthy]

            case component
            when :cluster
              if result[:error]
                issues << "Cluster: #{result[:error]}"
              else
                issues << "Cluster: unexpected issue"
              end
            when :dashboard
              if result[:error]
                issues << "Dashboard: #{result[:error]}"
              else
                issues << "Dashboard: #{result[:ready_replicas]}/#{result[:desired_replicas]} pods ready"
              end
            when :operator
              if result[:error]
                issues << "Operator: #{result[:error]}"
              else
                issues << "Operator: #{result[:ready_replicas]}/#{result[:desired_replicas]} pods ready"
              end
            when :clickhouse
              if result[:error]
                issues << "ClickHouse: #{result[:error]}"
              else
                auth_status = result[:auth_works] ? 'auth OK' : 'auth failed'
                issues << "ClickHouse: connection failed (#{auth_status})"
              end
            when :postgres
              if result[:error]
                issues << "PostgreSQL: #{result[:error]}"
              else
                auth_status = result[:auth_works] ? 'auth OK' : 'auth failed'
                issues << "PostgreSQL: connection failed (#{auth_status})"
              end
            end
          end

          if issues.any?
            puts
            Formatters::ProgressFormatter.warn('Health check issues detected:')
            issues.each do |issue|
              puts "  • #{issue}"
            end
          end
        end
      end
    end
  end
end
