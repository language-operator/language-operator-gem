# frozen_string_literal: true

require_relative '../command_loader'

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

              # Format cluster info using UxHelper
              logo(title: 'cluster status')
              
              if cluster_resource
                # Use actual cluster resource data
                status = cluster_resource.dig('status', 'phase') || 'Unknown'
                domain = cluster_resource.dig('spec', 'domain')
                created = cluster_resource.dig('metadata', 'creationTimestamp')
                
                format_cluster_details(
                  name: current_cluster,
                  namespace: cluster_config[:namespace],
                  context: cluster_config[:context],
                  status: status,
                  domain: domain,
                  created: created
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

              # Early exit if operator not installed
              unless k8s.operator_installed?
                puts
                puts 'Install the operator with:'
                puts '  aictl install'
                puts
                return
              end

              puts

              # Agent statistics
              agents = k8s.list_resources(RESOURCE_AGENT, namespace: cluster_config[:namespace])
              agent_stats = categorize_by_status(agents)
              agent_items = agent_stats.map { |status, count| "#{format_status(status)}: #{count}" }
              
              list_box(
                title: 'Agents',
                items: agent_items,
                empty_message: 'none',
                bullet: ''
              )

              puts

              # Tool statistics
              tools = k8s.list_resources('LanguageTool', namespace: cluster_config[:namespace])
              if tools.any?
                tool_types = tools.group_by { |t| t.dig('spec', 'type') }
                tool_items = tool_types.map { |type, items| "#{type}: #{items.count}" }
              else
                tool_items = []
              end
              
              list_box(
                title: 'Tools',
                items: tool_items,
                empty_message: 'none',
                bullet: ''
              )

              puts

              # Model statistics
              models = k8s.list_resources(RESOURCE_MODEL, namespace: cluster_config[:namespace])
              if models.any?
                model_providers = models.group_by { |m| m.dig('spec', 'provider') }
                model_items = model_providers.map { |provider, items| "#{provider}: #{items.count}" }
              else
                model_items = []
              end
              
              list_box(
                title: 'Models',
                items: model_items,
                empty_message: 'none',
                bullet: ''
              )

              puts

              # Persona statistics
              personas = k8s.list_resources('LanguagePersona', namespace: cluster_config[:namespace])
              if personas.any?
                persona_items = personas.map do |persona|
                  tone = persona.dig('spec', 'tone')
                  "#{persona.dig('metadata', 'name')} (#{tone})"
                end
              else
                persona_items = []
              end
              
              list_box(
                title: 'Personas',
                items: persona_items,
                empty_message: 'none',
                bullet: ''
              )
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
                puts '  aictl use <cluster>'
              else
                puts 'No clusters found. Create one with:'
                puts '  aictl cluster create <name>'
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
      end
    end
  end
end
