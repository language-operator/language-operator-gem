# frozen_string_literal: true

# CommandLoader - Single require point for all CLI commands
#
# This module eliminates duplication across command files by auto-loading
# all common formatters, helpers, and dependencies.
#
# Before CommandLoader, each command file had 15+ duplicate require statements.
# Now commands just need: require_relative '../command_loader'
#
# Usage in command files:
#   require_relative '../command_loader'
#   require_relative '../wizards/my_wizard'  # command-specific requires only
#
#   class MyCommand < BaseCommand
#     include Constants  # For RESOURCE_* constants
#
#     def some_method
#       ctx.client.get_resource(RESOURCE_AGENT, name, ctx.namespace)
#     end
#   end

module LanguageOperator
  module CLI
    module CommandLoader
      # Auto-load all common CLI dependencies
      # This runs once when the module is first required
      def self.setup
        # Core base class (must load first)
        require_relative 'base_command'

        # Constants for resource types
        require_relative '../constants'

        # Formatters - visual output and progress indicators
        require_relative 'formatters/progress_formatter'
        require_relative 'formatters/table_formatter'
        require_relative 'formatters/value_formatter'
        require_relative 'formatters/log_formatter'
        require_relative 'formatters/status_formatter'
        require_relative 'formatters/code_formatter'
        require_relative 'formatters/log_style'
        # require_relative 'formatters/optimization_formatter'

        # Helpers - shared utilities and validations
        require_relative 'helpers/cluster_validator'
        require_relative 'helpers/cluster_context'
        require_relative 'helpers/user_prompts'
        require_relative 'helpers/editor_helper'
        require_relative 'helpers/resource_dependency_checker'
        require_relative 'helpers/ux_helper'
        require_relative 'helpers/validation_helper'
        require_relative 'helpers/provider_helper'
        require_relative 'helpers/schedule_builder'
        require_relative 'helpers/kubeconfig_validator'

        # Error handling
        require_relative 'errors/handler'
        require_relative 'errors/suggestions'

        # Configuration and Kubernetes clients
        require_relative '../config/cluster_config'
        require_relative '../config/tool_registry'
        require_relative '../kubernetes/client'
        require_relative '../kubernetes/resource_builder'
      end
    end
  end
end

# Auto-setup when this file is required
LanguageOperator::CLI::CommandLoader.setup
