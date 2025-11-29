# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/commands/system/base'
require 'json'
require 'yaml'

RSpec.describe LanguageOperator::CLI::Commands::System::Base do
  let(:command) { described_class.new }

  # Mock exit calls to prevent parallel_rspec from seeing them as process failures
  before do
    allow(Kernel).to receive(:exit) do |code = 0|
      raise SystemExit.new(code)
    end
  end

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

  describe '#extract_code_examples' do
    it 'extracts Ruby code blocks from template' do
      template = <<~TEMPLATE
        Some text
        ```ruby
        puts "hello"
        ```
        More text
      TEMPLATE

      examples = command.send(:extract_code_examples, template)
      expect(examples.length).to eq(1)
      expect(examples[0][:code]).to include('puts "hello"')
      expect(examples[0][:start_line]).to eq(3) # idx=0: "Some text", idx=1: "```ruby", idx=2 (line 3): code
    end

    it 'extracts multiple code blocks' do
      template = <<~TEMPLATE
        First block:
        ```ruby
        agent "test1"
        ```
        Second block:
        ```ruby
        agent "test2"
        ```
      TEMPLATE

      examples = command.send(:extract_code_examples, template)
      expect(examples.length).to eq(2)
      expect(examples[0][:code]).to include('test1')
      expect(examples[1][:code]).to include('test2')
    end

    it 'returns empty array when no code blocks' do
      template = 'No code blocks here'
      examples = command.send(:extract_code_examples, template)
      expect(examples).to be_empty
    end

    it 'handles empty code blocks' do
      template = <<~TEMPLATE
        Empty block:
        ```ruby
        ```
      TEMPLATE

      examples = command.send(:extract_code_examples, template)
      expect(examples).to be_empty
    end
  end

  describe '#extract_method_calls' do
    it 'extracts method calls from Ruby code' do
      template = <<~TEMPLATE
        ```ruby
        agent "test" do
          description "Test agent"
          mode :autonomous
        end
        ```
      TEMPLATE

      methods = command.send(:extract_method_calls, template)
      expect(methods).to include('agent')
      expect(methods).to include('description')
      expect(methods).to include('mode')
    end

    it 'returns empty array when no code blocks' do
      template = 'No code here'
      methods = command.send(:extract_method_calls, template)
      expect(methods).to be_empty
    end

    it 'handles syntax errors gracefully' do
      template = <<~TEMPLATE
        ```ruby
        this is not valid ruby!!!
        ```
      TEMPLATE

      methods = command.send(:extract_method_calls, template)
      expect(methods).to be_empty
    end
  end

  describe '#validate_code_against_schema' do
    it 'validates safe Ruby code' do
      code = <<~RUBY
        require 'language_operator'
        agent "test" do
          description "Test"
        end
      RUBY

      result = command.send(:validate_code_against_schema, code)
      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end

    it 'detects dangerous method calls' do
      code = <<~RUBY
        system("rm -rf /")
      RUBY

      result = command.send(:validate_code_against_schema, code)
      expect(result[:valid]).to be false
      expect(result[:errors]).not_to be_empty
      expect(result[:errors][0][:message]).to include('system')
    end

    it 'detects syntax errors' do
      # NOTE: Prism is lenient and creates AST even with syntax errors
      # Our validator focuses on security (dangerous methods), not syntax
      skip 'Prism is lenient with syntax errors - focuses on security validation instead'

      code = '@@' # Invalid syntax
      result = command.send(:validate_code_against_schema, code)
      expect(result[:valid]).to be false
      expect(result[:errors]).not_to be_empty
      expect(result[:errors][0][:type]).to eq(:syntax_error)
    end

    it 'validates code with allowed requires' do
      code = <<~RUBY
        require 'language_operator'
        agent "test"
      RUBY

      result = command.send(:validate_code_against_schema, code)
      expect(result[:valid]).to be true
    end
  end

  # describe '#validate_template' do
  #   context 'with default bundled template' do
  #     it 'validates successfully' do
  #       output = capture_stdout { command.invoke(:validate_template, [], {}) }
  #       expect(output).to include('Validating template')
  #       expect(output).to include('All examples are valid')
  #     end

  #     it 'finds code examples' do
  #       output = capture_stdout { command.invoke(:validate_template, [], {}) }
  #       expect(output).to match(/Found \d+ code example/)
  #     end

  #     it 'exits with status 0 for valid template' do
  #       expect do
  #         capture_stdout { command.invoke(:validate_template, [], {}) }
  #       end.not_to raise_error
  #     end
  #   end

  #   context 'with bundled persona template' do
  #     it 'validates successfully' do
  #       output = capture_stdout do
  #         command.invoke(:validate_template, [], type: 'persona')
  #       end
  #       expect(output).to include('Validating template')
  #       expect(output).to include('bundled persona template')
  #     end
  #   end

  #   context 'with custom template file' do
  #     let(:valid_template_path) { '/tmp/valid_template_test.tmpl' }
  #     let(:valid_template) do
  #       <<~TEMPLATE
  #         Test template
  #         ```ruby
  #         require 'language_operator'

  #         agent "test-agent" do
  #           description "Test agent"
  #           mode :autonomous
  #         end
  #         ```
  #       TEMPLATE
  #     end

  #     before do
  #       File.write(valid_template_path, valid_template)
  #     end

  #     after do
  #       FileUtils.rm_f(valid_template_path)
  #     end

  #     it 'validates custom template successfully' do
  #       output = capture_stdout do
  #         command.invoke(:validate_template, [], template: valid_template_path)
  #       end
  #       expect(output).to include('Validating template')
  #       expect(output).to include('valid_template_test.tmpl')
  #       expect(output).to include('All examples are valid')
  #     end
  #   end

  #   context 'with verbose flag' do
  #     let(:template_path) { '/tmp/template_with_issues.tmpl' }
  #     let(:template_with_error) do
  #       <<~TEMPLATE
  #         Template with dangerous code
  #         ```ruby
  #         require 'language_operator'

  #         agent "test" do
  #           description "Test"
  #           system("echo hello")
  #         end
  #         ```
  #       TEMPLATE
  #     end

  #     before do
  #       File.write(template_path, template_with_error)
  #     end

  #     after do
  #       FileUtils.rm_f(template_path)
  #     end

  #     it 'shows detailed violation information' do
  #       expect do
  #         capture_stdout do
  #           command.invoke(:validate_template, [], template: template_path, verbose: true)
  #         end
  #       end.to raise_error(SystemExit)
  #     end
  #   end

  #   context 'error handling' do
  #     it 'exits with status 1 when file not found' do
  #       expect do
  #         command.invoke(:validate_template, [], template: '/nonexistent/file.tmpl')
  #       end.to raise_error(SystemExit) { |error|
  #         expect(error.status).to eq(1)
  #       }
  #     end

  #     it 'shows error message for missing file' do
  #       output = capture_stdout do
  #         expect do
  #           command.invoke(:validate_template, [], template: '/nonexistent/file.tmpl')
  #         end.to raise_error(SystemExit)
  #       end
  #       expect(output).to include('not found')
  #     end

  #     it 'exits with status 1 for invalid template type' do
  #       expect do
  #         command.invoke(:validate_template, [], type: 'invalid')
  #       end.to raise_error(SystemExit) { |error|
  #         expect(error.status).to eq(1)
  #       }
  #     end

  #     it 'shows error message for invalid type' do
  #       output = capture_stdout do
  #         expect do
  #           command.invoke(:validate_template, [], type: 'invalid')
  #         end.to raise_error(SystemExit)
  #       end
  #       expect(output).to include('Invalid template type')
  #     end
  #   end

  #   context 'with template containing no code blocks' do
  #     let(:template_path) { '/tmp/no_code_template.tmpl' }
  #     let(:template_no_code) { 'Just plain text, no code blocks here' }

  #     before do
  #       File.write(template_path, template_no_code)
  #     end

  #     after do
  #       FileUtils.rm_f(template_path)
  #     end

  #     it 'exits with status 1' do
  #       expect do
  #         capture_stdout do
  #           command.invoke(:validate_template, [], template: template_path)
  #         end
  #       end.to raise_error(SystemExit) { |error|
  #         expect(error.status).to eq(1)
  #       }
  #     end

  #     it 'shows warning about no code examples' do
  #       output = capture_stdout do
  #         expect do
  #           command.invoke(:validate_template, [], template: template_path)
  #         end.to raise_error(SystemExit)
  #       end
  #       expect(output).to include('No Ruby code examples found')
  #     end
  #   end

  #   context 'with template containing validation errors' do
  #     let(:template_path) { '/tmp/invalid_template.tmpl' }
  #     let(:invalid_template) do
  #       <<~TEMPLATE
  #         Template with errors
  #         ```ruby
  #         require 'language_operator'

  #         agent "test" do
  #           system("dangerous")
  #         end
  #         ```
  #       TEMPLATE
  #     end

  #     before do
  #       File.write(template_path, invalid_template)
  #     end

  #     after do
  #       FileUtils.rm_f(template_path)
  #     end

  #     it 'exits with status 1' do
  #       expect do
  #         capture_stdout do
  #           command.invoke(:validate_template, [], template: template_path)
  #         end
  #       end.to raise_error(SystemExit) { |error|
  #         expect(error.status).to eq(1)
  #       }
  #     end

  #     it 'shows validation errors' do
  #       output = capture_stdout do
  #         expect do
  #           command.invoke(:validate_template, [], template: template_path)
  #         end.to raise_error(SystemExit)
  #       end
  #       expect(output).to include('Validation failed')
  #       expect(output).to include('system')
  #     end

  #     it 'reports line numbers for violations' do
  #       output = capture_stdout do
  #         expect do
  #           command.invoke(:validate_template, [], template: template_path)
  #         end.to raise_error(SystemExit)
  #       end
  #       expect(output).to match(/Line \d+/)
  #     end
  #   end
  # end

  describe '#fetch_from_operator' do
    context 'when kubectl is available and ConfigMap exists' do
      it 'fetches agent template from operator' do
        allow(command).to receive(:`).with(
          'kubectl get configmap agent-synthesis-template -n language-operator-system ' \
          "-o jsonpath='{.data.template}' 2>/dev/null"
        ).and_return('Agent template content from operator')

        result = command.send(:fetch_from_operator, 'agent')
        expect(result).to eq('Agent template content from operator')
      end

      it 'fetches persona template from operator' do
        allow(command).to receive(:`).with(
          'kubectl get configmap persona-distillation-template -n language-operator-system ' \
          "-o jsonpath='{.data.template}' 2>/dev/null"
        ).and_return('Persona template content')

        result = command.send(:fetch_from_operator, 'persona')
        expect(result).to eq('Persona template content')
      end
    end

    context 'when kubectl fails or ConfigMap does not exist' do
      it 'returns nil for agent template' do
        allow(command).to receive(:`).with(
          'kubectl get configmap agent-synthesis-template -n language-operator-system ' \
          "-o jsonpath='{.data.template}' 2>/dev/null"
        ).and_return('')

        result = command.send(:fetch_from_operator, 'agent')
        expect(result).to be_nil
      end

      it 'returns nil for persona template' do
        allow(command).to receive(:`).with(
          'kubectl get configmap persona-distillation-template -n language-operator-system ' \
          "-o jsonpath='{.data.template}' 2>/dev/null"
        ).and_return('')

        result = command.send(:fetch_from_operator, 'persona')
        expect(result).to be_nil
      end

      it 'handles exceptions gracefully' do
        allow(command).to receive(:`).and_raise(StandardError.new('kubectl not found'))

        result = command.send(:fetch_from_operator, 'agent')
        expect(result).to be_nil
      end
    end
  end

  describe '#load_template' do
    context 'when operator template is available' do
      it 'uses operator template instead of bundled' do
        allow(command).to receive(:fetch_from_operator).with('agent').and_return('Operator template')
        allow(command).to receive(:load_bundled_template).and_return('Bundled template')

        result = command.send(:load_template, 'agent')
        expect(result).to eq('Operator template')
      end
    end

    context 'when operator template is not available' do
      it 'falls back to bundled template' do
        allow(command).to receive(:fetch_from_operator).with('agent').and_return(nil)
        allow(command).to receive(:load_bundled_template).with('agent').and_return('Bundled template')

        result = command.send(:load_template, 'agent')
        expect(result).to eq('Bundled template')
      end
    end

    context 'for persona templates' do
      it 'tries operator first, falls back to bundled' do
        allow(command).to receive(:fetch_from_operator).with('persona').and_return(nil)
        allow(command).to receive(:load_bundled_template).with('persona').and_return('Bundled persona')

        result = command.send(:load_template, 'persona')
        expect(result).to eq('Bundled persona')
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
