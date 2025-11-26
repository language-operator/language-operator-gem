# frozen_string_literal: true

require 'benchmark'
require 'memory_profiler'
require_relative '../spec_helper'
require_relative '../../lib/language_operator'

# Performance benchmarks for TaskExecutor
#
# Run with: bundle exec ruby spec/benchmarks/task_executor_benchmark.rb
# Or: bundle exec rspec spec/benchmarks/task_executor_benchmark.rb
#
# This benchmark suite establishes baseline performance metrics for:
# - Task lookup performance
# - Type coercion overhead
# - Symbolic task execution
# - Parallel execution scaling
# - Memory allocation patterns
class TaskExecutorBenchmark
  def initialize
    setup_tasks
    setup_executor
  end

  def run_all_benchmarks
    puts '=' * 80
    puts 'TaskExecutor Performance Benchmarks'
    puts '=' * 80
    puts

    benchmark_task_lookup
    benchmark_type_coercion
    benchmark_symbolic_execution
    benchmark_parallel_execution
    benchmark_memory_usage

    puts '=' * 80
    puts 'Benchmark Complete'
    puts '=' * 80
  end

  private

  def setup_tasks
    @tasks = {}

    # Simple symbolic task for basic benchmarking
    @tasks[:simple] = LanguageOperator::Dsl::TaskDefinition.new(:simple)
    @tasks[:simple].inputs(value: 'integer')
    @tasks[:simple].outputs(result: 'integer')
    @tasks[:simple].execute do |inputs|
      { result: inputs[:value] * 2 }
    end

    # Type-heavy task for coercion benchmarking
    @tasks[:type_heavy] = LanguageOperator::Dsl::TaskDefinition.new(:type_heavy)
    @tasks[:type_heavy].inputs(
      str: 'string',
      num: 'number',
      int: 'integer',
      bool: 'boolean',
      arr: 'array',
      hash: 'hash'
    )
    @tasks[:type_heavy].outputs(processed: 'hash')
    @tasks[:type_heavy].execute do |inputs|
      { processed: inputs }
    end

    # I/O simulation task for parallel benchmarking
    @tasks[:io_sim] = LanguageOperator::Dsl::TaskDefinition.new(:io_sim)
    @tasks[:io_sim].inputs(delay: 'number')
    @tasks[:io_sim].outputs(completed: 'boolean')
    @tasks[:io_sim].execute do |inputs|
      sleep(inputs[:delay])
      { completed: true }
    end

    # Create many tasks for lookup benchmarking
    (1..100).each do |i|
      task_name = :"task_#{i}"
      @tasks[task_name] = LanguageOperator::Dsl::TaskDefinition.new(task_name)
      @tasks[task_name].inputs(value: 'integer')
      @tasks[task_name].outputs(result: 'integer')
      @tasks[task_name].execute do |inputs|
        { result: inputs[:value] + i }
      end
    end
  end

  def setup_executor
    # Mock agent with minimal functionality
    agent = Object.new
    def agent.send_message(_prompt)
      'Mock response'
    end

    def agent.tools
      []
    end

    @executor = LanguageOperator::Agent::TaskExecutor.new(agent, @tasks)
  end

  def benchmark_task_lookup
    puts '1. Task Lookup Performance'
    puts '-' * 40

    # Test current linear search performance
    Benchmark.bm(25) do |x|
      x.report('100 tasks, 1000 lookups:') do
        1000.times do
          @executor.execute_task(:task_50, inputs: { value: 42 })
        end
      end

      x.report('100 tasks, worst case:') do
        1000.times do
          @executor.execute_task(:task_100, inputs: { value: 42 })
        end
      end
    end
    puts
  end

  def benchmark_type_coercion
    puts '2. Type Coercion Performance'
    puts '-' * 40

    test_inputs = {
      str: 'test string',
      num: '3.14159',
      int: '42',
      bool: 'true',
      arr: [1, 2, 3],
      hash: { key: 'value' }
    }

    Benchmark.bm(25) do |x|
      x.report('1000 type coercions:') do
        1000.times do
          @executor.execute_task(:type_heavy, inputs: test_inputs)
        end
      end

      # Test individual coercion performance
      x.report('String coercion x10000:') do
        10_000.times do
          LanguageOperator::TypeCoercion.coerce('test', 'string')
        end
      end

      x.report('Integer coercion x10000:') do
        10_000.times do
          LanguageOperator::TypeCoercion.coerce('42', 'integer')
        end
      end

      x.report('Boolean coercion x10000:') do
        10_000.times do
          LanguageOperator::TypeCoercion.coerce('true', 'boolean')
        end
      end
    end
    puts
  end

  def benchmark_symbolic_execution
    puts '3. Symbolic Task Execution'
    puts '-' * 40

    Benchmark.bm(25) do |x|
      x.report('1000 simple tasks:') do
        1000.times do |i|
          @executor.execute_task(:simple, inputs: { value: i })
        end
      end

      x.report('100 heavy tasks:') do
        test_inputs = {
          str: 'test',
          num: 3.14,
          int: 42,
          bool: true,
          arr: [1, 2, 3],
          hash: { key: 'value' }
        }

        100.times do
          @executor.execute_task(:type_heavy, inputs: test_inputs)
        end
      end
    end
    puts
  end

  def benchmark_parallel_execution
    puts '4. Parallel Execution Scaling'
    puts '-' * 40

    # Test parallel vs sequential execution
    parallel_tasks = Array.new(8) { { name: :io_sim, inputs: { delay: 0.01 } } }

    Benchmark.bm(25) do |x|
      x.report('8 tasks sequential:') do
        parallel_tasks.each do |task_spec|
          @executor.execute_task(task_spec[:name], inputs: task_spec[:inputs])
        end
      end

      x.report('8 tasks parallel (2t):') do
        @executor.execute_parallel(parallel_tasks, in_threads: 2)
      end

      x.report('8 tasks parallel (4t):') do
        @executor.execute_parallel(parallel_tasks, in_threads: 4)
      end

      x.report('8 tasks parallel (8t):') do
        @executor.execute_parallel(parallel_tasks, in_threads: 8)
      end
    end
    puts
  end

  def benchmark_memory_usage
    puts '5. Memory Usage Analysis'
    puts '-' * 40

    # Baseline memory usage
    puts 'Baseline memory usage:'
    baseline_report = MemoryProfiler.report do
      # Just create executor
      @executor
    end
    puts "  Objects allocated: #{baseline_report.total_allocated}"
    puts "  Memory allocated: #{baseline_report.total_allocated_memsize} bytes"
    puts

    # Task execution memory usage
    puts '100 simple task executions:'
    task_report = MemoryProfiler.report do
      100.times do |i|
        @executor.execute_task(:simple, inputs: { value: i })
      end
    end
    puts "  Objects allocated: #{task_report.total_allocated}"
    puts "  Memory allocated: #{task_report.total_allocated_memsize} bytes"
    puts "  Per task: #{task_report.total_allocated / 100.0} objects, #{task_report.total_allocated_memsize / 100.0} bytes"
    puts

    # Type coercion memory usage
    puts '1000 type coercions:'
    coercion_report = MemoryProfiler.report do
      1000.times do
        LanguageOperator::TypeCoercion.coerce('42', 'integer')
        LanguageOperator::TypeCoercion.coerce('3.14', 'number')
        LanguageOperator::TypeCoercion.coerce('true', 'boolean')
      end
    end
    puts "  Objects allocated: #{coercion_report.total_allocated}"
    puts "  Memory allocated: #{coercion_report.total_allocated_memsize} bytes"
    puts "  Per coercion: #{coercion_report.total_allocated / 3000.0} objects, #{coercion_report.total_allocated_memsize / 3000.0} bytes"
    puts

    # Show top allocations
    puts 'Top memory allocations in task execution:'
    task_report.allocated_memory_by_class.first(5).each do |klass, size|
      puts "  #{klass}: #{size} bytes"
    end
    puts
  end
end

# Run benchmarks if called directly
TaskExecutorBenchmark.new.run_all_benchmarks if $PROGRAM_NAME == __FILE__

# RSpec integration for CI
RSpec.describe 'TaskExecutor Performance Benchmarks', type: :benchmark do
  it 'runs performance benchmarks and documents baseline' do
    benchmark = TaskExecutorBenchmark.new

    expect do
      benchmark.run_all_benchmarks
    end.not_to raise_error
  end
end
