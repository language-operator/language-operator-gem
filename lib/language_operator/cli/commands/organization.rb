# frozen_string_literal: true

require_relative '../base_command'
require_relative '../formatters/table_formatter'
require_relative '../formatters/progress_formatter'
require_relative '../../kubernetes/client'

module LanguageOperator
  module CLI
    module Commands
      # Organization management commands
      class Organization < BaseCommand
        desc 'list', 'List all organizations in the cluster'
        long_desc <<-DESC
          Lists all organizations present in the Kubernetes cluster.
          
          Organizations are identified by namespaces with the label:
          langop.io/type=organization

          Examples:
            # List all organizations
            langop organization list
        DESC
        def list
          handle_command_error('list organizations') do
            organizations_data = get_organizations_data
            Formatters::TableFormatter.organizations(organizations_data)
          end
        end

        private

        def get_organizations_data
          k8s = Kubernetes::Client.new
          
          # Find all namespaces with organization label
          namespaces = k8s.list_namespaces(
            label_selector: 'langop.io/type=organization'
          )

          namespaces.map do |namespace|
            {
              namespace: namespace.dig('metadata', 'name'),
              organization_id: namespace.dig('metadata', 'labels', 'langop.io/organization-id') || 'N/A',
              plan: namespace.dig('metadata', 'labels', 'langop.io/plan') || 'N/A',
              created: format_creation_date(namespace.dig('metadata', 'creationTimestamp'))
            }
          end
        end

        def format_creation_date(timestamp)
          return 'N/A' unless timestamp
          
          Time.parse(timestamp).strftime('%Y-%m-%d %H:%M')
        rescue StandardError
          'N/A'
        end
      end
    end
  end
end