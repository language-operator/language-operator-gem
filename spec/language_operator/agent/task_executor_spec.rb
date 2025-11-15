# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/task_executor'
require 'language_operator/dsl/task_definition'

RSpec.describe LanguageOperator::Agent::TaskExecutor do
  let(:agent) { instance_double(LanguageOperator::Agent::Base) }
  let(:tasks) { {} }
  let(:executor) { described_class.new(agent, tasks) }

  describe '#initialize' do
    it 'initializes with agent and tasks' do
      expect(executor.agent).to eq(agent)
      expect(executor.tasks).to eq(tasks)
    end

    it 'accepts empty tasks registry' do
      exec = described_class.new(agent)
      expect(exec.tasks).to eq({})
    end
  end

  describe '#execute_task' do
    context 'when task not found' do
      it 'raises ArgumentError with available tasks' do
        tasks[:foo] = double
        tasks[:bar] = double

        expect do
          executor.execute_task(:missing, inputs: {})
        end.to raise_error(ArgumentError, /Task not found: missing.*Available tasks: (foo, bar|bar, foo)/)
      end
    end

    context 'with symbolic task' do
      let(:task_def) do
        LanguageOperator::Dsl::TaskDefinition.new(:calculate_total).tap do |t|
          t.inputs({ items: 'array' })
          t.outputs({ total: 'number' })
          t.execute do |inputs|
            { total: inputs[:items].sum }
          end
        end
      end

      before do
        tasks[:calculate_total] = task_def
      end

      it 'executes symbolic task and returns validated output' do
        result = executor.execute_task(:calculate_total, inputs: { items: [1, 2, 3, 4, 5] })

        expect(result).to eq({ total: 15 })
      end

      it 'validates inputs before execution' do
        expect do
          executor.execute_task(:calculate_total, inputs: {})
        end.to raise_error(ArgumentError, /Missing required input parameter: items/)
      end

      it 'validates outputs after execution' do
        # Create a task that returns invalid output
        broken_task = LanguageOperator::Dsl::TaskDefinition.new(:broken).tap do |t|
          t.inputs({})
          t.outputs({ result: 'string' })
          t.execute do |_inputs|
            { wrong_field: 'oops' } # Missing required output field
          end
        end
        tasks[:broken] = broken_task

        expect do
          executor.execute_task(:broken, inputs: {})
        end.to raise_error(ArgumentError, /Missing required output field: result/)
      end

      it 'provides task executor as context to symbolic tasks' do
        # Create a task that uses execute_task internally
        nested_task = LanguageOperator::Dsl::TaskDefinition.new(:nested).tap do |t|
          t.inputs({})
          t.outputs({ sum: 'number' })
          t.execute do |_inputs, context|
            # Call another task via context
            result = context.execute_task(:calculate_total, inputs: { items: [10, 20, 30] })
            { sum: result[:total] }
          end
        end
        tasks[:nested] = nested_task

        result = executor.execute_task(:nested, inputs: {})
        expect(result).to eq({ sum: 60 })
      end
    end

    context 'with neural task' do
      let(:neural_task) do
        LanguageOperator::Dsl::TaskDefinition.new(:summarize_text).tap do |t|
          t.instructions('Summarize the given text')
          t.inputs({ text: 'string' })
          t.outputs({ summary: 'string' })
        end
      end

      let(:llm_response) do
        instance_double(RubyLLM::Message, content: '{"summary": "This is a summary"}', is_a?: false)
      end

      before do
        tasks[:summarize_text] = neural_task
        allow(agent).to receive(:send_message).and_return(llm_response)
      end

      it 'executes neural task via LLM' do
        result = executor.execute_task(:summarize_text, inputs: { text: 'Long text here...' })

        expect(result).to eq({ summary: 'This is a summary' })
        expect(agent).to have_received(:send_message)
      end

      it 'builds prompt with task instructions and inputs' do
        executor.execute_task(:summarize_text, inputs: { text: 'Sample text' })

        expect(agent).to have_received(:send_message) do |prompt|
          expect(prompt).to include('summarize_text')
          expect(prompt).to include('Summarize the given text')
          expect(prompt).to include('Sample text')
          expect(prompt).to include('summary (string)')
        end
      end

      it 'parses JSON from code blocks' do
        allow(agent).to receive(:send_message).and_return(
          instance_double(RubyLLM::Message,
                          content: "Here's the result:\n```json\n{\"summary\": \"Parsed from code block\"}\n```",
                          is_a?: false)
        )

        result = executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        expect(result).to eq({ summary: 'Parsed from code block' })
      end

      it 'parses raw JSON objects' do
        allow(agent).to receive(:send_message).and_return(
          instance_double(RubyLLM::Message,
                          content: '{"summary": "Raw JSON object"}',
                          is_a?: false)
        )

        result = executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        expect(result).to eq({ summary: 'Raw JSON object' })
      end

      it 'raises error if LLM returns invalid JSON' do
        allow(agent).to receive(:send_message).and_return(
          instance_double(RubyLLM::Message,
                          content: 'Not JSON at all',
                          is_a?: false)
        )

        expect do
          executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        end.to raise_error(RuntimeError, /returned invalid JSON/)
      end

      it 'validates neural task outputs against schema' do
        # LLM returns wrong field
        allow(agent).to receive(:send_message).and_return(
          instance_double(RubyLLM::Message,
                          content: '{"wrong_field": "value"}',
                          is_a?: false)
        )

        expect do
          executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        end.to raise_error(RuntimeError, /Missing required output field: summary/)
      end
    end

    context 'error handling' do
      let(:failing_task) do
        LanguageOperator::Dsl::TaskDefinition.new(:failing).tap do |t|
          t.inputs({})
          t.outputs({ result: 'string' })
          t.execute do |_inputs|
            raise StandardError, 'Task execution error'
          end
        end
      end

      before do
        tasks[:failing] = failing_task
      end

      it 'wraps execution errors with task context' do
        expect do
          executor.execute_task(:failing, inputs: {})
        end.to raise_error(RuntimeError, /Task 'failing' execution failed: Task execution error/)
      end

      it 'fails fast on errors' do
        # Ensure error is raised immediately, not caught
        expect do
          executor.execute_task(:failing, inputs: {})
        end.to raise_error(RuntimeError)
      end
    end
  end

  describe '#execute_tool' do
    it 'executes tool via LLM interface' do
      allow(agent).to receive(:send_message).and_return('Tool executed successfully')

      result = executor.execute_tool('my_tool', 'action_name', { param: 'value' })

      expect(result).to eq('Tool executed successfully')
      expect(agent).to have_received(:send_message).with(/Use the my_tool tool/)
    end
  end

  describe '#execute_llm' do
    it 'delegates to agent.send_message and extracts content' do
      llm_response = instance_double(RubyLLM::Message, content: 'LLM response text', is_a?: false)
      allow(agent).to receive(:send_message).and_return(llm_response)

      result = executor.execute_llm('Test prompt')

      expect(result).to eq('LLM response text')
      expect(agent).to have_received(:send_message).with('Test prompt')
    end

    it 'handles string responses' do
      allow(agent).to receive(:send_message).and_return('Direct string response')

      result = executor.execute_llm('Test prompt')

      expect(result).to eq('Direct string response')
    end
  end

  describe 'integration with MainDefinition' do
    let(:main_def) { LanguageOperator::Dsl::MainDefinition.new }
    let(:task1) do
      LanguageOperator::Dsl::TaskDefinition.new(:task1).tap do |t|
        t.inputs({ value: 'integer' })
        t.outputs({ doubled: 'integer' })
        t.execute do |inputs|
          { doubled: inputs[:value] * 2 }
        end
      end
    end
    let(:task2) do
      LanguageOperator::Dsl::TaskDefinition.new(:task2).tap do |t|
        t.inputs({ value: 'integer' })
        t.outputs({ result: 'string' })
        t.execute do |inputs|
          { result: "The answer is #{inputs[:value]}" }
        end
      end
    end

    before do
      tasks[:task1] = task1
      tasks[:task2] = task2
    end

    it 'executes main block with task executor as context' do
      main_def.execute do |inputs|
        result1 = execute_task(:task1, inputs: { value: inputs[:number] })
        result2 = execute_task(:task2, inputs: { value: result1[:doubled] })
        result2
      end

      result = main_def.call({ number: 21 }, executor)

      expect(result).to eq({ result: 'The answer is 42' })
    end
  end
end
