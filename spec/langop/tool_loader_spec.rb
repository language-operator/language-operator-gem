# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/tool_loader'

RSpec.describe LanguageOperator::ToolLoader do
  let(:tool_dir) { File.join(__dir__, '../fixtures/tools') }
  let(:registry) { LanguageOperator::Dsl::Registry.new }
  let(:loader) { described_class.new(registry, tool_dir) }

  before do
    # Create fixture tools directory
    FileUtils.mkdir_p(tool_dir)

    # Create a sample tool file
    File.write(File.join(tool_dir, 'sample_tool.rb'), <<~RUBY)
      tool 'sample' do
        description 'A sample tool for testing'

        parameter 'input' do
          type 'string'
          required true
        end
      end

      def execute(params)
        "Sample tool executed with: \#{params['input']}"
      end
    RUBY

    # Create another tool file
    File.write(File.join(tool_dir, 'math_tool.rb'), <<~RUBY)
      tool 'add' do
        description 'Adds two numbers'

        parameter 'a' do
          type 'number'
          required true
        end

        parameter 'b' do
          type 'number'
          required true
        end
      end

      def execute(params)
        result = params['a'] + params['b']
        "Result: \#{result}"
      end
    RUBY
  end

  after do
    # Clean up fixture files
    FileUtils.rm_rf(tool_dir)
  end

  describe '#load_tools' do
    it 'loads all tool files from directory' do
      loader.load_tools

      expect(registry.all.length).to be >= 2
      expect(registry.get('sample')).not_to be_nil
      expect(registry.get('add')).not_to be_nil
    end

    xit 'creates tool instances with correct definitions' do
      loader.load_tools

      sample_tool = registry.get('sample')

      expect(sample_tool.tool_definition.name).to eq('sample')
      expect(sample_tool.tool_definition.description).to eq('A sample tool for testing')
      expect(sample_tool.tool_definition.parameters).to have_key('input')
    end

    it 'skips non-Ruby files' do
      File.write(File.join(tool_dir, 'readme.txt'), 'Not a tool')

      expect { loader.load_tools }.not_to raise_error
    end

    it 'handles subdirectories' do
      subdir = File.join(tool_dir, 'advanced')
      FileUtils.mkdir_p(subdir)

      File.write(File.join(subdir, 'advanced_tool.rb'), <<~RUBY)
        tool 'advanced' do
          description 'Advanced tool'
        end

        def execute(params)
          'advanced'
        end
      RUBY

      loader.load_tools

      expect(registry.get('advanced')).not_to be_nil
    end
  end

  describe '#reload_tools' do
    xit 'reloads tools when files change' do
      loader.load_tools

      # Modify a tool file
      File.write(File.join(tool_dir, 'sample_tool.rb'), <<~RUBY)
        tool 'sample' do
          description 'Modified description'
          parameter 'input' do
            type 'string'
            required true
          end
        end

        def execute(params)
          "Modified: \#{params['input']}"
        end
      RUBY

      loader.reload_tools

      sample_tool = registry.get('sample')
      expect(sample_tool.tool_definition.description).to eq('Modified description')
    end
  end

  describe 'error handling' do
    it 'reports tools with syntax errors' do
      File.write(File.join(tool_dir, 'broken_tool.rb'), <<~RUBY)
        tool 'broken' do
          description 'This tool has a syntax error
        end
      RUBY

      expect { loader.load_tools }.to raise_error(/syntax error/i)
    end

    it 'handles missing tool directory gracefully' do
      loader = described_class.new(registry, '/nonexistent/path')

      expect { loader.load_tools }.not_to raise_error # It just skips loading
    end
  end

  describe '.create_mcp_tool with OpenTelemetry instrumentation' do
    let(:tracer_double) { instance_double(OpenTelemetry::Trace::Tracer) }
    let(:span_double) { instance_double(OpenTelemetry::Trace::Span) }
    let(:tracer_provider_double) { instance_double(OpenTelemetry::Trace::TracerProvider) }
    let(:tool_def) do
      instance_double(
        LanguageOperator::Dsl::ToolDefinition,
        name: 'test_tool',
        description: 'Test tool',
        parameters: {},
        execute_block: ->(params) { "executed with #{params}" }
      )
    end

    before do
      # Mock OpenTelemetry tracer
      allow(OpenTelemetry).to receive(:tracer_provider).and_return(tracer_provider_double)
      allow(tracer_provider_double).to receive(:tracer).and_return(tracer_double)
      allow(tracer_double).to receive(:in_span).and_yield(span_double)
      allow(span_double).to receive(:set_attribute)
      allow(span_double).to receive(:record_exception)
      allow(span_double).to receive(:status=)
    end

    it 'creates a span with correct name during tool execution' do
      mcp_tool = described_class.create_mcp_tool(tool_def)

      expect(tracer_double).to receive(:in_span).with('agent.tool.execute', anything).and_yield(span_double)
      mcp_tool.call(input: 'test')
    end

    it 'includes tool.name attribute' do
      mcp_tool = described_class.create_mcp_tool(tool_def)

      expect(tracer_double).to receive(:in_span).with(
        'agent.tool.execute',
        hash_including(attributes: hash_including('tool.name' => 'test_tool'))
      ).and_yield(span_double)
      mcp_tool.call(input: 'test')
    end

    it 'includes tool.type attribute' do
      mcp_tool = described_class.create_mcp_tool(tool_def)

      expect(tracer_double).to receive(:in_span).with(
        'agent.tool.execute',
        hash_including(attributes: hash_including('tool.type' => 'custom'))
      ).and_yield(span_double)
      mcp_tool.call(input: 'test')
    end

    it 'sets tool.result to success on successful execution' do
      mcp_tool = described_class.create_mcp_tool(tool_def)

      expect(span_double).to receive(:set_attribute).with('tool.result', 'success')
      mcp_tool.call(input: 'test')
    end

    it 'records exception and sets failure status on error' do
      error_tool_def = instance_double(
        LanguageOperator::Dsl::ToolDefinition,
        name: 'error_tool',
        description: 'Tool that fails',
        parameters: {},
        execute_block: ->(_params) { raise StandardError, 'Tool failed' }
      )

      mcp_tool = described_class.create_mcp_tool(error_tool_def)

      expect(span_double).to receive(:record_exception).with(instance_of(StandardError))
      expect(span_double).to receive(:set_attribute).with('tool.result', 'failure')
      expect(span_double).to receive(:status=).with(instance_of(OpenTelemetry::Trace::Status))

      expect { mcp_tool.call(input: 'test') }.to raise_error(StandardError, 'Tool failed')
    end

    it 'executes tool within the span' do
      mcp_tool = described_class.create_mcp_tool(tool_def)
      result = mcp_tool.call(input: 'test')

      expect(result).to be_a(MCP::Tool::Response)
    end
  end
end
