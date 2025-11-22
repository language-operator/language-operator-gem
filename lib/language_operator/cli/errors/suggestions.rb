# frozen_string_literal: true

require 'did_you_mean'
require_relative '../helpers/ux_helper'

module LanguageOperator
  module CLI
    module Errors
      # Provides helpful suggestions for error recovery
      class Suggestions
        extend Helpers::UxHelper

        class << self
          # Find similar resource names using fuzzy matching
          def find_similar(input_name, available_names, limit: 3)
            return [] if available_names.empty?

            spell_checker = DidYouMean::SpellChecker.new(dictionary: available_names)
            corrections = spell_checker.correct(input_name)
            corrections.first(limit)
          end

          # Generate context-aware suggestions based on error type
          def for_error(error_type, context = {})
            case error_type
            when :agent_not_found
              agent_not_found_suggestions(context)
            when :tool_not_found
              tool_not_found_suggestions(context)
            when :model_not_found
              model_not_found_suggestions(context)
            when :persona_not_found
              persona_not_found_suggestions(context)
            when :cluster_not_found
              cluster_not_found_suggestions(context)
            when :no_cluster_selected
              no_cluster_selected_suggestions
            when :no_models_available
              no_models_available_suggestions(context)
            when :synthesis_failed
              synthesis_failed_suggestions
            when :already_exists
              already_exists_suggestions(context)
            else
              []
            end
          end

          private

          def agent_not_found_suggestions(context)
            suggestions = []
            suggestions << "List all agents: #{pastel.dim('aictl agent list')}"
            suggestions << "Create a new agent: #{pastel.dim('aictl agent create \"description\"')}"
            suggestions << "Use the wizard: #{pastel.dim('aictl agent create --wizard')}" if context[:suggest_wizard]
            suggestions
          end

          def tool_not_found_suggestions(context)
            suggestions = []
            tool_name = context[:tool_name]

            if tool_name
              suggestions << "Install from registry: #{pastel.dim("aictl tool install #{tool_name}")}"
              suggestions << "Search for tools: #{pastel.dim('aictl tool search')}"
            end

            suggestions << "List installed tools: #{pastel.dim('aictl tool list')}"
            suggestions
          end

          def model_not_found_suggestions(_context)
            suggestions = []
            suggestions << "List all models: #{pastel.dim('aictl model list')}"
            suggestions << "Create a new model: #{pastel.dim('aictl model create <name> --provider <provider>')}"
            suggestions
          end

          def persona_not_found_suggestions(_context)
            suggestions = []
            suggestions << "List all personas: #{pastel.dim('aictl persona list')}"
            suggestions << "Create a new persona: #{pastel.dim('aictl persona create <name>')}"
            suggestions
          end

          def cluster_not_found_suggestions(_context)
            suggestions = []
            suggestions << "List available clusters: #{pastel.dim('aictl cluster list')}"
            suggestions << "Create a new cluster: #{pastel.dim('aictl cluster create <name>')}"
            suggestions
          end

          def no_cluster_selected_suggestions
            [
              'Create a new cluster:',
              "  #{pastel.dim('aictl cluster create my-cluster')}",
              '',
              'Or select an existing cluster:',
              "  #{pastel.dim('aictl use my-cluster')}",
              '',
              'List available clusters:',
              "  #{pastel.dim('aictl cluster list')}"
            ]
          end

          def no_models_available_suggestions(context)
            cluster = context[:cluster]
            suggestions = []

            if cluster
              suggestions << "Create a model in cluster '#{cluster}':"
              suggestions << "  #{pastel.dim('aictl model create <name> --provider anthropic --model claude-3-5-sonnet')}"
            else
              suggestions << "Create a model: #{pastel.dim('aictl model create <name> --provider <provider>')}"
            end

            suggestions << ''
            suggestions << "List available models: #{pastel.dim('aictl model list')}"
            suggestions
          end

          def synthesis_failed_suggestions
            [
              'The description may be too vague. Try the interactive wizard:',
              "  #{pastel.dim('aictl agent create --wizard')}",
              '',
              'Or provide a more detailed description with:',
              '  • What the agent should do specifically',
              '  • When it should run (schedule)',
              '  • What tools or resources it needs',
              '',
              'Examples:',
              "  #{pastel.green('✓')} #{pastel.dim('\"Check my email every hour and notify me of urgent messages\"')}",
              "  #{pastel.green('✓')} #{pastel.dim('\"Review my spreadsheet at 4pm daily and email me errors\"')}",
              "  #{pastel.red('✗')} #{pastel.dim('\"do the thing\"')} (too vague)"
            ]
          end

          def already_exists_suggestions(context)
            resource_type = context[:resource_type]
            resource_name = context[:resource_name]

            suggestions = []

            if resource_name
              suggestions << "View existing #{resource_type}: #{pastel.dim("aictl #{command_for_resource(resource_type)} inspect #{resource_name}")}"
              suggestions << "Delete and recreate: #{pastel.dim("aictl #{command_for_resource(resource_type)} delete #{resource_name}")}"
            end

            suggestions << 'Choose a different name'
            suggestions
          end

          def command_for_resource(resource_type)
            case resource_type
            when 'LanguageAgent', 'agent'
              'agent'
            when 'LanguageTool', 'tool'
              'tool'
            when 'LanguageModel', 'model'
              'model'
            when 'LanguagePersona', 'persona'
              'persona'
            when 'cluster'
              'cluster'
            else
              resource_type.downcase
            end
          end
        end
      end
    end
  end
end
