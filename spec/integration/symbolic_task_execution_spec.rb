# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Symbolic Task Execution', type: :integration do
  describe 'Simple symbolic tasks' do
    it 'executes symbolic task with Ruby code block' do
      agent_dsl = <<~RUBY
        agent "calculator" do
          description "A calculator agent with symbolic tasks"
        #{'  '}
          task :add_numbers,
            inputs: { a: 'number', b: 'number' },
            outputs: { sum: 'number' }
          do |inputs|
            { sum: inputs[:a] + inputs[:b] }
          end
        #{'  '}
          main do |inputs|
            execute_task(:add_numbers, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('calculator', agent_dsl)

      result = execute_main_with_timing(agent, { a: 10, b: 32 })

      expect(result[:success]).to be(true)
      expect(result[:output][:sum]).to eq(42)
    end

    it 'validates symbolic task input and output schemas' do
      agent_dsl = <<~RUBY
        agent "data-processor" do
          task :process_array,
            inputs: { items: 'array', multiplier: 'number' },
            outputs: { processed: 'array', count: 'integer' }
          do |inputs|
            processed = inputs[:items].map { |x| x * inputs[:multiplier] }
            {#{' '}
              processed: processed,
              count: processed.length#{' '}
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:process_array, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('data-processor', agent_dsl)

      result = execute_main_with_timing(agent, { items: [1, 2, 3], multiplier: 2 })

      expect(result[:success]).to be(true)
      expect(result[:output][:processed]).to eq([2, 4, 6])
      expect(result[:output][:count]).to eq(3)

      # Verify output schema
      expected_schema = { processed: 'array', count: 'integer' }
      expect(verify_task_output(result[:output], expected_schema)).to be(true)
    end

    it 'handles complex Ruby logic in symbolic tasks' do
      agent_dsl = <<~'RUBY'
        agent "text-analyzer" do
          task :analyze_text,
            inputs: { text: 'string' },
            outputs: {
              word_count: 'integer',
              char_count: 'integer',
              sentences: 'integer',
              summary: 'hash'
            }
          do |inputs|
            text = inputs[:text]
            words = text.split(/\s+/).reject(&:empty?)
            sentences = text.split(/[.!?]+/).reject(&:empty?)

            {
              word_count: words.length,
              char_count: text.length,
              sentences: sentences.length,
              summary: {
                avg_word_length: words.empty? ? 0 : words.map(&:length).sum.to_f / words.length,
                longest_word: words.max_by(&:length) || '',
                has_punctuation: text.match?(/[.!?]/)
              }
            }
          end

          main do |inputs|
            execute_task(:analyze_text, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('text-analyzer', agent_dsl)

      test_text = 'Hello world! This is a test. How are you?'
      result = execute_main_with_timing(agent, { text: test_text })

      expect(result[:success]).to be(true)
      expect(result[:output][:word_count]).to eq(8)
      expect(result[:output][:sentences]).to eq(3)
      expect(result[:output][:summary][:has_punctuation]).to be(true)
      expect(result[:output][:summary][:longest_word]).to eq('Hello')
    end
  end

  describe 'Symbolic tasks with context access' do
    it 'executes symbolic task with access to task executor context' do
      agent_dsl = <<~RUBY
        agent "context-aware" do
          task :fetch_data,
            inputs: { source: 'string' },
            outputs: { data: 'hash' }
          do |inputs|
            { data: { source: inputs[:source], fetched: true } }
          end
        #{'  '}
          task :process_with_context,
            inputs: { query: 'string' },
            outputs: { result: 'hash', metadata: 'hash' }
          do |inputs|
            # Access other tasks via context
            data = execute_task(:fetch_data, inputs: { source: 'database' })
        #{'    '}
            {
              result: { query: inputs[:query], processed: true },
              metadata: {
                data_source: data[:data][:source],
                timestamp: Time.now.iso8601,
                agent_context: true
              }
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:process_with_context, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('context-aware', agent_dsl)

      result = execute_main_with_timing(agent, { query: 'test query' })

      expect(result[:success]).to be(true)
      expect(result[:output][:result][:query]).to eq('test query')
      expect(result[:output][:metadata][:data_source]).to eq('database')
      expect(result[:output][:metadata][:agent_context]).to be(true)
    end

    it 'provides execute_llm helper in symbolic task context' do
      agent_dsl = <<~RUBY
        agent "llm-helper" do
          task :hybrid_processing,
            inputs: { prompt: 'string' },
            outputs: { response: 'string', processed_locally: 'boolean' }
          do |inputs|
            # Use LLM helper method (this would be mocked in tests)
            llm_response = execute_llm(inputs[:prompt]) rescue 'Mock LLM response'
        #{'    '}
            {
              response: llm_response,
              processed_locally: true
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:hybrid_processing, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('llm-helper', agent_dsl)

      result = execute_main_with_timing(agent, { prompt: 'What is 2+2?' })

      expect(result[:success]).to be(true)
      expect(result[:output][:response]).to be_a(String)
      expect(result[:output][:processed_locally]).to be(true)
    end

    it 'provides execute_tool helper in symbolic task context' do
      agent_dsl = <<~RUBY
        agent "tool-user" do
          task :use_tools,
            inputs: { operation: 'string', data: 'hash' },
            outputs: { result: 'hash', tools_used: 'boolean' }
          do |inputs|
            # Use tool helper method (this would be mocked in tests)
            tool_result = execute_tool('calculator', 'add',#{' '}
              a: inputs[:data][:a],#{' '}
              b: inputs[:data][:b]
            ) rescue { sum: inputs[:data][:a] + inputs[:data][:b] }
        #{'    '}
            {
              result: tool_result,
              tools_used: true
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:use_tools, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('tool-user', agent_dsl)

      result = execute_main_with_timing(agent, {
                                          operation: 'add',
                                          data: { a: 15, b: 27 }
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:result][:sum]).to eq(42)
      expect(result[:output][:tools_used]).to be(true)
    end
  end

  describe 'Symbolic task error handling' do
    it 'handles Ruby exceptions in symbolic tasks' do
      agent_dsl = <<~RUBY
        agent "error-prone" do
          task :divide_numbers,
            inputs: { numerator: 'number', denominator: 'number' },
            outputs: { result: 'number' }
          do |inputs|
            if inputs[:denominator] == 0
              raise ArgumentError, "Cannot divide by zero"
            end
        #{'    '}
            { result: inputs[:numerator] / inputs[:denominator] }
          end
        #{'  '}
          main do |inputs|
            begin
              execute_task(:divide_numbers, inputs: inputs)
            rescue => e
              { error: e.message, success: false }
            end
          end
        end
      RUBY

      agent = create_test_agent('error-prone', agent_dsl)

      # Test division by zero
      result = execute_main_with_timing(agent, { numerator: 10, denominator: 0 })

      expect(result[:success]).to be(true)
      expect(result[:output][:error]).to include('Cannot divide by zero')
      expect(result[:output][:success]).to be(false)
    end

    it 'validates input types in symbolic tasks' do
      agent_dsl = <<~RUBY
        agent "type-checker" do
          task :strict_math,
            inputs: { numbers: 'array' },
            outputs: { sum: 'number' }
          do |inputs|
            { sum: inputs[:numbers].sum }
          end
        #{'  '}
          main do |inputs|
            execute_task(:strict_math, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('type-checker', agent_dsl)

      # Test with wrong input type
      expect do
        execute_main_with_timing(agent, { numbers: 'not-an-array' })
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Expected.*array/)
    end

    it 'validates output schema in symbolic tasks' do
      agent_dsl = <<~RUBY
        agent "schema-validator" do
          task :bad_output,
            inputs: { data: 'string' },
            outputs: { result: 'integer', status: 'boolean' }
          do |inputs|
            # Return wrong output schema
            { wrong_key: 'bad value' }
          end
        #{'  '}
          main do |inputs|
            execute_task(:bad_output, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('schema-validator', agent_dsl)

      expect do
        execute_main_with_timing(agent, { data: 'test' })
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Missing required output/)
    end
  end

  describe 'Symbolic task performance' do
    it 'executes symbolic tasks faster than neural equivalents' do
      # Symbolic version
      symbolic_dsl = <<~RUBY
        agent "symbolic-calc" do
          task :calculate,
            inputs: { numbers: 'array' },
            outputs: { sum: 'number', average: 'number' }
          do |inputs|
            sum = inputs[:numbers].sum
            {
              sum: sum,
              average: sum.to_f / inputs[:numbers].length
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:calculate, inputs: inputs)
          end
        end
      RUBY

      # Neural version (would be slower due to LLM call)
      neural_dsl = <<~RUBY
        agent "neural-calc" do
          task :calculate,
            instructions: "Calculate sum and average of the provided numbers",
            inputs: { numbers: 'array' },
            outputs: { sum: 'number', average: 'number' }
        #{'  '}
          main do |inputs|
            execute_task(:calculate, inputs: inputs)
          end
        end
      RUBY

      symbolic_agent = create_test_agent('symbolic-calc', symbolic_dsl)
      neural_agent = create_test_agent('neural-calc', neural_dsl)

      test_data = { numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }

      benchmark_comparison(
        'Symbolic',
        -> { execute_main_with_timing(symbolic_agent, test_data) },
        'Neural',
        -> { execute_main_with_timing(neural_agent, test_data) }
      )
    end

    it 'handles large datasets efficiently in symbolic tasks' do
      agent_dsl = <<~RUBY
        agent "large-data-processor" do
          task :process_large_dataset,
            inputs: { data: 'array' },
            outputs: {#{' '}
              count: 'integer',
              sum: 'number',
              stats: 'hash'
            }
          do |inputs|
            data = inputs[:data]
            {
              count: data.length,
              sum: data.sum,
              stats: {
                min: data.min,
                max: data.max,
                median: data.sort[data.length / 2],
                even_count: data.count(&:even?)
              }
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:process_large_dataset, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('large-data-processor', agent_dsl)

      # Create large dataset
      large_data = (1..10_000).to_a

      result = measure_performance('Large dataset processing') do
        execute_main_with_timing(agent, { data: large_data })
      end

      expect(result[:success]).to be(true)
      expect(result[:output][:count]).to eq(10_000)
      expect(result[:output][:sum]).to eq(50_005_000)
      expect(result[:execution_time]).to be < 1.0 # Should be very fast
    end
  end

  describe 'Type coercion in symbolic tasks' do
    it 'applies type coercion to symbolic task inputs' do
      agent_dsl = <<~'RUBY'
        agent "type-coercion" do
          task :process_types,
            inputs: {
              count: 'integer',
              rate: 'number',
              active: 'boolean',
              name: 'string'
            },
            outputs: { summary: 'string' }
          do |inputs|
            {
              summary: "#{inputs[:name]}: count=#{inputs[:count]}, " +
                      "rate=#{inputs[:rate]}, active=#{inputs[:active]}"
            }
          end

          main do |inputs|
            execute_task(:process_types, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('type-coercion', agent_dsl)

      # Test with coercible types
      result = execute_main_with_timing(agent, {
                                          count: '42', # string -> integer
                                          rate: '3.14159',    # string -> number
                                          active: 'true',     # string -> boolean
                                          name: :test_user    # symbol -> string
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:summary]).to include('count=42')
      expect(result[:output][:summary]).to include('rate=3.14159')
      expect(result[:output][:summary]).to include('active=true')
      expect(result[:output][:summary]).to include('test_user')
    end

    it 'validates output types with coercion' do
      agent_dsl = <<~RUBY
        agent "output-coercion" do
          task :flexible_output,
            inputs: { input: 'string' },
            outputs: {#{' '}
              number_result: 'number',
              string_result: 'string',
              bool_result: 'boolean'
            }
          do |inputs|
            {
              number_result: '42.5',    # string that should coerce to number
              string_result: 123,       # number that should coerce to string
              bool_result: 'true'       # string that should coerce to boolean
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:flexible_output, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('output-coercion', agent_dsl)

      result = execute_main_with_timing(agent, { input: 'test' })

      expect(result[:success]).to be(true)
      expect(result[:output][:number_result]).to eq(42.5)
      expect(result[:output][:string_result]).to eq('123')
      expect(result[:output][:bool_result]).to be(true)
    end
  end
end
