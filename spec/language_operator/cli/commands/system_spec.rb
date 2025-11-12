# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/commands/system'
require 'json'
require 'yaml'

RSpec.describe LanguageOperator::CLI::Commands::System do
  let(:command) { described_class.new }

  describe '#schema' do
    context 'with --version flag' do
      it 'outputs only the schema version' do
        expect { command.invoke(:schema, [], version: true) }.to output(
          "#{LanguageOperator::VERSION}\n"
        ).to_stdout
      end

      it 'does not output JSON schema' do
        expect { command.invoke(:schema, [], version: true) }.not_to output(
          /\{.*\}/
        ).to_stdout
      end
    end

    context 'with json format (default)' do
      it 'outputs valid JSON' do
        output = capture_stdout { command.invoke(:schema, [], format: 'json') }
        expect { JSON.parse(output) }.not_to raise_error
      end

      it 'outputs JSON Schema v7' do
        output = capture_stdout { command.invoke(:schema, [], format: 'json') }
        schema = JSON.parse(output)
        expect(schema['$schema']).to eq('http://json-schema.org/draft-07/schema#')
      end

      it 'includes schema title and description' do
        output = capture_stdout { command.invoke(:schema, [], format: 'json') }
        schema = JSON.parse(output)
        expect(schema['title']).to eq('Language Operator Agent DSL')
        expect(schema['description']).to include('autonomous AI agents')
      end

      it 'includes version matching gem version' do
        output = capture_stdout { command.invoke(:schema, [], format: 'json') }
        schema = JSON.parse(output)
        expect(schema['version']).to eq(LanguageOperator::VERSION)
      end

      it 'pretty-prints the JSON' do
        output = capture_stdout { command.invoke(:schema, [], format: 'json') }
        # Pretty-printed JSON should have newlines and indentation
        expect(output).to include("\n")
        expect(output).to match(/\s{2}"/)
      end
    end

    context 'with yaml format' do
      it 'outputs valid YAML' do
        output = capture_stdout { command.invoke(:schema, [], format: 'yaml') }
        expect { YAML.safe_load(output, permitted_classes: [Symbol]) }.not_to raise_error
      end

      it 'includes schema metadata' do
        output = capture_stdout { command.invoke(:schema, [], format: 'yaml') }
        schema = YAML.safe_load(output, permitted_classes: [Symbol])
        expect(schema['title']).to eq('Language Operator Agent DSL')
        expect(schema['version']).to eq(LanguageOperator::VERSION)
      end

      it 'transforms symbol keys to strings' do
        output = capture_stdout { command.invoke(:schema, [], format: 'yaml') }
        schema = YAML.safe_load(output, permitted_classes: [Symbol])
        expect(schema.keys).to all(be_a(String))
      end
    end

    context 'with openapi format' do
      it 'outputs valid JSON' do
        output = capture_stdout { command.invoke(:schema, [], format: 'openapi') }
        expect { JSON.parse(output) }.not_to raise_error
      end

      it 'outputs OpenAPI 3.0.3 specification' do
        output = capture_stdout { command.invoke(:schema, [], format: 'openapi') }
        spec = JSON.parse(output)
        expect(spec['openapi']).to eq('3.0.3')
      end

      it 'includes info section with version' do
        output = capture_stdout { command.invoke(:schema, [], format: 'openapi') }
        spec = JSON.parse(output)
        expect(spec['info']).to be_a(Hash)
        expect(spec['info']['version']).to eq(LanguageOperator::VERSION)
        expect(spec['info']['title']).to include('Language Operator')
      end

      it 'includes paths section' do
        output = capture_stdout { command.invoke(:schema, [], format: 'openapi') }
        spec = JSON.parse(output)
        expect(spec['paths']).to be_a(Hash)
        expect(spec['paths']).not_to be_empty
      end

      it 'includes components section' do
        output = capture_stdout { command.invoke(:schema, [], format: 'openapi') }
        spec = JSON.parse(output)
        expect(spec['components']).to be_a(Hash)
        expect(spec['components']['schemas']).to be_a(Hash)
      end
    end

    context 'with invalid format' do
      it 'exits with error status 1' do
        expect do
          command.invoke(:schema, [], format: 'invalid')
        end.to raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end

    context 'with case-insensitive format' do
      it 'accepts JSON in uppercase' do
        output = capture_stdout { command.invoke(:schema, [], format: 'JSON') }
        expect { JSON.parse(output) }.not_to raise_error
      end

      it 'accepts YAML in mixed case' do
        output = capture_stdout { command.invoke(:schema, [], format: 'YaML') }
        expect { YAML.safe_load(output, permitted_classes: [Symbol]) }.not_to raise_error
      end

      it 'accepts OpenAPI in uppercase' do
        output = capture_stdout { command.invoke(:schema, [], format: 'OPENAPI') }
        spec = JSON.parse(output)
        expect(spec['openapi']).to eq('3.0.3')
      end
    end
  end

  describe '#synthesis_template' do
    context 'with default options (agent template, template format)' do
      it 'outputs agent synthesis template' do
        output = capture_stdout { command.invoke(:synthesis_template, [], {}) }
        expect(output).to include('You are generating Ruby DSL code')
        expect(output).to include('{{.AgentName}}')
        expect(output).to include('{{.Instructions}}')
      end

      it 'includes required placeholders' do
        output = capture_stdout { command.invoke(:synthesis_template, [], {}) }
        expect(output).to include('{{.ToolsList}}')
        expect(output).to include('{{.ModelsList}}')
        expect(output).to include('{{.TemporalIntent}}')
      end
    end

    context 'with persona type' do
      it 'outputs persona distillation template' do
        output = capture_stdout { command.invoke(:synthesis_template, [], type: 'persona') }
        expect(output).to include('Distill this persona')
        expect(output).to include('{{.PersonaName}}')
        expect(output).to include('{{.PersonaDescription}}')
      end

      it 'includes persona-specific placeholders' do
        output = capture_stdout { command.invoke(:synthesis_template, [], type: 'persona') }
        expect(output).to include('{{.PersonaSystemPrompt}}')
        expect(output).to include('{{.AgentInstructions}}')
        expect(output).to include('{{.AgentTools}}')
      end
    end

    context 'with json format' do
      it 'outputs valid JSON' do
        output = capture_stdout { command.invoke(:synthesis_template, [], format: 'json') }
        expect { JSON.parse(output) }.not_to raise_error
      end

      it 'includes version and template type' do
        output = capture_stdout { command.invoke(:synthesis_template, [], format: 'json') }
        data = JSON.parse(output)
        expect(data['version']).to eq(LanguageOperator::VERSION)
        expect(data['template_type']).to eq('agent')
      end

      it 'includes template content' do
        output = capture_stdout { command.invoke(:synthesis_template, [], format: 'json') }
        data = JSON.parse(output)
        expect(data['template']).to be_a(String)
        expect(data['template']).to include('{{.AgentName}}')
      end

      it 'pretty-prints the JSON' do
        output = capture_stdout { command.invoke(:synthesis_template, [], format: 'json') }
        expect(output).to include("\n")
        expect(output).to match(/\s{2}"/)
      end
    end

    context 'with json format and --with-schema' do
      it 'includes DSL schema' do
        output = capture_stdout do
          command.invoke(:synthesis_template, [], format: 'json', with_schema: true)
        end
        data = JSON.parse(output)
        expect(data['schema']).to be_a(Hash)
        expect(data['schema']['$schema']).to eq('http://json-schema.org/draft-07/schema#')
      end

      it 'includes safe methods' do
        output = capture_stdout do
          command.invoke(:synthesis_template, [], format: 'json', with_schema: true)
        end
        data = JSON.parse(output)
        expect(data['safe_agent_methods']).to be_an(Array)
        expect(data['safe_tool_methods']).to be_an(Array)
        expect(data['safe_helper_methods']).to be_an(Array)
      end
    end

    context 'with yaml format' do
      it 'outputs valid YAML' do
        output = capture_stdout { command.invoke(:synthesis_template, [], format: 'yaml') }
        expect { YAML.safe_load(output) }.not_to raise_error
      end

      it 'includes version and template type' do
        output = capture_stdout { command.invoke(:synthesis_template, [], format: 'yaml') }
        data = YAML.safe_load(output)
        expect(data['version']).to eq(LanguageOperator::VERSION)
        expect(data['template_type']).to eq('agent')
      end

      it 'includes template content' do
        output = capture_stdout { command.invoke(:synthesis_template, [], format: 'yaml') }
        data = YAML.safe_load(output)
        expect(data['template']).to be_a(String)
        expect(data['template']).to include('{{.AgentName}}')
      end
    end

    context 'with yaml format and --with-schema' do
      it 'includes DSL schema' do
        output = capture_stdout do
          command.invoke(:synthesis_template, [], format: 'yaml', with_schema: true)
        end
        data = YAML.safe_load(output, permitted_classes: [Symbol])
        expect(data['schema']).to be_a(Hash)
        expect(data['schema']['$schema']).to eq('http://json-schema.org/draft-07/schema#')
      end

      it 'includes safe methods' do
        output = capture_stdout do
          command.invoke(:synthesis_template, [], format: 'yaml', with_schema: true)
        end
        data = YAML.safe_load(output, permitted_classes: [Symbol])
        expect(data['safe_agent_methods']).to be_an(Array)
        expect(data['safe_tool_methods']).to be_an(Array)
        expect(data['safe_helper_methods']).to be_an(Array)
      end
    end

    context 'with --validate flag' do
      it 'validates agent template successfully' do
        expect do
          capture_stdout { command.invoke(:synthesis_template, [], validate: true) }
        end.not_to raise_error
      end

      it 'validates persona template successfully' do
        expect do
          capture_stdout do
            command.invoke(:synthesis_template, [], type: 'persona', validate: true)
          end
        end.not_to raise_error
      end

      it 'outputs success message for valid template' do
        output = capture_stdout { command.invoke(:synthesis_template, [], validate: true) }
        expect(output).to include('validation passed')
      end
    end

    context 'with invalid template type' do
      it 'exits with error status 1' do
        expect do
          command.invoke(:synthesis_template, [], type: 'invalid')
        end.to raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end

    context 'with invalid format' do
      it 'exits with error status 1' do
        expect do
          command.invoke(:synthesis_template, [], format: 'invalid')
        end.to raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end

    context 'with case-insensitive format' do
      it 'accepts JSON in uppercase' do
        output = capture_stdout { command.invoke(:synthesis_template, [], format: 'JSON') }
        expect { JSON.parse(output) }.not_to raise_error
      end

      it 'accepts YAML in mixed case' do
        output = capture_stdout { command.invoke(:synthesis_template, [], format: 'YaML') }
        expect { YAML.safe_load(output) }.not_to raise_error
      end
    end

    context 'with case-insensitive type' do
      it 'accepts AGENT in uppercase' do
        output = capture_stdout { command.invoke(:synthesis_template, [], type: 'AGENT') }
        expect(output).to include('{{.AgentName}}')
      end

      it 'accepts Persona in mixed case' do
        output = capture_stdout { command.invoke(:synthesis_template, [], type: 'Persona') }
        expect(output).to include('{{.PersonaName}}')
      end
    end
  end

  # Helper methods for capturing stdout and stderr
  def capture_stdout(&block)
    original_stdout = $stdout
    $stdout = StringIO.new
    block.call
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def capture_stderr(&block)
    original_stderr = $stderr
    $stderr = StringIO.new
    block.call
    $stderr.string
  ensure
    $stderr = original_stderr
  end
end
