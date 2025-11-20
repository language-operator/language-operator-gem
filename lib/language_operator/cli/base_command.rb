# frozen_string_literal: true

require 'thor'

module LanguageOperator
  module CLI
    # Base class for all CLI commands providing shared functionality
    class BaseCommand < Thor
      no_commands do
        # Lazy-initialized cluster context from options
        # @return [Helpers::ClusterContext]
        def ctx
          @ctx ||= Helpers::ClusterContext.from_options(options)
        end

        # Handle command errors with consistent formatting
        # @param operation [String] Description of the operation for error message
        # @yield Block to execute with error handling
        def handle_command_error(operation)
          yield
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to #{operation}: #{e.message}")

          # Show backtrace for debugging
          if ENV['DEBUG']
            puts "\nBacktrace:"
            puts e.backtrace.join("\n")
            raise
          end

          exit 1
        end

        # Get a Kubernetes resource or exit with helpful error message
        # @param type [String] Resource type (e.g., 'LanguageAgent')
        # @param name [String] Resource name
        # @param error_message [String, nil] Custom error message (optional)
        # @return [Hash] The Kubernetes resource
        def get_resource_or_exit(type, name, error_message: nil)
          ctx.client.get_resource(type, name, ctx.namespace)
        rescue K8s::Error::NotFound => e
          # Try to provide helpful fuzzy matching suggestions
          resources = ctx.client.list_resources(type, namespace: ctx.namespace)
          available_names = resources.map { |r| r.dig('metadata', 'name') }

          msg = error_message || "#{type} '#{name}' not found in cluster '#{ctx.name}'"
          Errors::Handler.handle_not_found(
            e,
            resource_type: type,
            resource_name: name,
            available_names: available_names,
            cluster_name: ctx.name,
            custom_message: msg
          )
          exit 1
        end

        # Confirm resource deletion with user
        # @param resource_type [String] Type of resource being deleted
        # @param name [String] Resource name
        # @param cluster [String] Cluster name
        # @param details [Hash] Additional details to display
        # @param force [Boolean] Skip confirmation if true
        # @return [Boolean] True if deletion should proceed
        def confirm_deletion(resource_type, name, cluster, details: {}, force: false)
          return true if force

          puts "This will delete #{resource_type} '#{name}' from cluster '#{cluster}':"
          details.each { |key, value| puts "  #{key}: #{value}" }
          puts

          Helpers::UserPrompts.confirm('Are you sure?')
        end

        # Check if resource has dependencies and confirm deletion
        # @param resource_type [String] Type of resource (e.g., 'persona', 'model', 'tool')
        # @param resource_name [String] Name of the resource
        # @param force [Boolean] Skip dependency check if true
        # @return [Boolean] True if deletion should proceed
        def check_dependencies_and_confirm(resource_type, resource_name, force: false)
          agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)

          checker_method = "agents_using_#{resource_type}"
          agents_using = Helpers::ResourceDependencyChecker.send(checker_method, agents, resource_name)

          if agents_using.any? && !force
            Formatters::ProgressFormatter.warn(
              "#{resource_type.capitalize} '#{resource_name}' is in use by #{agents_using.count} agent(s)"
            )
            puts
            puts "Agents using this #{resource_type}:"
            agents_using.each { |agent| puts "  - #{agent.dig('metadata', 'name')}" }
            puts
            puts 'Delete these agents first, or use --force to delete anyway.'
            puts

            return Helpers::UserPrompts.confirm('Are you sure?')
          end

          true
        end

        # List resources or handle empty state
        # @param type [String] Resource type (e.g., 'LanguageModel')
        # @param empty_message [String, nil] Custom message when no resources found
        # @yield Optional block to execute when list is empty (for guidance)
        # @return [Array<Hash>] List of resources (empty array if none found)
        def list_resources_or_empty(type, empty_message: nil)
          resources = ctx.client.list_resources(type, namespace: ctx.namespace)

          if resources.empty?
            msg = empty_message || "No #{type} resources found in cluster '#{ctx.name}'"
            Formatters::ProgressFormatter.info(msg)
            yield if block_given?
          end

          resources
        end
      end
      # rubocop:enable Metrics/BlockLength
    end
  end
end
