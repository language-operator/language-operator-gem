# frozen_string_literal: true

require_relative '../helpers/ux_helper'
require_relative 'status_formatter'

module LanguageOperator
  module CLI
    module Formatters
      # Table output for CLI list commands
      class TableFormatter
        class << self
          include Helpers::UxHelper

          def clusters(clusters)
            return ProgressFormatter.info('No clusters found') if clusters.empty?

            headers = ['', 'NAME', 'NAMESPACE', 'ORGANIZATION', 'STATUS', 'DOMAIN']
            rows = clusters.map do |cluster|
              # Extract asterisk for selected cluster
              name = cluster[:name].to_s.gsub(' *', '')
              is_current = cluster[:name].to_s.include?(' *')

              # Apply bold yellow formatting if current cluster
              formatted_name = is_current ? pastel.bold.yellow(name) : name

              # Format domain - show empty cell if nil or empty, handle error states
              domain_display = case cluster[:domain]
                               when nil, ''
                                 ''
                               when '?', '-'
                                 cluster[:domain]
                               else
                                 cluster[:domain]
                               end

              # Format organization display
              org_display = cluster[:organization] || 'legacy'

              [
                StatusFormatter.dot(cluster[:status] || 'Unknown'),
                formatted_name,
                cluster[:namespace],
                org_display,
                cluster[:status] || 'Unknown',
                domain_display
              ]
            end

            puts table(headers, rows)
          end

          def agents(agents)
            return ProgressFormatter.info('No agents found') if agents.empty?

            headers = ['', 'NAME', 'NAMESPACE', 'STATUS', 'MODE']
            rows = agents.map do |agent|
              [
                StatusFormatter.dot(agent[:status]),
                agent[:name],
                agent[:namespace],
                agent[:status] || 'Unknown',
                agent[:mode]
              ]
            end

            puts table(headers, rows)
          end

          def all_agents(agents_by_cluster)
            return ProgressFormatter.info('No agents found across any cluster') if agents_by_cluster.empty?

            headers = ['CLUSTER', 'NAME', 'MODE', 'STATUS', 'NEXT RUN', 'EXECUTIONS']
            rows = []

            agents_by_cluster.each do |cluster_name, agents|
              agents.each do |agent|
                rows << [
                  cluster_name,
                  agent[:name],
                  agent[:mode],
                  StatusFormatter.format(agent[:status]),
                  agent[:next_run] || 'N/A',
                  agent[:executions] || 0
                ]
              end
            end

            puts table(headers, rows)
          end

          def tools(tools)
            return ProgressFormatter.info('No tools found') if tools.empty?

            headers = ['', 'NAME', 'NAMESPACE', 'STATUS']
            rows = tools.map do |tool|
              [
                StatusFormatter.dot(tool[:status]),
                tool[:name],
                tool[:namespace],
                tool[:status] || 'Unknown'
              ]
            end

            puts table(headers, rows)
          end

          def personas(personas)
            return ProgressFormatter.info('No personas found') if personas.empty?

            headers = ['NAME', 'TONE', 'USED BY', 'DESCRIPTION']
            rows = personas.map do |persona|
              [
                persona[:name],
                persona[:tone],
                persona[:used_by] || 0,
                truncate(persona[:description], 50)
              ]
            end

            puts table(headers, rows)
          end

          def models(models)
            return ProgressFormatter.info('No models found') if models.empty?

            headers = ['', 'NAME', 'NAMESPACE', 'STATUS', 'PROVIDER/MODEL']
            rows = models.map do |model|
              provider_model = "#{model[:provider]}/#{model[:model]}"

              [
                StatusFormatter.dot(model[:status]),
                model[:name],
                model[:namespace],
                model[:status] || 'Unknown',
                provider_model
              ]
            end

            puts table(headers, rows)
          end

          def status_dashboard(cluster_summary, current_cluster: nil)
            return ProgressFormatter.info('No clusters configured') if cluster_summary.empty?

            headers = %w[CLUSTER AGENTS TOOLS MODELS STATUS]
            rows = cluster_summary.map do |cluster|
              name = cluster[:name].to_s
              name += ' *' if current_cluster && cluster[:name] == current_cluster

              [
                name,
                cluster[:agents] || 0,
                cluster[:tools] || 0,
                cluster[:models] || 0,
                StatusFormatter.format(cluster[:status] || 'Unknown')
              ]
            end

            puts table(headers, rows)

            return unless current_cluster

            puts
            puts '* = current cluster'
          end

          private

          def truncate(text, length)
            return text if text.nil? || text.length <= length

            "#{text[0...(length - 3)]}..."
          end
        end
      end
    end
  end
end
