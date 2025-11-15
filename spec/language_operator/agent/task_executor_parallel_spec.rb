# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/task_executor'
require 'language_operator/dsl/task_definition'

RSpec.describe LanguageOperator::Agent::TaskExecutor, '#execute_parallel' do
  let(:agent) { instance_double(LanguageOperator::Agent::Base) }
  let(:tasks) { {} }
  let(:executor) { described_class.new(agent, tasks) }

  describe 'basic parallel execution' do
    let(:task1) do
      LanguageOperator::Dsl::TaskDefinition.new(:task1).tap do |t|
        t.inputs({})
        t.outputs({ result: 'integer' })
        t.execute do |_inputs|
          sleep 0.02 # Simulate I/O
          { result: 1 }
        end
      end
    end

    let(:task2) do
      LanguageOperator::Dsl::TaskDefinition.new(:task2).tap do |t|
        t.inputs({})
        t.outputs({ result: 'integer' })
        t.execute do |_inputs|
          sleep 0.02 # Simulate I/O
          { result: 2 }
        end
      end
    end

    before do
      tasks[:task1] = task1
      tasks[:task2] = task2
    end

    it 'executes tasks in parallel' do
      task_specs = [
        { name: :task1 },
        { name: :task2 }
      ]

      start_time = Time.now
      results = executor.execute_parallel(task_specs)
      elapsed = Time.now - start_time

      # Should execute in parallel (~0.02s) not sequential (~0.04s)
      expect(elapsed).to be < 0.03

      expect(results).to eq([{ result: 1 }, { result: 2 }])
    end

    it 'preserves result order matching input order' do
      task_specs = [
        { name: :task2 },
        { name: :task1 }
      ]

      results = executor.execute_parallel(task_specs)

      expect(results).to eq([{ result: 2 }, { result: 1 }])
    end
  end

  describe 'with task inputs' do
    let(:process_task) do
      LanguageOperator::Dsl::TaskDefinition.new(:process).tap do |t|
        t.inputs({ value: 'integer' })
        t.outputs({ doubled: 'integer' })
        t.execute do |inputs|
          { doubled: inputs[:value] * 2 }
        end
      end
    end

    before do
      tasks[:process] = process_task
    end

    it 'passes inputs to each task' do
      task_specs = [
        { name: :process, inputs: { value: 5 } },
        { name: :process, inputs: { value: 10 } },
        { name: :process, inputs: { value: 15 } }
      ]

      results = executor.execute_parallel(task_specs)

      expect(results).to eq([
                              { doubled: 10 },
                              { doubled: 20 },
                              { doubled: 30 }
                            ])
    end
  end

  describe 'thread pool configuration' do
    before do
      tasks[:task1] = LanguageOperator::Dsl::TaskDefinition.new(:task1).tap do |t|
        t.inputs({})
        t.outputs({ result: 'integer' })
        t.execute { |_inputs| { result: 1 } }
      end
    end

    it 'uses default thread pool size' do
      task_specs = [{ name: :task1 }]

      expect do
        executor.execute_parallel(task_specs)
      end.not_to raise_error
    end

    it 'accepts custom thread pool size' do
      task_specs = [{ name: :task1 }]

      results = executor.execute_parallel(task_specs, in_threads: 2)

      expect(results).to eq([{ result: 1 }])
    end
  end

  describe 'error handling' do
    let(:failing_task) do
      LanguageOperator::Dsl::TaskDefinition.new(:failing).tap do |t|
        t.inputs({})
        t.outputs({ result: 'string' })
        t.execute do |_inputs|
          raise StandardError, 'Task failed!'
        end
      end
    end

    let(:success_task) do
      LanguageOperator::Dsl::TaskDefinition.new(:success).tap do |t|
        t.inputs({})
        t.outputs({ result: 'string' })
        t.execute do |_inputs|
          { result: 'ok' }
        end
      end
    end

    before do
      tasks[:failing] = failing_task
      tasks[:success] = success_task
    end

    it 'propagates errors from failed tasks' do
      task_specs = [
        { name: :success },
        { name: :failing }
      ]

      expect do
        executor.execute_parallel(task_specs)
      end.to raise_error(/Task 'failing' execution failed/)
    end
  end

  describe 'real-world use cases' do
    context 'ETL pipeline with parallel extraction' do
      let(:extract1) do
        LanguageOperator::Dsl::TaskDefinition.new(:extract_source1).tap do |t|
          t.inputs({})
          t.outputs({ data: 'array' })
          t.execute do |_inputs|
            sleep 0.03
            { data: [1, 2, 3] }
          end
        end
      end

      let(:extract2) do
        LanguageOperator::Dsl::TaskDefinition.new(:extract_source2).tap do |t|
          t.inputs({})
          t.outputs({ data: 'array' })
          t.execute do |_inputs|
            sleep 0.03
            { data: [4, 5, 6] }
          end
        end
      end

      let(:merge_task) do
        LanguageOperator::Dsl::TaskDefinition.new(:merge).tap do |t|
          t.inputs({ sources: 'array' })
          t.outputs({ merged: 'array' })
          t.execute do |inputs|
            merged_data = inputs[:sources].flat_map { |s| s[:data] }
            { merged: merged_data }
          end
        end
      end

      before do
        tasks[:extract_source1] = extract1
        tasks[:extract_source2] = extract2
        tasks[:merge] = merge_task
      end

      it 'extracts in parallel then merges' do
        # Extract in parallel
        sources = executor.execute_parallel([
                                              { name: :extract_source1 },
                                              { name: :extract_source2 }
                                            ])

        # Merge sequentially
        result = executor.execute_task(:merge, inputs: { sources: sources })

        expect(result[:merged]).to eq([1, 2, 3, 4, 5, 6])
      end

      it 'demonstrates parallel speedup' do
        start_time = Time.now
        executor.execute_parallel([
                                    { name: :extract_source1 },
                                    { name: :extract_source2 }
                                  ])
        elapsed = Time.now - start_time

        # Sequential would take ~0.06s, parallel should be ~0.03s
        expect(elapsed).to be < 0.045
      end
    end

    context 'code review with parallel checks' do
      let(:style_check) do
        LanguageOperator::Dsl::TaskDefinition.new(:check_style).tap do |t|
          t.inputs({ code: 'string' })
          t.outputs({ issues: 'integer' })
          t.execute do |_inputs|
            sleep 0.02
            { issues: 3 }
          end
        end
      end

      let(:security_scan) do
        LanguageOperator::Dsl::TaskDefinition.new(:scan_security).tap do |t|
          t.inputs({ code: 'string' })
          t.outputs({ vulnerabilities: 'integer' })
          t.execute do |_inputs|
            sleep 0.02
            { vulnerabilities: 0 }
          end
        end
      end

      let(:coverage_analysis) do
        LanguageOperator::Dsl::TaskDefinition.new(:analyze_coverage).tap do |t|
          t.inputs({ code: 'string' })
          t.outputs({ percentage: 'number' })
          t.execute do |_inputs|
            sleep 0.02
            { percentage: 87.5 }
          end
        end
      end

      before do
        tasks[:check_style] = style_check
        tasks[:scan_security] = security_scan
        tasks[:analyze_coverage] = coverage_analysis
      end

      it 'runs multiple checks in parallel' do
        code = 'def foo; end'

        results = executor.execute_parallel([
                                              { name: :check_style, inputs: { code: code } },
                                              { name: :scan_security, inputs: { code: code } },
                                              { name: :analyze_coverage, inputs: { code: code } }
                                            ])

        expect(results[0][:issues]).to eq(3)
        expect(results[1][:vulnerabilities]).to eq(0)
        expect(results[2][:percentage]).to eq(87.5)
      end
    end
  end
end
