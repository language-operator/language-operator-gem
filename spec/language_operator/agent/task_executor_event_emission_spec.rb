# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/task_executor'
require 'language_operator/dsl/task_definition'

RSpec.describe LanguageOperator::Agent::TaskExecutor, 'event emission' do
  let(:agent) { instance_double(LanguageOperator::Agent::Base) }
  let(:kubernetes_client) { instance_double(LanguageOperator::Kubernetes::Client) }
  let(:tasks_registry) { {} }
  let(:config) { {} }
  let(:executor) { described_class.new(agent, tasks_registry, config) }

  let(:symbolic_task) do
    LanguageOperator::Dsl::TaskDefinition.new('test_task').tap do |task|
      task.execute { |inputs| { result: 'success' } }
    end
  end

  let(:neural_task) do
    LanguageOperator::Dsl::TaskDefinition.new('neural_task').tap do |task|
      task.instruction 'Test instruction'
      task.outputs { result :string }
    end
  end

  before do
    tasks_registry[:test_task] = symbolic_task
    tasks_registry[:neural_task] = neural_task
    
    allow(agent).to receive(:kubernetes_client).and_return(kubernetes_client)
    allow(agent).to receive(:send_message).and_return('{"result": "success"}')
    allow(agent).to receive(:logger).and_return(Logger.new('/dev/null'))
    
    # Mock OpenTelemetry
    allow(OpenTelemetry::Trace).to receive(:current_span).and_return(nil)
    allow_any_instance_of(described_class).to receive(:tracer).and_return(
      instance_double(OpenTelemetry::Tracer, in_span: nil)
    )
  end

  describe 'successful task execution' do
    it 'emits a success event for symbolic tasks' do
      expect(kubernetes_client).to receive(:emit_execution_event).with(
        'test_task',
        hash_including(
          success: true,
          duration_ms: be_a(Float),
          metadata: hash_including('task_type' => 'symbolic')
        )
      )

      executor.execute_task(:test_task, inputs: {})
    end

    it 'emits a success event for neural tasks' do
      expect(kubernetes_client).to receive(:emit_execution_event).with(
        'neural_task',
        hash_including(
          success: true,
          duration_ms: be_a(Float),
          metadata: hash_including('task_type' => 'neural')
        )
      )

      executor.execute_task(:neural_task, inputs: {})
    end

    it 'includes execution duration in the event' do
      start_time = Time.now
      
      expect(kubernetes_client).to receive(:emit_execution_event) do |task_name, options|
        expect(options[:duration_ms]).to be > 0
        expect(options[:duration_ms]).to be < 10000 # Should be less than 10 seconds
      end

      allow(Time).to receive(:now).and_return(start_time, start_time + 0.1) # 100ms execution
      executor.execute_task(:test_task, inputs: {})
    end
  end

  describe 'failed task execution' do
    before do
      allow(symbolic_task).to receive(:call).and_raise(StandardError.new('Task failed'))
    end

    it 'emits a failure event with error details' do
      expect(kubernetes_client).to receive(:emit_execution_event).with(
        'test_task',
        hash_including(
          success: false,
          duration_ms: be_a(Float),
          metadata: hash_including(
            'task_type' => 'symbolic',
            'error_type' => 'StandardError',
            'error_category' => 'execution'
          )
        )
      )

      expect { executor.execute_task(:test_task, inputs: {}) }
        .to raise_error(LanguageOperator::Agent::TaskExecutionError)
    end

    it 'emits failure event for validation errors' do
      allow(symbolic_task).to receive(:validate_inputs).and_raise(ArgumentError.new('Invalid input'))

      expect(kubernetes_client).to receive(:emit_execution_event).with(
        'test_task',
        hash_including(
          success: false,
          metadata: hash_including(
            'error_type' => 'ArgumentError',
            'error_category' => 'validation'
          )
        )
      )

      expect { executor.execute_task(:test_task, inputs: {}) }
        .to raise_error(LanguageOperator::Agent::TaskValidationError)
    end
  end

  describe 'when Kubernetes client is not available' do
    before do
      allow(agent).to receive(:kubernetes_client).and_return(nil)
      allow(agent).to receive(:respond_to?).with(:kubernetes_client).and_return(false)
    end

    it 'does not emit events and continues normally' do
      expect(kubernetes_client).not_to receive(:emit_execution_event)
      
      result = executor.execute_task(:test_task, inputs: {})
      expect(result[:result]).to eq('success')
    end
  end

  describe 'when event emission fails' do
    before do
      allow(kubernetes_client).to receive(:emit_execution_event)
        .and_raise(StandardError.new('Event emission failed'))
    end

    it 'logs warning but does not fail task execution' do
      logger = instance_double(Logger)
      allow(agent).to receive(:logger).and_return(logger)
      allow(logger).to receive(:warn)

      expect(logger).to receive(:warn).with(
        'Failed to emit task execution event',
        hash_including(task: :test_task)
      )

      result = executor.execute_task(:test_task, inputs: {})
      expect(result[:result]).to eq('success')
    end

    it 'does not prevent error propagation for failed tasks' do
      allow(symbolic_task).to receive(:call).and_raise(StandardError.new('Task failed'))

      expect { executor.execute_task(:test_task, inputs: {}) }
        .to raise_error(LanguageOperator::Agent::TaskExecutionError)
    end
  end

  describe '#emit_task_execution_event' do
    let(:error) { StandardError.new('Test error') }
    let(:start_time) { Time.now - 0.5 } # 500ms ago

    it 'calculates duration correctly' do
      expect(kubernetes_client).to receive(:emit_execution_event) do |task_name, options|
        expect(options[:duration_ms]).to be_within(50).of(500)
      end

      executor.send(:emit_task_execution_event, 'test_task', 
                   success: true, execution_start: start_time)
    end

    it 'includes task type in metadata' do
      expect(kubernetes_client).to receive(:emit_execution_event) do |task_name, options|
        expect(options[:metadata]['task_type']).to eq('symbolic')
      end

      executor.send(:emit_task_execution_event, 'test_task', 
                   success: true, execution_start: start_time)
    end

    it 'includes error details for failed tasks' do
      expect(kubernetes_client).to receive(:emit_execution_event) do |task_name, options|
        expect(options[:metadata]['error_type']).to eq('StandardError')
        expect(options[:metadata]['error_category']).to be_a(String)
      end

      executor.send(:emit_task_execution_event, 'test_task', 
                   success: false, execution_start: start_time, error: error)
    end

    context 'when task is not in registry' do
      it 'handles missing tasks gracefully' do
        expect(kubernetes_client).to receive(:emit_execution_event) do |task_name, options|
          expect(options[:metadata]['task_type']).to be_nil
        end

        executor.send(:emit_task_execution_event, 'unknown_task', 
                     success: true, execution_start: start_time)
      end
    end
  end
end