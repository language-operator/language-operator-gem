# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'yaml'

RSpec.describe 'Schema Artifacts Generation' do
  let(:schema_dir) { File.join(__dir__, '../../../lib/language_operator/templates/schema') }
  let(:json_schema_path) { File.join(schema_dir, 'agent_dsl_schema.json') }
  let(:openapi_path) { File.join(schema_dir, 'agent_dsl_openapi.yaml') }
  let(:changelog_path) { File.join(schema_dir, 'CHANGELOG.md') }

  describe 'JSON Schema artifact' do
    it 'exists' do
      expect(File.exist?(json_schema_path)).to be true
    end

    it 'is valid JSON' do
      expect { JSON.parse(File.read(json_schema_path)) }.not_to raise_error
    end

    it 'contains required schema properties' do
      schema = JSON.parse(File.read(json_schema_path))

      expect(schema['$schema']).to eq('http://json-schema.org/draft-07/schema#')
      expect(schema['title']).to eq('Language Operator Agent DSL')
      expect(schema['version']).to eq(LanguageOperator::VERSION)
      expect(schema['type']).to eq('object')
    end

    it 'includes agent properties' do
      schema = JSON.parse(File.read(json_schema_path))

      expect(schema['properties']).to include('name', 'description', 'persona', 'mode', 'schedule')
    end

    it 'includes definitions' do
      schema = JSON.parse(File.read(json_schema_path))

      expect(schema['definitions']).to include(
        'TaskDefinition',
        'MainDefinition',
        'ConstraintsDefinition',
        'WebhookDefinition',
        'ToolDefinition'
      )
    end

    it 'matches the output of Schema.to_json_schema' do
      expected_schema = LanguageOperator::Dsl::Schema.to_json_schema
      actual_schema = JSON.parse(File.read(json_schema_path), symbolize_names: true)

      expect(actual_schema).to eq(expected_schema)
    end
  end

  describe 'OpenAPI artifact' do
    it 'exists' do
      expect(File.exist?(openapi_path)).to be true
    end

    it 'is valid YAML' do
      expect { YAML.safe_load_file(openapi_path, permitted_classes: [Symbol], aliases: true) }.not_to raise_error
    end

    it 'contains required OpenAPI properties' do
      openapi = YAML.safe_load_file(openapi_path, permitted_classes: [Symbol], aliases: true, symbolize_names: true)

      expect(openapi[:openapi]).to eq('3.0.3')
      expect(openapi[:info]).to be_a(Hash)
      expect(openapi[:info][:title]).to eq('Language Operator Agent API')
      expect(openapi[:info][:version]).to eq(LanguageOperator::VERSION)
    end

    it 'includes documented endpoints' do
      openapi = YAML.safe_load_file(openapi_path, permitted_classes: [Symbol], aliases: true, symbolize_names: true)

      expect(openapi[:paths].keys).to include(
        :'/health',
        :'/ready',
        :'/v1/chat/completions',
        :'/v1/models'
      )
    end

    it 'includes component schemas' do
      openapi = YAML.safe_load_file(openapi_path, permitted_classes: [Symbol], aliases: true, symbolize_names: true)

      expect(openapi[:components][:schemas].keys).to include(
        :ChatCompletionRequest,
        :ChatCompletionResponse,
        :HealthResponse,
        :ErrorResponse
      )
    end

    it 'matches the output of Schema.to_openapi' do
      expected_openapi = LanguageOperator::Dsl::Schema.to_openapi
      actual_openapi = YAML.safe_load_file(openapi_path, permitted_classes: [Symbol], aliases: true, symbolize_names: true)

      # YAML serialization may change symbol keys to string keys, so we compare after converting
      expect(actual_openapi).to eq(YAML.load(YAML.dump(expected_openapi), symbolize_names: true))
    end
  end

  describe 'Schema CHANGELOG' do
    it 'exists' do
      expect(File.exist?(changelog_path)).to be true
    end

    it 'contains version history' do
      changelog = File.read(changelog_path)

      expect(changelog).to include('# Schema Changelog')
      expect(changelog).to include('## Version History')
      expect(changelog).to include(LanguageOperator::VERSION)
    end

    it 'documents schema versioning approach' do
      changelog = File.read(changelog_path)

      expect(changelog).to include('Semantic Versioning')
      expect(changelog).to include('MAJOR')
      expect(changelog).to include('MINOR')
      expect(changelog).to include('PATCH')
    end
  end

  describe 'Rake task' do
    it 'can regenerate schema artifacts' do
      require 'rake'
      require 'fileutils'

      # Load the rake task
      load File.join(__dir__, '../../../Rakefile')

      # Remove existing files to test generation
      FileUtils.rm_f(json_schema_path)
      FileUtils.rm_f(openapi_path)

      # Run the task
      Rake::Task['schema:generate'].reenable
      Rake::Task['schema:generate'].invoke

      # Verify files were recreated
      expect(File.exist?(json_schema_path)).to be true
      expect(File.exist?(openapi_path)).to be true

      # Verify they are valid
      expect { JSON.parse(File.read(json_schema_path)) }.not_to raise_error
      expect { YAML.safe_load_file(openapi_path, permitted_classes: [Symbol], aliases: true) }.not_to raise_error
    end
  end
end
