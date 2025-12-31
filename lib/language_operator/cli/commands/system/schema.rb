# frozen_string_literal: true

require 'json'
require 'yaml'

module LanguageOperator
  module CLI
    module Commands
      module System
        # DSL schema export command
        module Schema
          def self.included(base)
            base.class_eval do
              desc 'schema', 'Export the DSL schema in various formats'
              long_desc <<-DESC
                Export the Language Operator Agent DSL schema in various formats.

                The schema documents all available DSL methods, parameters, validation
                patterns, and structure. Useful for template validation, documentation
                generation, and IDE autocomplete.

                Examples:
                  # Export JSON schema (default)
                  langop system schema

                  # Export as YAML
                  langop system schema --format yaml

                  # Export OpenAPI 3.0 specification
                  langop system schema --format openapi

                  # Show schema version only
                  langop system schema --version

                  # Save to file
                  langop system schema > schema.json
                  langop system schema --format openapi > openapi.json
              DESC
              option :format, type: :string, default: 'json', desc: 'Output format (json, yaml, openapi)'
              option :version, type: :boolean, default: false, desc: 'Show schema version only'
              def schema
                handle_command_error('generate schema') do
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
                end
              end

              private

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
          end
        end
      end
    end
  end
end
