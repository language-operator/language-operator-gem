# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/scheduler'

RSpec.describe LanguageOperator::Agent::Scheduler do
  let(:agent_config) do
    {
      'agent' => {
        'name' => 'test-scheduled-agent',
        'instructions' => 'Run scheduled tasks',
        'schedules' => []
      },
      'llm' => {
        'provider' => 'anthropic',
        'model' => 'claude-3-5-sonnet-20241022'
      },
      'mcp' => { 'servers' => {} }
    }
  end

  let(:agent_double) do
    instance_double(
      LanguageOperator::Agent::Base,
      workspace_path: '/workspace',
      servers_info: [{ name: 'test-server', url: 'http://localhost:8080' }],
      config: agent_config
    )
  end

  let(:scheduler) { described_class.new(agent_double) }

  describe '#initialize' do
    it 'creates a scheduler with agent' do
      expect(scheduler.agent).to eq(agent_double)
    end

    it 'initializes rufus scheduler' do
      expect(scheduler.rufus_scheduler).to be_a(Rufus::Scheduler)
    end
  end

  describe 'OpenTelemetry instrumentation' do
    let(:tracer_double) { instance_double(OpenTelemetry::Trace::Tracer) }
    let(:span_double) { instance_double(OpenTelemetry::Trace::Span) }
    let(:tracer_provider_double) { instance_double(OpenTelemetry::Trace::TracerProvider) }
    let(:executor_double) { instance_double(LanguageOperator::Agent::Executor) }

    before do
      # Mock OpenTelemetry tracer
      allow(OpenTelemetry).to receive(:tracer_provider).and_return(tracer_provider_double)
      allow(tracer_provider_double).to receive(:tracer).and_return(tracer_double)
      allow(tracer_double).to receive(:in_span).and_yield(span_double)

      # Mock the executor
      allow(LanguageOperator::Agent::Executor).to receive(:new).and_return(executor_double)
      allow(executor_double).to receive(:execute).and_return('Task completed')
      allow(executor_double).to receive(:execute_workflow).and_return(double(content: 'Workflow completed'))

      # Mock the rufus scheduler to immediately execute blocks
      allow_any_instance_of(Rufus::Scheduler).to receive(:cron) do |_instance, _cron, &block|
        block.call
      end
    end

    describe '#add_schedule' do
      let(:schedule) do
        {
          'cron' => '0 9 * * *',
          'task' => 'Daily morning task'
        }
      end

      it 'creates a span with correct name during scheduled execution' do
        expect(tracer_double).to receive(:in_span).with('agent.scheduler.execute', anything).and_yield(span_double)
        scheduler.send(:add_schedule, schedule)
      end

      it 'includes scheduler.cron_expression attribute' do
        expect(tracer_double).to receive(:in_span).with(
          'agent.scheduler.execute',
          hash_including(attributes: hash_including('scheduler.cron_expression' => '0 9 * * *'))
        ).and_yield(span_double)
        scheduler.send(:add_schedule, schedule)
      end

      it 'includes agent.name attribute' do
        expect(tracer_double).to receive(:in_span).with(
          'agent.scheduler.execute',
          hash_including(attributes: hash_including('agent.name' => 'test-scheduled-agent'))
        ).and_yield(span_double)
        scheduler.send(:add_schedule, schedule)
      end

      it 'includes scheduler.task_type attribute' do
        expect(tracer_double).to receive(:in_span).with(
          'agent.scheduler.execute',
          hash_including(attributes: hash_including('scheduler.task_type' => 'scheduled'))
        ).and_yield(span_double)
        scheduler.send(:add_schedule, schedule)
      end
    end

    describe '#setup_default_schedule' do
      it 'creates a span with correct name during default execution' do
        expect(tracer_double).to receive(:in_span).with('agent.scheduler.execute', anything).and_yield(span_double)
        scheduler.send(:setup_default_schedule)
      end

      it 'includes scheduler.cron_expression attribute' do
        expect(tracer_double).to receive(:in_span).with(
          'agent.scheduler.execute',
          hash_including(attributes: hash_including('scheduler.cron_expression' => '0 6 * * *'))
        ).and_yield(span_double)
        scheduler.send(:setup_default_schedule)
      end

      it 'includes agent.name attribute' do
        expect(tracer_double).to receive(:in_span).with(
          'agent.scheduler.execute',
          hash_including(attributes: hash_including('agent.name' => 'test-scheduled-agent'))
        ).and_yield(span_double)
        scheduler.send(:setup_default_schedule)
      end

      it 'includes scheduler.task_type attribute set to default' do
        expect(tracer_double).to receive(:in_span).with(
          'agent.scheduler.execute',
          hash_including(attributes: hash_including('scheduler.task_type' => 'default'))
        ).and_yield(span_double)
        scheduler.send(:setup_default_schedule)
      end
    end

    describe '#start_with_workflow' do
      let(:workflow_double) { instance_double(LanguageOperator::Dsl::WorkflowDefinition, steps: {}, step_order: []) }
      let(:schedule_double) { double(cron: '0 12 * * *') }
      let(:agent_def_double) do
        instance_double(
          LanguageOperator::Dsl::AgentDefinition,
          name: 'test-workflow-agent',
          description: 'Test workflow',
          schedule: schedule_double,
          workflow: workflow_double,
          objectives: [],
          constraints: nil,
          output_config: nil,
          persona: nil
        )
      end

      before do
        # Mock the join to prevent blocking
        allow_any_instance_of(Rufus::Scheduler).to receive(:join)
      end

      it 'creates a span with correct name during workflow execution' do
        expect(tracer_double).to receive(:in_span).with('agent.scheduler.execute', anything).and_yield(span_double)

        thread = Thread.new { scheduler.start_with_workflow(agent_def_double) }
        sleep 0.1 # Give it time to execute
        thread.kill
      end

      it 'includes scheduler.cron_expression attribute' do
        expect(tracer_double).to receive(:in_span).with(
          'agent.scheduler.execute',
          hash_including(attributes: hash_including('scheduler.cron_expression' => '0 12 * * *'))
        ).and_yield(span_double)

        thread = Thread.new { scheduler.start_with_workflow(agent_def_double) }
        sleep 0.1
        thread.kill
      end

      it 'includes agent.name attribute from agent definition' do
        expect(tracer_double).to receive(:in_span).with(
          'agent.scheduler.execute',
          hash_including(attributes: hash_including('agent.name' => 'test-workflow-agent'))
        ).and_yield(span_double)

        thread = Thread.new { scheduler.start_with_workflow(agent_def_double) }
        sleep 0.1
        thread.kill
      end

      it 'includes scheduler.task_type attribute set to workflow' do
        expect(tracer_double).to receive(:in_span).with(
          'agent.scheduler.execute',
          hash_including(attributes: hash_including('scheduler.task_type' => 'workflow'))
        ).and_yield(span_double)

        thread = Thread.new { scheduler.start_with_workflow(agent_def_double) }
        sleep 0.1
        thread.kill
      end
    end

    describe 'exception handling in spans' do
      let(:schedule) do
        {
          'cron' => '0 9 * * *',
          'task' => 'Failing task'
        }
      end

      before do
        # Make the executor raise an error
        allow(executor_double).to receive(:execute).and_raise(StandardError, 'Task execution failed')
      end

      it 'records exception on span when execution fails' do
        expect(span_double).to receive(:record_exception).with(
          an_instance_of(StandardError)
        )
        expect(span_double).to receive(:status=)

        expect { scheduler.send(:add_schedule, schedule) }.to raise_error(StandardError, 'Task execution failed')
      end
    end
  end

  describe '#stop' do
    it 'shuts down the rufus scheduler' do
      expect(scheduler.rufus_scheduler).to receive(:shutdown)
      scheduler.stop
    end
  end
end
