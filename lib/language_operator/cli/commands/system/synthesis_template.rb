# frozen_string_literal: true

require 'json'
require 'yaml'

module LanguageOperator
  module CLI
    module Commands
      module System
        # Synthesis template export command
        module SynthesisTemplate
          def self.included(base)
            base.class_eval do
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
                handle_command_error('load template') do
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
                    validation_result = validate_template_content(template_content, template_type)

                    # Display warnings if any
                    unless validation_result[:warnings].empty?
                      Formatters::ProgressFormatter.warn('Template validation warnings:')
                      validation_result[:warnings].each do |warning|
                        puts "  ⚠  #{warning}"
                      end
                      puts
                    end

                    # Display errors and exit if validation failed
                    if validation_result[:valid]
                      Formatters::ProgressFormatter.success('Template validation passed')
                      return
                    else
                      Formatters::ProgressFormatter.error('Template validation failed:')
                      validation_result[:errors].each do |error|
                        puts "  ✗ #{error}"
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
                end
              end

              private

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
    end
  end
end
