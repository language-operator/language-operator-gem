# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/task_executor'
require 'language_operator/dsl/task_definition'
require 'opentelemetry/sdk'
require 'opentelemetry/sdk/trace/export/in_memory_span_exporter'

RSpec.describe LanguageOperator::Instrumentation::TaskTracer do
  let(:exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }
  let(:span_processor) { OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter) }

  let(:mock_agent) do
    double('Agent',
           config: { 'llm' => { 'model' => 'claude-3-5-sonnet-20241022', 'provider' => 'anthropic' } },
           send_message: mock_response)
  end

  let(:mock_response) do
    double('Response',
           content: '{"result": "success"}',
           input_tokens: 100,
           output_tokens: 50,
           model: 'claude-3-5-sonnet-20241022',
           id: 'msg_123',
           stop_reason: 'end_turn')
  end

  let(:neural_task) do
    LanguageOperator::Dsl::TaskDefinition.new(:test_neural).tap do |task|
      task.instructions('Do something with the input')
      task.inputs(text: 'string')
      task.outputs(result: 'string')
    end
  end

  let(:symbolic_task) do
    LanguageOperator::Dsl::TaskDefinition.new(:test_symbolic).tap do |task|
      task.inputs(value: 'integer')
      task.outputs(doubled: 'integer')
      task.execute do |inputs|
        { doubled: inputs[:value] * 2 }
      end
    end
  end

  let(:tasks) { { test_neural: neural_task, test_symbolic: symbolic_task } }
  let(:executor) { LanguageOperator::Agent::TaskExecutor.new(mock_agent, tasks) }

  before do
    # Configure OpenTelemetry with in-memory exporter for testing
    OpenTelemetry::SDK.configure do |c|
      c.add_span_processor(span_processor)
    end
    exporter.reset
  end

  after do
    # Clean up environment variables
    ENV.delete('CAPTURE_TASK_INPUTS')
    ENV.delete('CAPTURE_TASK_OUTPUTS')
    ENV.delete('CAPTURE_TOOL_ARGS')
    ENV.delete('CAPTURE_TOOL_RESULTS')
    ENV.delete('AGENT_NAME')
    ENV.delete('AGENT_MODE')
    ENV.delete('AGENT_CLUSTER')
  end

  describe 'span creation' do
    it 'creates root span for task execution' do
      executor.execute_task(:test_symbolic, inputs: { value: 5 })

      spans = exporter.finished_spans
      root_span = spans.find { |s| s.name == 'task_executor.execute_task' }

      expect(root_span).not_to be_nil
      expect(root_span.attributes['task.name']).to eq('test_symbolic')
    end

    it 'creates child span for neural execution' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      spans = exporter.finished_spans
      neural_span = spans.find { |s| s.name == 'gen_ai.chat' }

      expect(neural_span).not_to be_nil
      expect(neural_span.attributes['gen_ai.operation.name']).to eq('chat')
    end

    it 'creates child span for symbolic execution' do
      executor.execute_task(:test_symbolic, inputs: { value: 5 })

      spans = exporter.finished_spans
      symbolic_span = spans.find { |s| s.name == 'task_executor.symbolic' }

      expect(symbolic_span).not_to be_nil
      expect(symbolic_span.attributes['task.execution.type']).to eq('symbolic')
    end

    it 'creates parse_response span for neural tasks' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      spans = exporter.finished_spans
      parse_span = spans.find { |s| s.name == 'task_executor.parse_response' }

      expect(parse_span).not_to be_nil
    end
  end

  describe 'span attributes' do
    it 'records task metadata on root span' do
      executor.execute_task(:test_symbolic, inputs: { value: 5 })

      root_span = exporter.finished_spans.find { |s| s.name == 'task_executor.execute_task' }
      expect(root_span.attributes['task.name']).to eq('test_symbolic')
      expect(root_span.attributes['task.inputs']).to eq('value')
    end

    it 'records GenAI attributes for neural tasks' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      neural_span = exporter.finished_spans.find { |s| s.name == 'gen_ai.chat' }
      expect(neural_span.attributes['gen_ai.operation.name']).to eq('chat')
      expect(neural_span.attributes['gen_ai.system']).to eq('anthropic')
      expect(neural_span.attributes['gen_ai.request.model']).to eq('claude-3-5-sonnet-20241022')
      expect(neural_span.attributes['gen_ai.prompt.size']).to be > 0
    end

    it 'records token usage for neural tasks' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      neural_span = exporter.finished_spans.find { |s| s.name == 'gen_ai.chat' }
      expect(neural_span.attributes['gen_ai.usage.input_tokens']).to eq(100)
      expect(neural_span.attributes['gen_ai.usage.output_tokens']).to eq(50)
    end

    it 'records response metadata for neural tasks' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      neural_span = exporter.finished_spans.find { |s| s.name == 'gen_ai.chat' }
      expect(neural_span.attributes['gen_ai.response.model']).to eq('claude-3-5-sonnet-20241022')
      expect(neural_span.attributes['gen_ai.response.id']).to eq('msg_123')
      expect(neural_span.attributes['gen_ai.response.finish_reasons']).to eq('end_turn')
    end

    it 'records input metadata for neural tasks' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      neural_span = exporter.finished_spans.find { |s| s.name == 'gen_ai.chat' }
      expect(neural_span.attributes['task.input.keys']).to eq('text')
      expect(neural_span.attributes['task.input.count']).to eq(1)
    end

    it 'records output metadata for neural tasks' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      neural_span = exporter.finished_spans.find { |s| s.name == 'gen_ai.chat' }
      expect(neural_span.attributes['task.output.keys']).to eq('result')
      expect(neural_span.attributes['task.output.count']).to eq(1)
    end

    it 'records parse metadata' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      parse_span = exporter.finished_spans.find { |s| s.name == 'task_executor.parse_response' }
      expect(parse_span.attributes['gen_ai.completion.size']).to be > 0
    end

    it 'records input/output metadata for symbolic tasks' do
      executor.execute_task(:test_symbolic, inputs: { value: 5 })

      symbolic_span = exporter.finished_spans.find { |s| s.name == 'task_executor.symbolic' }
      expect(symbolic_span.attributes['task.input.keys']).to eq('value')
      expect(symbolic_span.attributes['task.input.count']).to eq(1)
      expect(symbolic_span.attributes['task.output.keys']).to eq('doubled')
      expect(symbolic_span.attributes['task.output.count']).to eq(1)
    end
  end

  describe 'data sanitization' do
    it 'does not capture prompt by default' do
      executor.execute_task(:test_neural, inputs: { text: 'secret data' })

      neural_span = exporter.finished_spans.find { |s| s.name == 'gen_ai.chat' }
      expect(neural_span.attributes).not_to have_key('gen_ai.prompt')
      expect(neural_span.attributes['gen_ai.prompt.size']).to be > 0
    end

    it 'does not capture completion by default' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      parse_span = exporter.finished_spans.find { |s| s.name == 'task_executor.parse_response' }
      expect(parse_span.attributes).not_to have_key('gen_ai.completion')
      expect(parse_span.attributes['gen_ai.completion.size']).to be > 0
    end

    it 'captures prompt when CAPTURE_TASK_INPUTS=true' do
      ENV['CAPTURE_TASK_INPUTS'] = 'true'
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      neural_span = exporter.finished_spans.find { |s| s.name == 'gen_ai.chat' }
      expect(neural_span.attributes['gen_ai.prompt']).not_to be_nil
      expect(neural_span.attributes['gen_ai.prompt']).to include('test')
    end

    it 'captures completion when CAPTURE_TASK_OUTPUTS=true' do
      ENV['CAPTURE_TASK_OUTPUTS'] = 'true'
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      parse_span = exporter.finished_spans.find { |s| s.name == 'task_executor.parse_response' }
      expect(parse_span.attributes['gen_ai.completion']).not_to be_nil
    end

    it 'truncates large prompts' do
      ENV['CAPTURE_TASK_INPUTS'] = 'true'
      large_text = 'x' * 2000

      executor.execute_task(:test_neural, inputs: { text: large_text })

      neural_span = exporter.finished_spans.find { |s| s.name == 'gen_ai.chat' }
      prompt = neural_span.attributes['gen_ai.prompt']
      expect(prompt).not_to be_nil
      expect(prompt).to include('truncated')
    end
  end

  describe 'tool call instrumentation' do
    let(:mock_tool_call) do
      double('ToolCall',
             name: 'github',
             id: 'call_123',
             arguments: { repo: 'test/repo', action: 'list_issues' },
             result: { issues: [] })
    end

    let(:mock_response_with_tools) do
      double('Response',
             content: '{"result": "success"}',
             input_tokens: 100,
             output_tokens: 50,
             model: 'claude-3-5-sonnet-20241022',
             tool_calls: [mock_tool_call])
    end

    before do
      allow(mock_agent).to receive(:send_message).and_return(mock_response_with_tools)
    end

    it 'creates spans for tool calls' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      tool_spans = exporter.finished_spans.select { |s| s.name.start_with?('execute_tool') }
      expect(tool_spans.size).to eq(1)
    end

    it 'records tool call attributes' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      tool_span = exporter.finished_spans.find { |s| s.name.start_with?('execute_tool') }
      expect(tool_span.attributes['gen_ai.operation.name']).to eq('execute_tool')
      expect(tool_span.attributes['gen_ai.tool.name']).to eq('github')
      expect(tool_span.attributes['gen_ai.tool.call.id']).to eq('call_123')
    end

    it 'does not capture tool arguments by default' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      tool_span = exporter.finished_spans.find { |s| s.name.start_with?('execute_tool') }
      expect(tool_span.attributes).not_to have_key('gen_ai.tool.call.arguments')
      expect(tool_span.attributes['gen_ai.tool.call.arguments.size']).to be > 0
    end

    it 'captures tool arguments when CAPTURE_TOOL_ARGS=true' do
      ENV['CAPTURE_TOOL_ARGS'] = 'true'
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      tool_span = exporter.finished_spans.find { |s| s.name.start_with?('execute_tool') }
      expect(tool_span.attributes['gen_ai.tool.call.arguments']).not_to be_nil
    end

    it 'does not capture tool results by default' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      tool_span = exporter.finished_spans.find { |s| s.name.start_with?('execute_tool') }
      expect(tool_span.attributes).not_to have_key('gen_ai.tool.call.result')
      expect(tool_span.attributes['gen_ai.tool.call.result.size']).to be > 0
    end

    it 'captures tool results when CAPTURE_TOOL_RESULTS=true' do
      ENV['CAPTURE_TOOL_RESULTS'] = 'true'
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      tool_span = exporter.finished_spans.find { |s| s.name.start_with?('execute_tool') }
      expect(tool_span.attributes['gen_ai.tool.call.result']).not_to be_nil
    end
  end

  describe 'error recording' do
    let(:failing_task) do
      LanguageOperator::Dsl::TaskDefinition.new(:failing).tap do |task|
        task.inputs(value: 'integer')
        task.outputs(result: 'integer')
        task.execute do |_inputs|
          raise StandardError, 'Task failed'
        end
      end
    end

    before do
      tasks[:failing] = failing_task
    end

    it 'records exceptions on span' do
      expect do
        executor.execute_task(:failing, inputs: { value: 5 })
      end.to raise_error(LanguageOperator::Agent::TaskExecutionError)

      symbolic_span = exporter.finished_spans.find { |s| s.name == 'task_executor.symbolic' }
      expect(symbolic_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
      expect(symbolic_span.events.any? { |e| e.name == 'exception' }).to be true
    end
  end

  describe '#capture_enabled?' do
    let(:tracer_instance) do
      Class.new do
        include LanguageOperator::Instrumentation::TaskTracer
      end.new
    end

    it 'returns false by default for all types' do
      expect(tracer_instance.send(:capture_enabled?, :inputs)).to be false
      expect(tracer_instance.send(:capture_enabled?, :outputs)).to be false
      expect(tracer_instance.send(:capture_enabled?, :tool_args)).to be false
      expect(tracer_instance.send(:capture_enabled?, :tool_results)).to be false
    end

    it 'returns true when env var is set' do
      ENV['CAPTURE_TASK_INPUTS'] = 'true'
      expect(tracer_instance.send(:capture_enabled?, :inputs)).to be true
    end
  end

  describe '#sanitize_data' do
    let(:tracer_instance) do
      Class.new do
        include LanguageOperator::Instrumentation::TaskTracer
      end.new
    end

    it 'returns nil when capture disabled' do
      result = tracer_instance.send(:sanitize_data, 'test', :inputs)
      expect(result).to be_nil
    end

    it 'returns string when capture enabled' do
      ENV['CAPTURE_TASK_INPUTS'] = 'true'
      result = tracer_instance.send(:sanitize_data, 'test', :inputs)
      expect(result).to eq('test')
    end

    it 'converts hash to JSON' do
      ENV['CAPTURE_TASK_INPUTS'] = 'true'
      result = tracer_instance.send(:sanitize_data, { key: 'value' }, :inputs)
      expect(result).to eq('{"key":"value"}')
    end

    it 'truncates long strings' do
      ENV['CAPTURE_TASK_INPUTS'] = 'true'
      long_string = 'x' * 2000
      result = tracer_instance.send(:sanitize_data, long_string, :inputs, max_length: 1000)
      expect(result).to include('truncated')
      expect(result.length).to be < 1100
    end
  end

  describe 'semantic attributes for learning system' do
    before do
      ENV['AGENT_NAME'] = 'test-agent'
      ENV['AGENT_MODE'] = 'autonomous'
      ENV['AGENT_CLUSTER'] = 'test-cluster'
    end

    it 'includes agent context attributes on task execution spans' do
      executor.execute_task(:test_symbolic, inputs: { value: 5 })

      root_span = exporter.finished_spans.find { |s| s.name == 'task_executor.execute_task' }
      expect(root_span.attributes['agent.name']).to eq('test-agent')
      expect(root_span.attributes['task.name']).to eq('test_symbolic')
      expect(root_span.attributes['gen_ai.operation.name']).to eq('execute_task')
    end

    it 'includes agent context attributes on neural task spans' do
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      neural_span = exporter.finished_spans.find { |s| s.name == 'gen_ai.chat' }
      expect(neural_span.attributes['agent.name']).to eq('test-agent')
      expect(neural_span.attributes['agent.mode']).to eq('autonomous')
      expect(neural_span.attributes['agent.cluster']).to eq('test-cluster')
      expect(neural_span.attributes['task.name']).to eq('test_neural')
    end

    it 'includes agent context attributes on symbolic task spans' do
      executor.execute_task(:test_symbolic, inputs: { value: 5 })

      symbolic_span = exporter.finished_spans.find { |s| s.name == 'task_executor.symbolic' }
      expect(symbolic_span.attributes['agent.name']).to eq('test-agent')
      expect(symbolic_span.attributes['agent.mode']).to eq('autonomous')
      expect(symbolic_span.attributes['agent.cluster']).to eq('test-cluster')
      expect(symbolic_span.attributes['task.name']).to eq('test_symbolic')
      expect(symbolic_span.attributes['gen_ai.operation.name']).to eq('execute_task')
    end

    it 'includes agent context attributes on tool call spans' do
      ENV['CAPTURE_TOOL_ARGS'] = 'true'
      mock_tool_call = double('ToolCall',
                              name: 'github',
                              id: 'call_123',
                              arguments: { repo: 'test/repo' },
                              result: { issues: [] })
      
      mock_response_with_tools = double('Response',
                                       content: '{"result": "success"}',
                                       input_tokens: 100,
                                       output_tokens: 50,
                                       model: 'claude-3-5-sonnet-20241022',
                                       tool_calls: [mock_tool_call])
      
      allow(mock_agent).to receive(:send_message).and_return(mock_response_with_tools)
      
      executor.execute_task(:test_neural, inputs: { text: 'test' })

      tool_span = exporter.finished_spans.find { |s| s.name.start_with?('execute_tool') }
      expect(tool_span.attributes['agent.name']).to eq('test-agent')
      expect(tool_span.attributes['agent.mode']).to eq('autonomous')
      expect(tool_span.attributes['agent.cluster']).to eq('test-cluster')
      expect(tool_span.attributes['gen_ai.operation.name']).to eq('execute_tool')
      expect(tool_span.attributes['gen_ai.tool.name']).to eq('github')
    end

    it 'includes task type information on task execution spans' do
      executor.execute_task(:test_symbolic, inputs: { value: 5 })

      root_span = exporter.finished_spans.find { |s| s.name == 'task_executor.execute_task' }
      expect(root_span.attributes['task.type']).to eq('symbolic')
      expect(root_span.attributes['task.has_neural']).to eq('false')
      expect(root_span.attributes['task.has_symbolic']).to eq('true')
    end

    it 'handles missing agent environment variables gracefully' do
      ENV.delete('AGENT_NAME')
      ENV.delete('AGENT_MODE')
      ENV.delete('AGENT_CLUSTER')

      executor.execute_task(:test_symbolic, inputs: { value: 5 })

      root_span = exporter.finished_spans.find { |s| s.name == 'task_executor.execute_task' }
      expect(root_span.attributes['agent.name']).to be_nil
      expect(root_span.attributes['task.name']).to eq('test_symbolic')
    end
  end

  describe '#add_agent_context_attributes' do
    let(:tracer_instance) do
      Class.new do
        include LanguageOperator::Instrumentation::TaskTracer
      end.new
    end

    it 'adds agent attributes from environment variables' do
      ENV['AGENT_NAME'] = 'test-agent'
      ENV['AGENT_MODE'] = 'scheduled'
      ENV['AGENT_CLUSTER'] = 'prod'

      attributes = {}
      tracer_instance.send(:add_agent_context_attributes, attributes)

      expect(attributes['agent.name']).to eq('test-agent')
      expect(attributes['agent.mode']).to eq('scheduled')
      expect(attributes['agent.cluster']).to eq('prod')
    end

    it 'handles missing environment variables gracefully' do
      attributes = {}
      tracer_instance.send(:add_agent_context_attributes, attributes)

      expect(attributes['agent.name']).to be_nil
      expect(attributes['agent.mode']).to be_nil
      expect(attributes['agent.cluster']).to be_nil
    end
  end
end
