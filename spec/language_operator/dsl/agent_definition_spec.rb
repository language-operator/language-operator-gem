# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/agent_definition'
require 'language_operator/dsl/task_definition'
require 'language_operator/dsl/main_definition'

RSpec.describe LanguageOperator::Dsl::AgentDefinition do
  let(:agent_name) { 'test-agent' }
  let(:agent) { described_class.new(agent_name) }

  describe '#initialize' do
    it 'initializes with a name' do
      expect(agent.name).to eq(agent_name)
    end

    it 'initializes tasks as empty hash' do
      expect(agent.tasks).to eq({})
      expect(agent.tasks).to be_a(Hash)
    end

    it 'initializes with nil main' do
      expect(agent.main).to be_nil
    end

    it 'sets default execution mode to autonomous' do
      expect(agent.execution_mode).to eq(:autonomous)
    end
  end

  describe '#task' do
    context 'with neural task (instructions only)' do
      it 'creates and registers a neural task' do
        task_def = agent.task :analyze_data,
                              instructions: 'Analyze the data for anomalies',
                              inputs: { data: 'array' },
                              outputs: { issues: 'array', summary: 'string' }

        expect(task_def).to be_a(LanguageOperator::Dsl::TaskDefinition)
        expect(task_def.name).to eq(:analyze_data)
        expect(task_def.neural?).to be true
        expect(task_def.symbolic?).to be false
        expect(task_def.instructions_text).to eq('Analyze the data for anomalies')
        expect(task_def.inputs_schema).to eq({ data: 'array' })
        expect(task_def.outputs_schema).to eq({ issues: 'array', summary: 'string' })
      end

      it 'stores task in tasks hash' do
        agent.task :my_task,
                   instructions: 'Do something',
                   inputs: { x: 'integer' },
                   outputs: { y: 'integer' }

        expect(agent.tasks[:my_task]).to be_a(LanguageOperator::Dsl::TaskDefinition)
        expect(agent.tasks[:my_task].name).to eq(:my_task)
      end
    end

    context 'with symbolic task (block only)' do
      it 'creates and registers a symbolic task' do
        task_def = agent.task :calculate_total,
                              inputs: { items: 'array' },
                              outputs: { total: 'number' } do |inputs|
          { total: inputs[:items].sum { |i| i['amount'] } }
        end

        expect(task_def).to be_a(LanguageOperator::Dsl::TaskDefinition)
        expect(task_def.name).to eq(:calculate_total)
        expect(task_def.neural?).to be false
        expect(task_def.symbolic?).to be true
        expect(task_def.execute_block).to be_a(Proc)
      end

      it 'stores symbolic task in tasks hash' do
        agent.task :add_numbers,
                   inputs: { a: 'integer', b: 'integer' },
                   outputs: { sum: 'integer' } do |inputs|
          { sum: inputs[:a] + inputs[:b] }
        end

        expect(agent.tasks[:add_numbers]).to be_a(LanguageOperator::Dsl::TaskDefinition)
        expect(agent.tasks[:add_numbers].symbolic?).to be true
      end
    end

    context 'with hybrid task (both instructions and block)' do
      it 'creates and registers a hybrid task' do
        task_def = agent.task :fetch_user,
                              instructions: 'Fetch user from database',
                              inputs: { user_id: 'integer' },
                              outputs: { user: 'hash' } do |inputs|
          { user: { id: inputs[:user_id], name: 'Test User' } }
        end

        expect(task_def).to be_a(LanguageOperator::Dsl::TaskDefinition)
        expect(task_def.name).to eq(:fetch_user)
        expect(task_def.neural?).to be true
        expect(task_def.symbolic?).to be true
        expect(task_def.instructions_text).to eq('Fetch user from database')
        expect(task_def.execute_block).to be_a(Proc)
      end
    end

    context 'with multiple tasks' do
      it 'registers all tasks in the tasks hash' do
        agent.task :task1,
                   inputs: {},
                   outputs: { result: 'string' } do
          { result: 'task1' }
        end

        agent.task :task2,
                   instructions: 'Do task2',
                   inputs: {},
                   outputs: { result: 'string' }

        agent.task :task3,
                   inputs: { x: 'integer' },
                   outputs: { y: 'integer' } do |inputs|
          { y: inputs[:x] * 2 }
        end

        expect(agent.tasks.size).to eq(3)
        expect(agent.tasks.keys).to contain_exactly(:task1, :task2, :task3)
        expect(agent.tasks[:task1].symbolic?).to be true
        expect(agent.tasks[:task2].neural?).to be true
        expect(agent.tasks[:task3].symbolic?).to be true
      end
    end
  end

  describe '#main' do
    it 'creates a main definition when block is provided' do
      main_def = agent.main do |_inputs|
        { result: 'completed' }
      end

      expect(main_def).to be_a(LanguageOperator::Dsl::MainDefinition)
      expect(main_def.execute_block).to be_a(Proc)
      expect(agent.main).to eq(main_def)
    end

    it 'returns existing main definition when called without block' do
      original_main = agent.main { |inputs| inputs }
      retrieved_main = agent.main

      expect(retrieved_main).to eq(original_main)
    end
  end

  describe 'DSL v1 complete example' do
    it 'supports full DSL v1 pattern with tasks and main' do
      agent.description 'Test agent for DSL v1'
      agent.persona 'A helpful assistant'

      # Define tasks
      agent.task :fetch_data,
                 instructions: 'Fetch data from source',
                 inputs: { source: 'string' },
                 outputs: { data: 'array' }

      agent.task :process_data,
                 inputs: { data: 'array' },
                 outputs: { processed: 'hash' } do |inputs|
        { processed: { count: inputs[:data].size } }
      end

      # Define main block
      agent.main do |inputs|
        raw_data = execute_task(:fetch_data, inputs: { source: inputs[:source] })
        execute_task(:process_data, inputs: raw_data)
      end

      expect(agent.description).to eq('Test agent for DSL v1')
      expect(agent.persona).to eq('A helpful assistant')
      expect(agent.tasks.size).to eq(2)
      expect(agent.tasks[:fetch_data].neural?).to be true
      expect(agent.tasks[:process_data].symbolic?).to be true
      expect(agent.main).to be_a(LanguageOperator::Dsl::MainDefinition)
      expect(agent.main.defined?).to be true
    end
  end
end
