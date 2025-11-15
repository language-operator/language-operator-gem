# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Parallel Execution', type: :integration do
  describe 'Implicit parallel execution' do
    it 'automatically detects and executes independent tasks in parallel' do
      agent_dsl = <<~RUBY
        agent "parallel-processor" do
          description "Agent that can execute independent tasks in parallel"
        #{'  '}
          # Independent task 1
          task :fetch_source_a,
            inputs: { delay: 'number' },
            outputs: { data: 'string', source: 'string' }
          do |inputs|
            sleep(inputs[:delay] / 1000.0) if inputs[:delay] > 0  # Simulate I/O delay
            {
              data: "Data from source A",
              source: "source_a"
            }
          end
        #{'  '}
          # Independent task 2#{'  '}
          task :fetch_source_b,
            inputs: { delay: 'number' },
            outputs: { data: 'string', source: 'string' }
          do |inputs|
            sleep(inputs[:delay] / 1000.0) if inputs[:delay] > 0  # Simulate I/O delay
            {
              data: "Data from source B",#{' '}
              source: "source_b"
            }
          end
        #{'  '}
          # Independent task 3
          task :fetch_source_c,
            inputs: { delay: 'number' },
            outputs: { data: 'string', source: 'string' }
          do |inputs|
            sleep(inputs[:delay] / 1000.0) if inputs[:delay] > 0  # Simulate I/O delay
            {
              data: "Data from source C",
              source: "source_c"
            }
          end
        #{'  '}
          # Dependent task that merges results
          task :merge_sources,
            inputs: { source_a: 'hash', source_b: 'hash', source_c: 'hash' },
            outputs: { merged: 'hash', sources: 'array' }
          do |inputs|
            {
              merged: {
                combined_data: [
                  inputs[:source_a][:data],
                  inputs[:source_b][:data],#{' '}
                  inputs[:source_c][:data]
                ].join(' + ')
              },
              sources: [
                inputs[:source_a][:source],
                inputs[:source_b][:source],
                inputs[:source_c][:source]
              ]
            }
          end
        #{'  '}
          main do |inputs|
            # These three tasks are independent and should run in parallel
            delay = inputs[:delay] || 100
        #{'    '}
            source_a = execute_task(:fetch_source_a, inputs: { delay: delay })
            source_b = execute_task(:fetch_source_b, inputs: { delay: delay })
            source_c = execute_task(:fetch_source_c, inputs: { delay: delay })
        #{'    '}
            # This task depends on all three above and runs after they complete
            execute_task(:merge_sources, inputs: {
              source_a: source_a,
              source_b: source_b,
              source_c: source_c
            })
          end
        end
      RUBY

      agent = create_test_agent('parallel-processor', agent_dsl)

      # Measure execution time to verify parallelization
      result = measure_performance('Parallel independent tasks') do
        execute_main_with_timing(agent, { delay: 50 }) # 50ms delay per task
      end

      expect(result[:success]).to be(true)
      expect(result[:output][:merged][:combined_data]).to include('source A', 'source B', 'source C')
      expect(result[:output][:sources]).to contain_exactly('source_a', 'source_b', 'source_c')

      # With parallel execution, total time should be much less than 3 * 50ms = 150ms
      # Should be closer to ~50ms (plus overhead)
      expect(result[:execution_time]).to be < 0.12 # Less than 120ms indicates parallelization
    end

    it 'respects task dependencies in parallel execution' do
      agent_dsl = <<~'RUBY'
        agent "dependency-aware" do
          # Level 1: Independent initial tasks
          task :init_a do |inputs|
            { result: 'A', level: 1 }
          end
          
          task :init_b do |inputs|
            { result: 'B', level: 1 }
          end
          
          # Level 2: Depends on init_a
          task :process_a,
            inputs: { init_result: 'hash' },
            outputs: { result: 'string', level: 'integer' }
          do |inputs|
            {
              result: "Processed_#{inputs[:init_result][:result]}",
              level: 2
            }
          end
          
          # Level 2: Depends on init_b
          task :process_b,
            inputs: { init_result: 'hash' },
            outputs: { result: 'string', level: 'integer' }
          do |inputs|
            {
              result: "Processed_#{inputs[:init_result][:result]}", 
              level: 2
            }
          end
          
          # Level 3: Depends on both process_a and process_b
          task :final_merge,
            inputs: { a_result: 'hash', b_result: 'hash' },
            outputs: { combined: 'string', level: 'integer' }
          do |inputs|
            {
              combined: "#{inputs[:a_result][:result]}_#{inputs[:b_result][:result]}",
              level: 3
            }
          end
          
          main do |inputs|
            # Level 1: These can run in parallel
            result_a = execute_task(:init_a)
            result_b = execute_task(:init_b)
            
            # Level 2: These can run in parallel after level 1 completes
            processed_a = execute_task(:process_a, inputs: { init_result: result_a })
            processed_b = execute_task(:process_b, inputs: { init_result: result_b })
            
            # Level 3: This must wait for level 2 to complete
            execute_task(:final_merge, inputs: {
              a_result: processed_a,
              b_result: processed_b
            })
          end
        end
      RUBY

      agent = create_test_agent('dependency-aware', agent_dsl)

      result = execute_main_with_timing(agent)

      expect(result[:success]).to be(true)
      expect(result[:output][:combined]).to eq('Processed_A_Processed_B')
      expect(result[:output][:level]).to eq(3)
    end
  end

  describe 'Explicit parallel execution' do
    it 'supports explicit execute_parallel for user-controlled concurrency' do
      agent_dsl = <<~'RUBY'
        agent "explicit-parallel" do
          # Task that simulates I/O work
          task :io_task,
            inputs: { id: 'string', delay: 'number' },
            outputs: { result: 'string', duration: 'number' }
          do |inputs|
            start_time = Time.now
            sleep(inputs[:delay] / 1000.0) if inputs[:delay] > 0
            end_time = Time.now
            
            {
              result: "Task #{inputs[:id]} completed",
              duration: ((end_time - start_time) * 1000).round(2)
            }
          end
          
          # Task that processes results
          task :combine_results,
            inputs: { results: 'array' },
            outputs: { combined: 'string', total_duration: 'number' }
          do |inputs|
            {
              combined: inputs[:results].map { |r| r[:result] }.join(' | '),
              total_duration: inputs[:results].sum { |r| r[:duration] }
            }
          end
          
          main do |inputs|
            task_count = inputs[:task_count] || 3
            delay = inputs[:delay] || 50
            
            # Explicit parallel execution
            parallel_results = execute_parallel(
              task_count.times.map do |i|
                {
                  name: :io_task,
                  inputs: { id: "task_#{i+1}", delay: delay }
                }
              end
            )
            
            # Process combined results
            execute_task(:combine_results, inputs: { results: parallel_results })
          end
        end
      RUBY

      agent = create_test_agent('explicit-parallel', agent_dsl)

      result = measure_performance('Explicit parallel execution') do
        execute_main_with_timing(agent, { task_count: 4, delay: 30 })
      end

      expect(result[:success]).to be(true)
      expect(result[:output][:combined]).to include('Task 1', 'Task 2', 'Task 3', 'Task 4')

      # With parallel execution, should complete in ~30ms + overhead
      # Sequential would take ~120ms (4 * 30ms)
      expect(result[:execution_time]).to be < 0.08 # Less than 80ms indicates parallelization
    end

    it 'handles mixed parallel and sequential execution patterns' do
      agent_dsl = <<~'RUBY'
        agent "mixed-execution" do
          # Initial setup task
          task :setup,
            inputs: { config: 'hash' },
            outputs: { prepared_data: 'array', batch_size: 'integer' }
          do |inputs|
            count = inputs[:config][:item_count] || 6
            {
              prepared_data: (1..count).map { |i| "item_#{i}" },
              batch_size: inputs[:config][:batch_size] || 2
            }
          end
          
          # Parallel processing task
          task :process_batch,
            inputs: { batch: 'array', batch_id: 'integer' },
            outputs: { processed: 'array', batch_id: 'integer', count: 'integer' }
          do |inputs|
            processed = inputs[:batch].map { |item| "processed_#{item}" }
            sleep(0.02)  # Simulate processing time
            
            {
              processed: processed,
              batch_id: inputs[:batch_id],
              count: processed.length
            }
          end
          
          # Final aggregation task
          task :aggregate_results,
            inputs: { batch_results: 'array' },
            outputs: { all_items: 'array', summary: 'hash' }
          do |inputs|
            all_processed = inputs[:batch_results].flat_map { |br| br[:processed] }
            
            {
              all_items: all_processed,
              summary: {
                total_items: all_processed.length,
                batch_count: inputs[:batch_results].length,
                items_per_batch: all_processed.length.to_f / inputs[:batch_results].length
              }
            }
          end
          
          main do |inputs|
            # Sequential setup
            setup_result = execute_task(:setup, inputs: inputs)
            
            # Parallel batch processing
            batches = setup_result[:prepared_data].each_slice(setup_result[:batch_size]).to_a
            batch_results = execute_parallel(
              batches.map.with_index do |batch, i|
                {
                  name: :process_batch,
                  inputs: { batch: batch, batch_id: i + 1 }
                }
              end
            )
            
            # Sequential aggregation
            execute_task(:aggregate_results, inputs: { batch_results: batch_results })
          end
        end
      RUBY

      agent = create_test_agent('mixed-execution', agent_dsl)

      result = measure_performance('Mixed parallel/sequential execution') do
        execute_main_with_timing(agent, {
                                   config: { item_count: 8, batch_size: 2 }
                                 })
      end

      expect(result[:success]).to be(true)
      expect(result[:output][:all_items].length).to eq(8)
      expect(result[:output][:summary][:batch_count]).to eq(4)
      expect(result[:output][:summary][:items_per_batch]).to eq(2.0)

      # All items should be processed
      expect(result[:output][:all_items]).to all(start_with('processed_item_'))
    end
  end

  describe 'Parallel execution performance' do
    it 'demonstrates significant performance improvements for I/O-bound tasks' do
      # Create sequential and parallel versions of the same workflow

      sequential_dsl = <<~'RUBY'
        agent "sequential" do
          task :slow_task,
            inputs: { id: 'string' },
            outputs: { result: 'string' }
          do |inputs|
            sleep(0.05)  # 50ms I/O simulation
            { result: "Processed #{inputs[:id]}" }
          end
          
          main do |inputs|
            results = []
            5.times do |i|
              result = execute_task(:slow_task, inputs: { id: "item_#{i}" })
              results << result[:result]
            end
            { combined: results.join(', ') }
          end
        end
      RUBY

      parallel_dsl = <<~'RUBY'
        agent "parallel" do
          task :slow_task,
            inputs: { id: 'string' },
            outputs: { result: 'string' }
          do |inputs|
            sleep(0.05)  # 50ms I/O simulation
            { result: "Processed #{inputs[:id]}" }
          end
          
          main do |inputs|
            results = execute_parallel(
              5.times.map do |i|
                { name: :slow_task, inputs: { id: "item_#{i}" } }
              end
            )
            { combined: results.map { |r| r[:result] }.join(', ') }
          end
        end
      RUBY

      sequential_agent = create_test_agent('sequential', sequential_dsl)
      parallel_agent = create_test_agent('parallel', parallel_dsl)

      # Benchmark the performance difference
      benchmark_comparison(
        'Sequential execution',
        -> { execute_main_with_timing(sequential_agent) },
        'Parallel execution',
        -> { execute_main_with_timing(parallel_agent) }
      )

      # Both should produce same results
      seq_result = execute_main_with_timing(sequential_agent)
      par_result = execute_main_with_timing(parallel_agent)

      expect(seq_result[:success]).to be(true)
      expect(par_result[:success]).to be(true)

      # Results should be equivalent (order might differ for parallel)
      seq_items = seq_result[:output][:combined].split(', ').sort
      par_items = par_result[:output][:combined].split(', ').sort
      expect(par_items).to eq(seq_items)

      # Parallel should be significantly faster
      # Sequential: ~250ms (5 * 50ms), Parallel: ~50ms + overhead
      expect(par_result[:execution_time]).to be < (seq_result[:execution_time] * 0.4)
    end

    it 'handles thread pool sizing and resource constraints' do
      agent_dsl = <<~RUBY
        agent "thread-pool-test" do
          task :cpu_intensive,
            inputs: { workload: 'integer' },
            outputs: { result: 'integer', thread_id: 'string' }
          do |inputs|
            # Simulate CPU work
            sum = 0
            inputs[:workload].times { |i| sum += i }
        #{'    '}
            {
              result: sum,
              thread_id: Thread.current.object_id.to_s
            }
          end
        #{'  '}
          main do |inputs|
            task_count = inputs[:task_count] || 10
            workload = inputs[:workload] || 1000
        #{'    '}
            results = execute_parallel(
              task_count.times.map do |i|
                { name: :cpu_intensive, inputs: { workload: workload } }
              end,
              in_threads: 4  # Limit thread pool size
            )
        #{'    '}
            unique_threads = results.map { |r| r[:thread_id] }.uniq
        #{'    '}
            {
              results_count: results.length,
              unique_threads: unique_threads.length,
              total_sum: results.sum { |r| r[:result] },
              thread_reuse: results.length > unique_threads.length
            }
          end
        end
      RUBY

      agent = create_test_agent('thread-pool-test', agent_dsl)

      result = measure_performance('Thread pool management') do
        execute_main_with_timing(agent, { task_count: 8, workload: 500 })
      end

      expect(result[:success]).to be(true)
      expect(result[:output][:results_count]).to eq(8)

      # Should use thread pool efficiently (reuse threads)
      expect(result[:output][:unique_threads]).to be <= 4
      expect(result[:output][:thread_reuse]).to be(true)
    end
  end

  describe 'Error handling in parallel execution' do
    it 'handles partial failures gracefully in parallel tasks' do
      agent_dsl = <<~'RUBY'
        agent "failure-tolerant" do
          task :potentially_failing_task,
            inputs: { id: 'integer', should_fail: 'boolean' },
            outputs: { result: 'string', success: 'boolean' }
          do |inputs|
            if inputs[:should_fail]
              raise StandardError, "Task #{inputs[:id]} failed"
            end
            
            {
              result: "Task #{inputs[:id]} succeeded",
              success: true
            }
          end
          
          main do |inputs|
            begin
              results = execute_parallel([
                { name: :potentially_failing_task, inputs: { id: 1, should_fail: false } },
                { name: :potentially_failing_task, inputs: { id: 2, should_fail: true } },  # This will fail
                { name: :potentially_failing_task, inputs: { id: 3, should_fail: false } },
                { name: :potentially_failing_task, inputs: { id: 4, should_fail: false } }
              ])
              
              { success: true, results: results }
            rescue => e
              {
                success: false,
                error: e.message,
                partial_completion: true
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('failure-tolerant', agent_dsl)

      result = execute_main_with_timing(agent)

      # The main execution should handle the error
      expect(result[:success]).to be(true)
      expect(result[:output][:success]).to be(false)
      expect(result[:output][:error]).to include('Task 2 failed')
      expect(result[:output][:partial_completion]).to be(true)
    end

    it 'provides detailed error information for debugging parallel failures' do
      agent_dsl = <<~'RUBY'
        agent "detailed-error-handling" do
          task :error_prone_task,
            inputs: { id: 'integer', error_type: 'string' },
            outputs: { result: 'string' }
          do |inputs|
            case inputs[:error_type]
            when 'timeout'
              sleep(2)  # Simulate timeout
              { result: "Task #{inputs[:id]} completed" }
            when 'exception'
              raise ArgumentError, "Invalid argument for task #{inputs[:id]}"
            when 'validation'
              # Return invalid output schema
              { wrong_field: "Task #{inputs[:id]} output" }
            else
              { result: "Task #{inputs[:id]} succeeded" }
            end
          end
          
          main do |inputs|
            begin
              results = execute_parallel([
                { name: :error_prone_task, inputs: { id: 1, error_type: 'success' } },
                { name: :error_prone_task, inputs: { id: 2, error_type: 'exception' } },
                { name: :error_prone_task, inputs: { id: 3, error_type: 'validation' } }
              ], timeout: 1.0)  # 1 second timeout
              
              { success: true, results: results }
            rescue => e
              {
                success: false,
                error_class: e.class.name,
                error_message: e.message,
                backtrace_preview: e.backtrace&.first(3)
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('detailed-error-handling', agent_dsl)

      result = execute_main_with_timing(agent)

      expect(result[:success]).to be(true)
      expect(result[:output][:success]).to be(false)
      expect(result[:output][:error_class]).to be_a(String)
      expect(result[:output][:error_message]).to be_a(String)
    end
  end
end
