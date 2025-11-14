# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/main_definition'

RSpec.describe LanguageOperator::Dsl::MainDefinition do
  let(:main_def) { described_class.new }

  describe '#initialize' do
    it 'creates a main definition with no execute block' do
      expect(main_def.execute_block).to be_nil
    end

    it 'is not defined initially' do
      expect(main_def.defined?).to be false
    end
  end

  describe '#execute' do
    it 'stores the execution block' do
      block = proc { |inputs| inputs }
      main_def.execute(&block)
      expect(main_def.execute_block).to eq(block)
    end

    it 'marks main as defined after setting block' do
      main_def.execute { |inputs| inputs }
      expect(main_def.defined?).to be true
    end

    it 'raises error if no block given' do
      expect { main_def.execute }.to raise_error(ArgumentError, /Main block is required/)
    end
  end

  describe '#call' do
    let(:inputs) { { user_id: 123, action: 'test' } }
    let(:context) { double('context') }

    context 'when main block is defined' do
      before do
        main_def.execute { |inputs| inputs[:user_id] * 2 }
      end

      it 'executes the main block with inputs' do
        result = main_def.call(inputs, context)
        expect(result).to eq(246)
      end

      it 'executes block in context using instance_exec' do
        main_def.execute { |_inputs| self }
        result = main_def.call(inputs, context)
        expect(result).to eq(context)
      end

      it 'passes inputs to the block' do
        received_inputs = nil
        main_def.execute do |inputs|
          received_inputs = inputs
          inputs
        end
        main_def.call(inputs, context)
        expect(received_inputs).to eq(inputs)
      end

      it 'returns the result from the block' do
        main_def.execute { |_inputs| { success: true } }
        result = main_def.call(inputs, context)
        expect(result).to eq({ success: true })
      end
    end

    context 'when main block is not defined' do
      it 'raises an error' do
        expect do
          main_def.call(inputs, context)
        end.to raise_error(RuntimeError, /Main block not defined/)
      end
    end

    context 'input validation' do
      before do
        main_def.execute { |inputs| inputs }
      end

      it 'requires inputs to be a Hash' do
        expect do
          main_def.call('not a hash', context)
        end.to raise_error(ArgumentError, /inputs must be a Hash/)
      end

      it 'accepts empty Hash' do
        expect { main_def.call({}, context) }.not_to raise_error
      end
    end

    context 'error handling' do
      it 'propagates errors from the block' do
        main_def.execute { |_inputs| raise StandardError, 'Test error' }
        expect do
          main_def.call(inputs, context)
        end.to raise_error(StandardError, 'Test error')
      end

      it 'logs error details before re-raising' do
        main_def.execute { |_inputs| raise ArgumentError, 'Bad argument' }
        expect do
          main_def.call(inputs, context)
        end.to raise_error(ArgumentError, 'Bad argument')
      end
    end

    context 'with execute_task calls' do
      let(:task_result) { { data: 'test_data' } }

      before do
        # Mock context that provides execute_task
        allow(context).to receive(:instance_exec) do |inputs, &block|
          # Create a simple binding that has execute_task method
          ctx = Object.new
          ctx.define_singleton_method(:execute_task) do |task_name, inputs:|
            { task: task_name, inputs: inputs }
          end
          ctx.instance_exec(inputs, &block)
        end
      end

      it 'allows calling execute_task within main block' do
        main_def.execute do |inputs|
          execute_task(:test_task, inputs: inputs)
        end

        result = main_def.call(inputs, context)
        expect(result[:task]).to eq(:test_task)
        expect(result[:inputs]).to eq(inputs)
      end
    end

    context 'with control flow' do
      before do
        main_def.execute do |inputs|
          if inputs[:user_id] > 100
            { status: 'high' }
          else
            { status: 'low' }
          end
        end
      end

      it 'supports conditional logic' do
        result = main_def.call({ user_id: 150 }, context)
        expect(result[:status]).to eq('high')

        result = main_def.call({ user_id: 50 }, context)
        expect(result[:status]).to eq('low')
      end
    end

    context 'with exception handling in block' do
      before do
        main_def.execute do |inputs|
          raise 'Simulated error' if inputs[:should_fail]

          { success: true }
        rescue StandardError => e
          { success: false, error: e.message }
        end
      end

      it 'allows block to handle its own exceptions' do
        result = main_def.call({ should_fail: true }, context)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Simulated error')
      end

      it 'returns success when no error' do
        result = main_def.call({ should_fail: false }, context)
        expect(result[:success]).to be true
      end
    end
  end

  describe '#defined?' do
    it 'returns false when no block is set' do
      expect(main_def.defined?).to be false
    end

    it 'returns true when block is set' do
      main_def.execute { |inputs| inputs }
      expect(main_def.defined?).to be true
    end
  end
end
