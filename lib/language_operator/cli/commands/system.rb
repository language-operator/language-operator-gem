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
      end
    end
  end
end
