# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/task_definition'

RSpec.describe LanguageOperator::Dsl::TaskDefinition do
  let(:task_name) { :test_task }
  let(:task) { described_class.new(task_name) }

  describe '#initialize' do
    it 'creates a task with a name' do
      expect(task.name).to eq(task_name)
    end

    it 'initializes with empty schemas' do
      expect(task.inputs_schema).to eq({})
      expect(task.outputs_schema).to eq({})
    end

    it 'has no instructions initially' do
      expect(task.instructions_text).to be_nil
    end

    it 'has no execute block initially' do
      expect(task.execute_block).to be_nil
    end
  end

  describe '#inputs' do
    let(:schema) { { user_id: 'integer', name: 'string' } }

    it 'sets the inputs schema' do
      task.inputs(schema)
      expect(task.inputs_schema).to eq(schema)
    end

    it 'returns the current schema when called without arguments' do
      task.inputs(schema)
      expect(task.inputs).to eq(schema)
    end

    it 'validates schema types' do
      expect do
        task.inputs(user_id: 'invalid_type')
      end.to raise_error(ArgumentError, /must be one of/)
    end

    it 'accepts all supported types' do
      all_types = {
        str: 'string',
        num: 'number',
        int: 'integer',
        bool: 'boolean',
        arr: 'array',
        obj: 'hash',
        anything: 'any'
      }
      expect { task.inputs(all_types) }.not_to raise_error
    end
  end

  describe '#outputs' do
    let(:schema) { { result: 'string', count: 'integer' } }

    it 'sets the outputs schema' do
      task.outputs(schema)
      expect(task.outputs_schema).to eq(schema)
    end

    it 'returns the current schema when called without arguments' do
      task.outputs(schema)
      expect(task.outputs).to eq(schema)
    end

    it 'validates schema types' do
      expect do
        task.outputs(result: 'bad_type')
      end.to raise_error(ArgumentError, /must be one of/)
    end
  end

  describe '#instructions' do
    let(:text) { 'Fetch user data from the database' }

    it 'sets the instructions' do
      task.instructions(text)
      expect(task.instructions_text).to eq(text)
    end

    it 'returns current instructions when called without arguments' do
      task.instructions(text)
      expect(task.instructions).to eq(text)
    end
  end

  describe '#execute' do
    it 'sets the execute block' do
      block = proc { |_inputs| { result: 'test' } }
      task.execute(&block)
      expect(task.execute_block).to eq(block)
    end
  end

  describe '#neural?' do
    it 'returns false when no instructions are set' do
      expect(task.neural?).to be false
    end

    it 'returns true when instructions are set' do
      task.instructions('Do something')
      expect(task.neural?).to be true
    end
  end

  describe '#symbolic?' do
    it 'returns false when no execute block is set' do
      expect(task.symbolic?).to be false
    end

    it 'returns true when execute block is set' do
      task.execute { |_inputs| { result: 'test' } }
      expect(task.symbolic?).to be true
    end
  end

  describe '#validate_inputs' do
    before do
      task.inputs(user_id: 'integer', name: 'string')
    end

    it 'validates and coerces valid inputs' do
      result = task.validate_inputs(user_id: 123, name: 'Alice')
      expect(result).to eq(user_id: 123, name: 'Alice')
    end

    it 'coerces string to integer' do
      result = task.validate_inputs(user_id: '456', name: 'Bob')
      expect(result[:user_id]).to eq(456)
      expect(result[:user_id]).to be_an(Integer)
    end

    it 'raises error for missing required input' do
      expect do
        task.validate_inputs(name: 'Alice')
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Missing required input parameter: user_id/)
    end

    it 'raises error for invalid coercion' do
      expect do
        task.validate_inputs(user_id: 'abc', name: 'Alice')
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Cannot coerce "abc" to integer/)
    end

    it 'converts symbol to string for string type' do
      result = task.validate_inputs(user_id: 123, name: :alice)
      expect(result[:name]).to eq('alice')
      expect(result[:name]).to be_a(String)
    end
  end

  describe '#validate_outputs' do
    before do
      task.outputs(user: 'hash', found: 'boolean')
    end

    it 'validates and coerces valid outputs' do
      result = task.validate_outputs(user: { id: 1 }, found: true)
      expect(result).to eq(user: { id: 1 }, found: true)
    end

    it 'raises error for missing required output' do
      expect do
        task.validate_outputs(user: { id: 1 })
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Missing required output field: found/)
    end

    it 'validates hash type' do
      expect do
        task.validate_outputs(user: 'not a hash', found: true)
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Expected hash/)
    end
  end

  describe 'type coercion' do
    describe 'integer' do
      before { task.inputs(value: 'integer') }

      it 'accepts integer' do
        result = task.validate_inputs(value: 42)
        expect(result[:value]).to eq(42)
      end

      it 'coerces string' do
        result = task.validate_inputs(value: '42')
        expect(result[:value]).to eq(42)
      end

      it 'rejects invalid string' do
        expect do
          task.validate_inputs(value: 'abc')
        end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Cannot coerce/)
      end
    end

    describe 'number' do
      before { task.inputs(value: 'number') }

      it 'accepts numeric' do
        result = task.validate_inputs(value: 3.14)
        expect(result[:value]).to eq(3.14)
      end

      it 'coerces string' do
        result = task.validate_inputs(value: '2.71')
        expect(result[:value]).to eq(2.71)
      end

      it 'coerces integer to float' do
        result = task.validate_inputs(value: 42)
        expect(result[:value]).to eq(42)
      end
    end

    describe 'boolean' do
      before { task.inputs(flag: 'boolean') }

      it 'accepts true' do
        result = task.validate_inputs(flag: true)
        expect(result[:flag]).to be true
      end

      it 'accepts false' do
        result = task.validate_inputs(flag: false)
        expect(result[:flag]).to be false
      end

      it 'coerces "true" string' do
        result = task.validate_inputs(flag: 'true')
        expect(result[:flag]).to be true
      end

      it 'coerces "false" string' do
        result = task.validate_inputs(flag: 'false')
        expect(result[:flag]).to be false
      end

      it 'coerces "1" to true' do
        result = task.validate_inputs(flag: '1')
        expect(result[:flag]).to be true
      end

      it 'coerces "0" to false' do
        result = task.validate_inputs(flag: '0')
        expect(result[:flag]).to be false
      end

      it 'rejects ambiguous values' do
        expect do
          task.validate_inputs(flag: 'maybe')
        end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Cannot coerce/)
      end
    end

    describe 'array' do
      before { task.inputs(items: 'array') }

      it 'accepts array' do
        result = task.validate_inputs(items: [1, 2, 3])
        expect(result[:items]).to eq([1, 2, 3])
      end

      it 'rejects non-array' do
        expect do
          task.validate_inputs(items: 'not an array')
        end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Expected array/)
      end
    end

    describe 'hash' do
      before { task.inputs(data: 'hash') }

      it 'accepts hash' do
        result = task.validate_inputs(data: { key: 'value' })
        expect(result[:data]).to eq(key: 'value')
      end

      it 'rejects non-hash' do
        expect do
          task.validate_inputs(data: [1, 2, 3])
        end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Expected hash/)
      end
    end

    describe 'any' do
      before { task.inputs(value: 'any') }

      it 'accepts any type' do
        expect(task.validate_inputs(value: 'string')[:value]).to eq('string')
        expect(task.validate_inputs(value: 123)[:value]).to eq(123)
        expect(task.validate_inputs(value: [1, 2])[:value]).to eq([1, 2])
        expect(task.validate_inputs(value: { a: 1 })[:value]).to eq(a: 1)
      end
    end
  end

  describe '#call (symbolic task)' do
    before do
      task.inputs(items: 'array')
      task.outputs(total: 'number')
      task.execute do |inputs|
        { total: inputs[:items].sum }
      end
    end

    it 'executes the symbolic implementation' do
      result = task.call(items: [1, 2, 3, 4])
      expect(result[:total]).to eq(10)
    end

    it 'validates inputs before execution' do
      expect do
        task.call(items: 'not an array')
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Expected array/)
    end

    it 'validates outputs after execution' do
      task.execute { |_inputs| { wrong_field: 123 } }

      expect do
        task.call(items: [1, 2, 3])
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Missing required output field: total/)
    end
  end

  describe '#call (neural task)' do
    before do
      task.instructions('Calculate the sum')
      task.inputs(items: 'array')
      task.outputs(total: 'number')
    end

    it 'raises NotImplementedError for neural execution' do
      expect do
        task.call(items: [1, 2, 3])
      end.to raise_error(NotImplementedError, /Neural task execution requires agent runtime/)
    end
  end

  describe '#call (no implementation)' do
    before do
      task.inputs(value: 'integer')
      task.outputs(result: 'integer')
    end

    it 'raises error when neither neural nor symbolic' do
      expect do
        task.call(value: 42)
      end.to raise_error(/has no implementation/)
    end
  end

  describe '#to_schema' do
    before do
      task.instructions('Process data')
      task.inputs(user_id: 'integer', filter: 'string')
      task.outputs(users: 'array', count: 'integer')
    end

    it 'exports task as JSON schema' do
      schema = task.to_schema

      expect(schema['name']).to eq('test_task')
      expect(schema['type']).to eq('neural')
      expect(schema['instructions']).to eq('Process data')
      expect(schema['inputs']['type']).to eq('object')
      expect(schema['inputs']['required']).to contain_exactly('user_id', 'filter')
      expect(schema['outputs']['type']).to eq('object')
      expect(schema['outputs']['required']).to contain_exactly('users', 'count')
    end

    it 'identifies symbolic type' do
      task.execute { |_inputs| { users: [], count: 0 } }
      schema = task.to_schema
      expect(schema['type']).to eq('hybrid')
    end

    it 'identifies purely symbolic type' do
      task.instance_variable_set(:@instructions_text, nil)
      task.execute { |_inputs| { users: [], count: 0 } }
      schema = task.to_schema
      expect(schema['type']).to eq('symbolic')
    end
  end

  describe 'real-world examples' do
    it 'supports neural task' do
      neural_task = described_class.new(:fetch_recent_orders)
      neural_task.instructions('Get orders from the last 24 hours')
      neural_task.inputs(user_id: 'integer')
      neural_task.outputs(orders: 'array')

      expect(neural_task.neural?).to be true
      expect(neural_task.symbolic?).to be false
    end

    it 'supports symbolic task' do
      symbolic_task = described_class.new(:calculate_total)
      symbolic_task.inputs(orders: 'array')
      symbolic_task.outputs(total: 'number')
      symbolic_task.execute do |inputs|
        { total: inputs[:orders].sum { |o| o['amount'] } }
      end

      result = symbolic_task.call(orders: [{ 'amount' => 10 }, { 'amount' => 20 }])
      expect(result[:total]).to eq(30)
    end

    it 'supports hybrid task' do
      hybrid_task = described_class.new(:fetch_and_process)
      hybrid_task.instructions('Fetch user data from database')
      hybrid_task.inputs(user_id: 'integer')
      hybrid_task.outputs(user: 'hash', preferences: 'hash')
      hybrid_task.execute do |inputs|
        # Symbolic implementation
        {
          user: { id: inputs[:user_id], name: 'Test' },
          preferences: { theme: 'dark' }
        }
      end

      expect(hybrid_task.neural?).to be true
      expect(hybrid_task.symbolic?).to be true

      result = hybrid_task.call(user_id: 123)
      expect(result[:user][:id]).to eq(123)
    end
  end

  describe 'block arity handling' do
    before do
      task.inputs(value: 'integer')
      task.outputs(result: 'integer')
    end

    it 'handles arity-1 blocks (inputs only)' do
      task.execute { |inputs| { result: inputs[:value] * 2 } }
      result = task.call(value: 5)
      expect(result[:result]).to eq(10)
    end

    it 'handles arity-2 blocks (inputs and context)' do
      task.execute { |inputs, _context| { result: inputs[:value] * 3 } }
      result = task.call(value: 5)
      expect(result[:result]).to eq(15)
    end

    it 'handles arity-0 blocks' do
      task.execute { { result: 42 } }
      result = task.call(value: 5)
      expect(result[:result]).to eq(42)
    end
  end
end
