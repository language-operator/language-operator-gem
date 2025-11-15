# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Performance Benchmarks', type: :integration do
  before do
    skip 'Performance benchmarks disabled' unless Integration::Config.performance_benchmarks?
  end

  describe 'Task execution performance baselines' do
    it 'establishes baseline for symbolic task performance' do
      agent_dsl = <<~'RUBY'
        agent "symbolic-benchmark" do
          # Simple computational task
          task :simple_math,
            inputs: { a: 'number', b: 'number' },
            outputs: { result: 'number' }
          do |inputs|
            { result: inputs[:a] + inputs[:b] }
          end
          
          # Complex computational task
          task :complex_math,
            inputs: { numbers: 'array' },
            outputs: { 
              sum: 'number', 
              average: 'number', 
              median: 'number',
              std_dev: 'number'
            }
          do |inputs|
            sorted = inputs[:numbers].sort
            n = inputs[:numbers].length
            sum = inputs[:numbers].sum
            avg = sum.to_f / n
            
            # Calculate standard deviation
            variance = inputs[:numbers].sum { |x| (x - avg) ** 2 } / n
            std_dev = Math.sqrt(variance)
            
            {
              sum: sum,
              average: avg,
              median: sorted[n / 2],
              std_dev: std_dev
            }
          end
          
          # String processing task
          task :string_processing,
            inputs: { text: 'string' },
            outputs: { 
              word_count: 'integer',
              unique_words: 'integer',
              avg_word_length: 'number'
            }
          do |inputs|
            words = inputs[:text].downcase.scan(/\w+/)
            unique = words.uniq
            
            {
              word_count: words.length,
              unique_words: unique.length,
              avg_word_length: words.empty? ? 0 : words.sum(&:length).to_f / words.length
            }
          end
          
          main do |inputs|
            case inputs[:benchmark_type]
            when 'simple'
              execute_task(:simple_math, inputs: { a: 10, b: 32 })
            when 'complex'
              data = (1..1000).map { |i| i * 0.5 + rand() }
              execute_task(:complex_math, inputs: { numbers: data })
            when 'string'
              text = "The quick brown fox jumps over the lazy dog. " * 100
              execute_task(:string_processing, inputs: { text: text })
            end
          end
        end
      RUBY

      agent = create_test_agent('symbolic-benchmark', agent_dsl)

      # Benchmark simple math
      simple_result = measure_performance('Simple symbolic math') do
        (1..100).map { execute_main_with_timing(agent, { benchmark_type: 'simple' }) }
      end

      # Benchmark complex math
      complex_result = measure_performance('Complex symbolic math') do
        execute_main_with_timing(agent, { benchmark_type: 'complex' })
      end

      # Benchmark string processing
      string_result = measure_performance('String processing') do
        execute_main_with_timing(agent, { benchmark_type: 'string' })
      end

      puts "\n=== Symbolic Task Performance Baselines ==="
      puts "Simple math (100 iterations): #{simple_result.class}"
      puts "Complex math (1000 numbers): #{complex_result[:execution_time]}s"
      puts "String processing (500 words): #{string_result[:execution_time]}s"

      # Establish performance expectations
      expect(simple_result).to be_truthy # Should complete without error
      expect(complex_result[:execution_time]).to be < 0.1 # Should be very fast
      expect(string_result[:execution_time]).to be < 0.05 # Should be very fast
    end

    it 'establishes baseline for neural task performance' do
      agent_dsl = <<~RUBY
        agent "neural-benchmark" do
          # Simple neural task
          task :simple_analysis,
            instructions: "Provide a brief analysis of the number",
            inputs: { number: 'number' },
            outputs: { analysis: 'string', category: 'string' }
        #{'  '}
          # Complex neural task
          task :complex_analysis,
            instructions: "Analyze the dataset and provide detailed insights",
            inputs: { data: 'array', context: 'string' },
            outputs: {#{' '}
              insights: 'array',
              summary: 'string',
              confidence: 'number'
            }
        #{'  '}
          main do |inputs|
            case inputs[:benchmark_type]
            when 'simple'
              execute_task(:simple_analysis, inputs: { number: 42 })
            when 'complex'
              data = (1..100).map { |i| { value: i, category: ['A', 'B', 'C'][i % 3] } }
              execute_task(:complex_analysis, inputs: {#{' '}
                data: data,#{' '}
                context: 'Sales data analysis'#{' '}
              })
            end
          end
        end
      RUBY

      agent = create_test_agent('neural-benchmark', agent_dsl)

      # Benchmark simple neural task
      simple_result = measure_performance('Simple neural task') do
        execute_main_with_timing(agent, { benchmark_type: 'simple' })
      end

      # Benchmark complex neural task
      complex_result = measure_performance('Complex neural task') do
        execute_main_with_timing(agent, { benchmark_type: 'complex' })
      end

      puts "\n=== Neural Task Performance Baselines ==="
      puts "Simple neural task: #{simple_result[:execution_time]}s"
      puts "Complex neural task: #{complex_result[:execution_time]}s"

      # Neural tasks will be slower due to LLM calls (even mocked)
      expect(simple_result[:execution_time]).to be < 1.0    # Reasonable for mocked LLM
      expect(complex_result[:execution_time]).to be < 2.0   # More complex but still reasonable
      expect(simple_result[:success]).to be(true)
      expect(complex_result[:success]).to be(true)
    end

    it 'compares symbolic vs neural performance for equivalent tasks' do
      # Symbolic version
      symbolic_dsl = <<~RUBY
        agent "symbolic-sentiment" do
          task :analyze_sentiment,
            inputs: { text: 'string' },
            outputs: { sentiment: 'string', confidence: 'number' }
          do |inputs|
            text = inputs[:text].downcase
        #{'    '}
            positive_words = ['good', 'great', 'excellent', 'amazing', 'wonderful', 'fantastic']
            negative_words = ['bad', 'terrible', 'awful', 'horrible', 'disappointing']
        #{'    '}
            positive_count = positive_words.count { |word| text.include?(word) }
            negative_count = negative_words.count { |word| text.include?(word) }
        #{'    '}
            if positive_count > negative_count
              sentiment = 'positive'
              confidence = [0.6 + (positive_count * 0.1), 1.0].min
            elsif negative_count > positive_count
              sentiment = 'negative'#{'  '}
              confidence = [0.6 + (negative_count * 0.1), 1.0].min
            else
              sentiment = 'neutral'
              confidence = 0.5
            end
        #{'    '}
            { sentiment: sentiment, confidence: confidence }
          end
        #{'  '}
          main do |inputs|
            execute_task(:analyze_sentiment, inputs: inputs)
          end
        end
      RUBY

      # Neural version
      neural_dsl = <<~RUBY
        agent "neural-sentiment" do
          task :analyze_sentiment,
            instructions: "Analyze the sentiment of the given text and provide a confidence score",
            inputs: { text: 'string' },
            outputs: { sentiment: 'string', confidence: 'number' }
        #{'  '}
          main do |inputs|
            execute_task(:analyze_sentiment, inputs: inputs)
          end
        end
      RUBY

      symbolic_agent = create_test_agent('symbolic-sentiment', symbolic_dsl)
      neural_agent = create_test_agent('neural-sentiment', neural_dsl)

      test_text = "This is a really great product! I'm amazed by how wonderful it is."

      # Performance comparison
      benchmark_comparison(
        'Symbolic sentiment analysis',
        -> { execute_main_with_timing(symbolic_agent, { text: test_text }) },
        'Neural sentiment analysis',
        -> { execute_main_with_timing(neural_agent, { text: test_text }) }
      )

      # Both should provide valid results
      symbolic_result = execute_main_with_timing(symbolic_agent, { text: test_text })
      neural_result = execute_main_with_timing(neural_agent, { text: test_text })

      expect(symbolic_result[:success]).to be(true)
      expect(neural_result[:success]).to be(true)
      expect(symbolic_result[:output][:sentiment]).to be_in(%w[positive negative neutral])
      expect(neural_result[:output][:sentiment]).to be_in(%w[positive negative neutral])
    end
  end

  describe 'Parallel execution performance' do
    it 'measures parallel execution scalability' do
      agent_dsl = <<~'RUBY'
        agent "scalability-test" do
          task :io_simulation,
            inputs: { id: 'integer', delay: 'number' },
            outputs: { result: 'string', actual_delay: 'number' }
          do |inputs|
            start_time = Time.now
            sleep(inputs[:delay])
            end_time = Time.now
            
            {
              result: "Task #{inputs[:id]} completed",
              actual_delay: ((end_time - start_time) * 1000).round(2)
            }
          end
          
          main do |inputs|
            task_count = inputs[:task_count]
            delay = inputs[:delay] || 0.05  # 50ms
            mode = inputs[:mode]
            
            if mode == 'sequential'
              # Sequential execution
              results = []
              task_count.times do |i|
                result = execute_task(:io_simulation, inputs: { id: i, delay: delay })
                results << result
              end
              { results: results, mode: 'sequential' }
            else
              # Parallel execution
              results = execute_parallel(
                task_count.times.map do |i|
                  { name: :io_simulation, inputs: { id: i, delay: delay } }
                end
              )
              { results: results, mode: 'parallel' }
            end
          end
        end
      RUBY

      agent = create_test_agent('scalability-test', agent_dsl)

      # Test different scales
      [2, 4, 8, 16].each do |task_count|
        puts "\n--- Testing #{task_count} tasks ---"

        # Sequential baseline
        sequential_result = measure_performance("Sequential (#{task_count} tasks)") do
          execute_main_with_timing(agent, {
                                     task_count: task_count,
                                     delay: 0.02, # 20ms per task
                                     mode: 'sequential'
                                   })
        end

        # Parallel comparison
        parallel_result = measure_performance("Parallel (#{task_count} tasks)") do
          execute_main_with_timing(agent, {
                                     task_count: task_count,
                                     delay: 0.02, # 20ms per task
                                     mode: 'parallel'
                                   })
        end

        # Calculate speedup
        speedup = sequential_result[:execution_time] / parallel_result[:execution_time]
        puts "Speedup: #{speedup.round(2)}x"

        # Parallel should be faster for I/O-bound tasks
        expect(parallel_result[:execution_time]).to be < (sequential_result[:execution_time] * 0.8)
        expect(speedup).to be > 1.2 # At least 20% speedup
      end
    end
  end

  describe 'Memory and resource usage' do
    it 'measures memory usage patterns' do
      agent_dsl = <<~'RUBY'
        agent "memory-test" do
          task :memory_intensive,
            inputs: { size: 'integer' },
            outputs: { allocated_mb: 'number', peak_objects: 'integer' }
          do |inputs|
            gc_start = GC.stat
            
            # Allocate memory
            large_arrays = []
            inputs[:size].times do |i|
              large_arrays << Array.new(1000, "data_#{i}")
            end
            
            gc_end = GC.stat
            
            # Estimate memory usage (rough approximation)
            allocated_mb = (large_arrays.flatten.sum(&:bytesize)) / (1024.0 * 1024.0)
            object_delta = gc_end[:heap_live_slots] - gc_start[:heap_live_slots]
            
            {
              allocated_mb: allocated_mb.round(2),
              peak_objects: object_delta
            }
          end
          
          main do |inputs|
            result = execute_task(:memory_intensive, inputs: inputs)
            
            # Force garbage collection
            GC.start
            
            result
          end
        end
      RUBY

      agent = create_test_agent('memory-test', agent_dsl)

      # Test different memory allocation sizes
      [10, 50, 100].each do |size|
        result = measure_performance("Memory allocation (#{size} arrays)") do
          execute_main_with_timing(agent, { size: size })
        end

        puts "Size: #{size}, Allocated: #{result[:output][:allocated_mb]}MB, Objects: #{result[:output][:peak_objects]}"

        expect(result[:success]).to be(true)
        expect(result[:output][:allocated_mb]).to be > 0
        expect(result[:execution_time]).to be < 1.0 # Should complete quickly
      end
    end

    it 'measures task overhead vs useful work' do
      # Minimal work task
      minimal_dsl = <<~RUBY
        agent "minimal-work" do
          task :minimal_task,
            inputs: { input: 'string' },
            outputs: { output: 'string' }
          do |inputs|
            { output: inputs[:input] }  # Just pass through
          end
        #{'  '}
          main do |inputs|
            execute_task(:minimal_task, inputs: inputs)
          end
        end
      RUBY

      # Substantial work task
      substantial_dsl = <<~'RUBY'
        agent "substantial-work" do
          task :substantial_task,
            inputs: { input: 'string' },
            outputs: { output: 'string', work_done: 'integer' }
          do |inputs|
            # Do actual computation
            result = ""
            work_counter = 0
            
            1000.times do |i|
              result += "#{inputs[:input]}_#{i}_"
              work_counter += i
            end
            
            {
              output: result[0..100],  # Truncate for output
              work_done: work_counter
            }
          end
          
          main do |inputs|
            execute_task(:substantial_task, inputs: inputs)
          end
        end
      RUBY

      minimal_agent = create_test_agent('minimal-work', minimal_dsl)
      substantial_agent = create_test_agent('substantial-work', substantial_dsl)

      test_input = { input: 'test' }

      # Measure overhead vs work
      minimal_time = measure_performance('Minimal work (overhead measurement)') do
        execute_main_with_timing(minimal_agent, test_input)
      end

      substantial_time = measure_performance('Substantial work') do
        execute_main_with_timing(substantial_agent, test_input)
      end

      # Calculate overhead percentage
      overhead_ratio = minimal_time[:execution_time] / substantial_time[:execution_time]
      puts "\nOverhead ratio: #{(overhead_ratio * 100).round(1)}%"

      # Overhead should be reasonable
      expect(overhead_ratio).to be < 0.5 # Overhead should be less than 50% of substantial work
      expect(minimal_time[:execution_time]).to be < 0.01 # Minimal overhead should be very fast
    end
  end

  describe 'Performance regression detection' do
    it 'establishes performance baselines for regression testing' do
      # This test establishes baseline performance metrics that can be
      # compared in future test runs to detect performance regressions

      baselines = {}

      # Symbolic task baseline
      symbolic_agent = create_test_agent('baseline-symbolic', <<~RUBY
        agent "baseline-symbolic" do
          task :baseline_task do |inputs|
            { result: (1..1000).sum }
          end
        #{'  '}
          main do |inputs|
            execute_task(:baseline_task)
          end
        end
      RUBY
      )

      symbolic_result = measure_performance('Symbolic baseline') do
        (1..10).map { execute_main_with_timing(symbolic_agent) }
      end

      # Neural task baseline (mocked)
      neural_agent = create_test_agent('baseline-neural', <<~RUBY
        agent "baseline-neural" do
          task :baseline_task,
            instructions: "Process the input",
            inputs: { input: 'string' },
            outputs: { result: 'string' }
        #{'  '}
          main do |inputs|
            execute_task(:baseline_task, inputs: { input: 'baseline test' })
          end
        end
      RUBY
      )

      neural_result = measure_performance('Neural baseline') do
        (1..5).map { execute_main_with_timing(neural_agent) }
      end

      # Store baselines for future comparison
      baselines[:symbolic_avg] = if symbolic_result.is_a?(Array)
                                   symbolic_result.sum { |r| r[:execution_time] } / symbolic_result.length
                                 else
                                   symbolic_result[:execution_time]
                                 end

      baselines[:neural_avg] = if neural_result.is_a?(Array)
                                 neural_result.sum { |r| r[:execution_time] } / neural_result.length
                               else
                                 neural_result[:execution_time]
                               end

      puts "\n=== Performance Baselines ==="
      puts "Symbolic task average: #{(baselines[:symbolic_avg] * 1000).round(2)}ms"
      puts "Neural task average: #{(baselines[:neural_avg] * 1000).round(2)}ms"

      # Write baselines to file for CI comparison
      baseline_file = '/tmp/performance_baselines.json'
      File.write(baseline_file, JSON.pretty_generate({
                                                       timestamp: Time.now.iso8601,
                                                       git_commit: `git rev-parse HEAD 2>/dev/null`.strip,
                                                       baselines: baselines
                                                     }))

      puts "Baselines written to: #{baseline_file}"

      # Verify baselines are reasonable
      expect(baselines[:symbolic_avg]).to be < 0.1    # Very fast for symbolic
      expect(baselines[:neural_avg]).to be < 1.0      # Reasonable for neural (mocked)
    end
  end
end
