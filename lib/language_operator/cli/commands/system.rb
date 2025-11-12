# frozen_string_literal: true

require 'thor'
require 'json'
require 'yaml'
require_relative '../formatters/progress_formatter'
require_relative '../../dsl/schema'

module LanguageOperator
  module CLI
    module Commands
      # System commands for schema introspection and metadata
      class System < Thor
        desc 'schema', 'Export the DSL schema in various formats'
        long_desc <<-DESC
          Export the Language Operator Agent DSL schema in various formats.

          The schema documents all available DSL methods, parameters, validation
          patterns, and structure. Useful for template validation, documentation
          generation, and IDE autocomplete.

          Examples:
            # Export JSON schema (default)
            aictl system schema

            # Export as YAML
            aictl system schema --format yaml

            # Export OpenAPI 3.0 specification
            aictl system schema --format openapi

            # Show schema version only
            aictl system schema --version

            # Save to file
            aictl system schema > schema.json
            aictl system schema --format openapi > openapi.json
        DESC
        option :format, type: :string, default: 'json', desc: 'Output format (json, yaml, openapi)'
        option :version, type: :boolean, default: false, desc: 'Show schema version only'
        def schema
          # Handle version flag
          if options[:version]
            puts Dsl::Schema.version
            return
          end

          # Generate schema based on format
          format = options[:format].downcase
          case format
          when 'json'
            output_json_schema
          when 'yaml'
            output_yaml_schema
          when 'openapi'
            output_openapi_schema
          else
            Formatters::ProgressFormatter.error("Invalid format: #{format}")
            puts
            puts 'Supported formats: json, yaml, openapi'
            exit 1
          end
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to generate schema: #{e.message}")
          exit 1
        end

        no_commands do
          # Output JSON Schema v7
          def output_json_schema
            schema = Dsl::Schema.to_json_schema
            puts JSON.pretty_generate(schema)
          end

          # Output YAML Schema
          def output_yaml_schema
            schema = Dsl::Schema.to_json_schema
            puts YAML.dump(schema.transform_keys(&:to_s))
          end

          # Output OpenAPI 3.0 specification
          def output_openapi_schema
            spec = Dsl::Schema.to_openapi
            puts JSON.pretty_generate(spec)
          end
        end

        desc 'synthesis-template', 'Export synthesis templates for agent code generation'
        long_desc <<-DESC
          Export the synthesis templates used by the Language Operator to generate
          agent code from natural language instructions.

          These templates are used by the operator's synthesis engine to convert
          user instructions into executable Ruby DSL code.

          Examples:
            # Export agent synthesis template (default)
            aictl system synthesis-template

            # Export persona distillation template
            aictl system synthesis-template --type persona

            # Export as JSON with schema included
            aictl system synthesis-template --format json --with-schema

            # Export as YAML
            aictl system synthesis-template --format yaml

            # Validate template syntax
            aictl system synthesis-template --validate

            # Save to file
            aictl system synthesis-template > agent_synthesis.tmpl
        DESC
        option :format, type: :string, default: 'template', desc: 'Output format (template, json, yaml)'
        option :type, type: :string, default: 'agent', desc: 'Template type (agent, persona)'
        option :with_schema, type: :boolean, default: false, desc: 'Include DSL schema in output'
        option :validate, type: :boolean, default: false, desc: 'Validate template syntax'
        def synthesis_template
          # Validate type
          template_type = options[:type].downcase
          unless %w[agent persona].include?(template_type)
            Formatters::ProgressFormatter.error("Invalid template type: #{template_type}")
            puts
            puts 'Supported types: agent, persona'
            exit 1
          end

          # Load template
          template_content = load_template(template_type)

          # Validate if requested
          if options[:validate]
            validation_result = validate_template(template_content, template_type)
            if validation_result[:valid]
              Formatters::ProgressFormatter.success('Template validation passed')
              return
            else
              Formatters::ProgressFormatter.error('Template validation failed:')
              validation_result[:errors].each do |error|
                puts "  - #{error}"
              end
              exit 1
            end
          end

          # Generate output based on format
          format = options[:format].downcase
          case format
          when 'template'
            output_template_format(template_content)
          when 'json'
            output_json_format(template_content, template_type)
          when 'yaml'
            output_yaml_format(template_content, template_type)
          else
            Formatters::ProgressFormatter.error("Invalid format: #{format}")
            puts
            puts 'Supported formats: template, json, yaml'
            exit 1
          end
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to load template: #{e.message}")
          exit 1
        end

        private

        # Load template from bundled gem or operator ConfigMap
        def load_template(type)
          # Try to fetch from operator ConfigMap first (if kubectl available)
          template = fetch_from_operator(type)
          return template if template

          # Fall back to bundled template
          load_bundled_template(type)
        end

        # Fetch template from operator ConfigMap via kubectl
        def fetch_from_operator(type)
          configmap_name = type == 'agent' ? 'agent-synthesis-template' : 'persona-distillation-template'
          result = `kubectl get configmap #{configmap_name} -n language-operator-system -o jsonpath='{.data.template}' 2>/dev/null`
          result.empty? ? nil : result
        rescue StandardError
          nil
        end

        # Load bundled template from gem
        def load_bundled_template(type)
          filename = type == 'agent' ? 'agent_synthesis.tmpl' : 'persona_distillation.tmpl'
          template_path = File.join(__dir__, '..', '..', 'templates', filename)
          File.read(template_path)
        end

        # Validate template syntax and structure
        def validate_template(content, type)
          errors = []

          # Check for required placeholders based on type
          required_placeholders = if type == 'agent'
                                    %w[
                                      Instructions ToolsList ModelsList AgentName TemporalIntent
                                    ]
                                  else
                                    %w[
                                      PersonaName PersonaDescription PersonaSystemPrompt
                                      AgentInstructions AgentTools
                                    ]
                                  end

          required_placeholders.each do |placeholder|
            errors << "Missing required placeholder: {{.#{placeholder}}}" unless content.include?("{{.#{placeholder}}}")
          end

          # Check for balanced braces
          open_braces = content.scan(/{{/).count
          close_braces = content.scan(/}}/).count
          errors << "Unbalanced template braces ({{ vs }}): #{open_braces} open, #{close_braces} close" if open_braces != close_braces

          {
            valid: errors.empty?,
            errors: errors
          }
        end

        # Output raw template format
        def output_template_format(content)
          puts content
        end

        # Output JSON format with metadata
        def output_json_format(content, type)
          data = {
            version: Dsl::Schema.version,
            template_type: type,
            template: content
          }

          if options[:with_schema]
            data[:schema] = Dsl::Schema.to_json_schema
            data[:safe_agent_methods] = Dsl::Schema.safe_agent_methods
            data[:safe_tool_methods] = Dsl::Schema.safe_tool_methods
            data[:safe_helper_methods] = Dsl::Schema.safe_helper_methods
          end

          puts JSON.pretty_generate(data)
        end

        # Output YAML format with metadata
        def output_yaml_format(content, type)
          data = {
            'version' => Dsl::Schema.version,
            'template_type' => type,
            'template' => content
          }

          if options[:with_schema]
            data['schema'] = Dsl::Schema.to_json_schema.transform_keys(&:to_s)
            data['safe_agent_methods'] = Dsl::Schema.safe_agent_methods
            data['safe_tool_methods'] = Dsl::Schema.safe_tool_methods
            data['safe_helper_methods'] = Dsl::Schema.safe_helper_methods
          end

          puts YAML.dump(data)
        end
      end
    end
  end
end
