# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Neural Task Execution', type: :integration do
  describe 'Simple neural tasks' do
    it 'executes neural task with instructions and validates output' do
      agent_dsl = <<~RUBY
        agent "weather-bot" do
          description "A bot that provides weather information"
        #{'  '}
          task :get_weather,
            instructions: "Get current weather for the given location",
            inputs: { location: 'string' },
            outputs: { temperature: 'number', condition: 'string', humidity: 'number' }
        #{'  '}
          main do |inputs|
            weather = execute_task(:get_weather, inputs: { location: inputs[:location] })
            weather
          end
        end
      RUBY

      agent = create_test_agent('weather-bot', agent_dsl)

      result = execute_main_with_timing(agent, { location: 'San Francisco' })

      expect(result[:success]).to be(true)
      expect(result[:output]).to be_a(Hash)
      expect(result[:output]).to include(:temperature, :condition, :humidity)
      expect(result[:output][:temperature]).to be_a(Numeric)
      expect(result[:output][:condition]).to be_a(String)
      expect(result[:output][:humidity]).to be_a(Numeric)
      expect(result[:execution_time]).to be > 0
    end

    it 'handles neural task with complex output schema' do
      agent_dsl = <<~RUBY
        agent "user-analyzer" do
          task :fetch_user_data,
            instructions: "Fetch comprehensive user data including profile and preferences",
            inputs: { user_id: 'integer' },
            outputs: {#{' '}
              user: 'hash',
              preferences: 'hash'
            }
        #{'  '}
          main do |inputs|
            execute_task(:fetch_user_data, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('user-analyzer', agent_dsl)

      result = execute_main_with_timing(agent, { user_id: 123 })

      expect(result[:success]).to be(true)
      expect(result[:output]).to include(:user, :preferences)
      expect(result[:output][:user]).to be_a(Hash)
      expect(result[:output][:preferences]).to be_a(Hash)
      expect(result[:output][:user]).to include(:id, :name, :email)
    end

    it 'validates neural task output against schema' do
      agent_dsl = <<~RUBY
        agent "calculator" do
          task :calculate_total,
            instructions: "Calculate the total sum of provided numbers",
            inputs: { numbers: 'array' },
            outputs: { total: 'number' }
        #{'  '}
          main do |inputs|
            execute_task(:calculate_total, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('calculator', agent_dsl)

      # Test with valid inputs
      result = execute_main_with_timing(agent, { numbers: [1, 2, 3, 4, 5] })

      expect(result[:success]).to be(true)
      expect(result[:output][:total]).to be_a(Numeric)

      # Verify output schema
      expected_schema = { total: 'number' }
      expect(verify_task_output(result[:output], expected_schema)).to be(true)
    end
  end

  describe 'Neural tasks with tool usage' do
    it 'executes neural task that calls tools via LLM' do
      agent_dsl = <<~RUBY
        agent "data-processor" do
          task :analyze_data,
            instructions: "Analyze the provided data and generate insights using available tools",
            inputs: { data: 'array' },
            outputs: { insights: 'string', metrics: 'hash' }
        #{'  '}
          main do |inputs|
            execute_task(:analyze_data, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('data-processor', agent_dsl)

      test_data = [
        { value: 10, category: 'A' },
        { value: 20, category: 'B' },
        { value: 15, category: 'A' }
      ]

      result = execute_main_with_timing(agent, { data: test_data })

      expect(result[:success]).to be(true)
      expect(result[:output]).to include(:insights, :metrics)
      expect(result[:output][:insights]).to be_a(String)
      expect(result[:output][:metrics]).to be_a(Hash)
    end
  end

  describe 'Neural task error handling' do
    it 'handles invalid inputs gracefully' do
      agent_dsl = <<~RUBY
        agent "validator" do
          task :validate_email,
            instructions: "Validate that the input is a properly formatted email",
            inputs: { email: 'string' },
            outputs: { valid: 'boolean', reason: 'string' }
        #{'  '}
          main do |inputs|
            execute_task(:validate_email, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('validator', agent_dsl)

      # Test with invalid email
      result = execute_main_with_timing(agent, { email: 'invalid-email' })

      # Should handle gracefully and provide validation result
      expect(result[:success]).to be(true)
      expect(result[:output]).to include(:valid, :reason)
      expect([true, false]).to include(result[:output][:valid])
      expect(result[:output][:reason]).to be_a(String)
    end

    it 'handles missing required inputs' do
      agent_dsl = <<~RUBY
        agent "strict-processor" do
          task :process_data,
            instructions: "Process the required data field",
            inputs: { data: 'array', config: 'hash' },
            outputs: { result: 'string' }
        #{'  '}
          main do |inputs|
            execute_task(:process_data, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('strict-processor', agent_dsl)

      # Test with missing config input - use execute_main_block to allow error to bubble up
      expect do
        execute_main_block(agent, { data: [1, 2, 3] })
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Missing required input parameter: config/)
    end
  end

  describe 'Neural task performance' do
    it 'executes neural tasks within reasonable time limits' do
      agent_dsl = <<~RUBY
        agent "quick-responder" do
          task :quick_response,
            instructions: "Provide a quick response to the input",
            inputs: { query: 'string' },
            outputs: { response: 'string' }
        #{'  '}
          main do |inputs|
            execute_task(:quick_response, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('quick-responder', agent_dsl)

      result = execute_main_with_timing(agent, { query: 'Hello, how are you?' })

      expect(result[:success]).to be(true)
      expect(result[:execution_time]).to be < Integration::Config.test_timeout
      expect(result[:output][:response]).to be_a(String)
      expect(result[:output][:response]).not_to be_empty
    end

    it 'measures performance of multiple neural task calls' do
      agent_dsl = <<~RUBY
        agent "multi-task" do
          task :task_one,
            instructions: "Process step one",
            inputs: { data: 'string' },
            outputs: { result: 'string' }
        #{'  '}
          task :task_two,
            instructions: "Process step two",#{' '}
            inputs: { result: 'string' },
            outputs: { result: 'string' }
        #{'  '}
          main do |inputs|
            result1 = execute_task(:task_one, inputs: inputs)
            result2 = execute_task(:task_two, inputs: result1)
            result2
          end
        end
      RUBY

      agent = create_test_agent('multi-task', agent_dsl)

      result = measure_performance('Sequential neural tasks') do
        execute_main_with_timing(agent, { data: 'test input' })
      end

      expect(result[:success]).to be(true)
      expect(result[:output][:result]).to be_a(String)
    end
  end

  describe 'Type coercion in neural tasks' do
    it 'handles type coercion for neural task inputs' do
      agent_dsl = <<~RUBY
        agent "type-processor" do
          task :process_numbers,
            instructions: "Process numeric inputs and return statistics",
            inputs: {#{' '}
              count: 'integer',
              rate: 'number',#{' '}
              active: 'boolean',
              name: 'string'
            },
            outputs: { summary: 'string' }
        #{'  '}
          main do |inputs|
            execute_task(:process_numbers, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('type-processor', agent_dsl)

      # Test with coercible inputs
      result = execute_main_with_timing(agent, {
                                          count: '42', # string -> integer
                                          rate: '3.14',       # string -> number
                                          active: 'true',     # string -> boolean
                                          name: :test         # symbol -> string
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:summary]).to be_a(String)
    end

    it 'rejects non-coercible inputs' do
      agent_dsl = <<~RUBY
        agent "strict-types" do
          task :strict_task,
            instructions: "Convert the number to a string",
            inputs: { number: 'integer' },
            outputs: { result: 'string' }
        #{'  '}
          main do |inputs|
            execute_task(:strict_task, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('strict-types', agent_dsl)

      # Test with non-coercible input - use execute_main_block to allow error to bubble up
      expect do
        execute_main_block(agent, { number: 'not-a-number' })
      end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Cannot coerce/)
    end
  end
end
