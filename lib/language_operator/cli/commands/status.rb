# frozen_string_literal: true

require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../formatters/table_formatter'
require_relative '../formatters/status_formatter'
require_relative '../helpers/pastel_helper'
require_relative '../../config/cluster_config'
require_relative '../../kubernetes/client'
require_relative '../helpers/cluster_validator'

module LanguageOperator
  module CLI
    module Commands
      # System status and overview command
      class Status < BaseCommand
        include Helpers::UxHelper

        desc 'overview', 'Show system status and overview'
        def overview
          handle_command_error('retrieve cluster status') do
            current_cluster = Config::ClusterConfig.current_cluster
            clusters = Config::ClusterConfig.list_clusters

            # Current cluster context
            if current_cluster
              cluster_config = Config::ClusterConfig.get_cluster(current_cluster)

              puts "\nCluster Details"
              puts '----------------'
              puts "Name: #{pastel.bold.white(current_cluster)}"
              puts "Namespace: #{pastel.bold.white(cluster_config[:namespace])}"
              puts

              # Check cluster health
              k8s = Helpers::ClusterValidator.kubernetes_client(current_cluster)

              # Operator status
              if k8s.operator_installed?
                version = k8s.operator_version || 'installed'
                Formatters::ProgressFormatter.success("Operator: #{version}")
              else
                Formatters::ProgressFormatter.error('Operator: not installed')
                puts
                puts 'Install the operator with:'
                puts '  aictl install'
                puts
                return
              end

              # Agent statistics
              agents = k8s.list_resources('LanguageAgent', namespace: cluster_config[:namespace])
              agent_stats = categorize_by_status(agents)

              puts
              puts "Agents (#{agents.count} total):"
              agent_stats.each do |status, count|
                puts "  #{format_status(status)}: #{count}"
              end

              # Tool statistics
              tools = k8s.list_resources('LanguageTool', namespace: cluster_config[:namespace])
              puts
              puts "Tools (#{tools.count} total):"
              if tools.any?
                tool_types = tools.group_by { |t| t.dig('spec', 'type') }
                tool_types.each do |type, items|
                  puts "  #{type}: #{items.count}"
                end
              else
                puts '  (none)'
              end

              # Model statistics
              models = k8s.list_resources('LanguageModel', namespace: cluster_config[:namespace])
              puts
              puts "Models (#{models.count} total):"
              if models.any?
                model_providers = models.group_by { |m| m.dig('spec', 'provider') }
                model_providers.each do |provider, items|
                  puts "  #{provider}: #{items.count}"
                end
              else
                puts '  (none)'
              end

              # Persona statistics
              personas = k8s.list_resources('LanguagePersona', namespace: cluster_config[:namespace])
              puts
              puts "Personas (#{personas.count} total):"
              if personas.any?
                personas.each do |persona|
                  tone = persona.dig('spec', 'tone')
                  puts "  - #{persona.dig('metadata', 'name')} (#{tone})"
                end
              else
                puts '  (none)'
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
