# frozen_string_literal: true

require_relative 'spec_helper'
require 'benchmark'

# Simple performance test to measure improvements
RSpec.describe 'TaskExecutor Performance' do
  let(:agent) do
    Object.new.tap do |a|
      def a.send_message(_prompt)
        'Mock response'
      end

      def a.tools
        []
      end
    end
  end

  it 'measures execution performance improvement' do
    tasks = {}

    # Create tasks for testing
    (1..50).each do |i|
      task_name = :"task_#{i}"
      tasks[task_name] = LanguageOperator::Dsl::TaskDefinition.new(task_name).tap do |task|
        task.inputs(value: 'integer')
        task.outputs(result: 'integer')
        task.execute do |inputs|
          { result: inputs[:value] * 2 }
        end
      end
    end

    # Create executor
    executor = LanguageOperator::Agent::TaskExecutor.new(agent, tasks)

    # Benchmark execution
    time = Benchmark.realtime do
      500.times do
        task_name = :"task_#{rand(1..50)}"
        executor.execute_task(task_name, inputs: { value: 42 })
      end
    end

    puts "\nPerformance Results:"
    puts '=' * 40
    puts "Executed 500 tasks in #{(time * 1000).round(2)}ms"
    puts "Average per task: #{(time * 1000 / 500).round(3)}ms"
    puts "Tasks per second: #{(500 / time).round(0)}"

    # Check TypeCoercion cache stats
    stats = LanguageOperator::TypeCoercion.cache_stats
    puts "\nType Coercion Cache:"
    puts "Size: #{stats[:size]}"
    puts "Hits: #{stats[:hits]}"
    puts "Misses: #{stats[:misses]}"
    puts "Hit rate: #{(stats[:hit_rate] * 100).round(1)}%"

    # Performance should be reasonable
    expect(time).to be < 2.0, "Expected execution time to be under 2 seconds, got #{time}s"
  end
end
