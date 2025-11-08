# frozen_string_literal: true

require 'pastel'
require_relative 'suggestions'
require_relative '../formatters/progress_formatter'

module LanguageOperator
  module CLI
    module Errors
      # Central error handler with context-aware suggestions
      class Handler
        class << self
          # Handle an error with context and provide helpful suggestions
          def handle(error, context = {})
            case error
            when K8s::Error::NotFound
              handle_not_found(error, context)
            else
              handle_generic(error, context)
            end
          end

          # Handle resource not found errors with fuzzy matching
          def handle_not_found(error, context)
            resource_type = context[:resource_type] || 'Resource'
            resource_name = context[:resource_name] || 'unknown'
            cluster = context[:cluster]

            # Display main error message
            message = if cluster
                        "#{format_resource_type(resource_type)} '#{resource_name}' not found in cluster '#{cluster}'"
                      else
                        "#{format_resource_type(resource_type)} '#{resource_name}' not found"
                      end

            Formatters::ProgressFormatter.error(message)
            puts

            # Find and display similar resources
            if context[:available_resources]
              similar = Suggestions.find_similar(resource_name, context[:available_resources])
              if similar.any?
                puts pastel.yellow('Did you mean?')
                similar.each { |name| puts "  #{pastel.cyan('•')} #{name}" }
                puts
              end
            end

            # Display recovery suggestions
            error_type = error_type_for_resource(resource_type)
            suggestions = Suggestions.for_error(error_type, context)
            display_suggestions(suggestions) if suggestions.any?

            # Re-raise if in debug mode, otherwise exit
            raise error if ENV['DEBUG']

            exit 1
          end

          # Handle generic errors
          def handle_generic(error, context)
            operation = context[:operation] || 'operation'

            Formatters::ProgressFormatter.error("Failed to #{operation}: #{error.message}")
            puts

            # Display suggestions if provided in context
            display_suggestions(context[:suggestions]) if context[:suggestions]

            # Re-raise if in debug mode, otherwise exit
            raise error if ENV['DEBUG']

            exit 1
          end

          # Handle specific error scenarios with custom suggestions
          def handle_no_cluster_selected
            Formatters::ProgressFormatter.error('No cluster selected')
            puts

            puts 'You must connect to a cluster first:'
            puts

            suggestions = Suggestions.for_error(:no_cluster_selected)
            suggestions.each { |line| puts line }

            exit 1
          end

          def handle_no_models_available(context = {})
            Formatters::ProgressFormatter.error('No models found in cluster')
            puts

            suggestions = Suggestions.for_error(:no_models_available, context)
            suggestions.each { |line| puts line }

            exit 1
          end

          def handle_synthesis_failed(message)
            Formatters::ProgressFormatter.error("Synthesis failed: #{message}")
            puts

            suggestions = Suggestions.for_error(:synthesis_failed)
            suggestions.each { |line| puts line }

            exit 1
          end

          def handle_already_exists(context = {})
            resource_type = context[:resource_type] || 'Resource'
            resource_name = context[:resource_name] || 'unknown'
            cluster = context[:cluster]

            message = if cluster
                        "#{format_resource_type(resource_type)} '#{resource_name}' already exists in cluster '#{cluster}'"
                      else
                        "#{format_resource_type(resource_type)} '#{resource_name}' already exists"
                      end

            Formatters::ProgressFormatter.error(message)
            puts

            suggestions = Suggestions.for_error(:already_exists, context)
            display_suggestions(suggestions) if suggestions.any?

            exit 1
          end

          private

          def display_suggestions(suggestions)
            return if suggestions.empty?

            suggestions.each do |suggestion|
              puts suggestion
            end
            puts
          end

          def format_resource_type(resource_type)
            case resource_type
            when 'LanguageAgent'
              'Agent'
            when 'LanguageTool'
              'Tool'
            when 'LanguageModel'
              'Model'
            when 'LanguagePersona'
              'Persona'
            else
              resource_type
            end
          end

          def error_type_for_resource(resource_type)
            case resource_type
            when 'LanguageAgent', 'agent'
              :agent_not_found
            when 'LanguageTool', 'tool'
              :tool_not_found
            when 'LanguageModel', 'model'
              :model_not_found
            when 'LanguagePersona', 'persona'
              :persona_not_found
            when 'cluster'
              :cluster_not_found
            else
              :resource_not_found
            end
          end

          def pastel
            @pastel ||= Pastel.new
          end
        end
      end
    end
  end
end
