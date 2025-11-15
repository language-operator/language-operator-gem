# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Error Handling in Task Execution', type: :integration, skip: 'Syntax fixes needed for task definitions' do
  describe 'Task execution errors' do
    it 'handles Ruby exceptions in symbolic tasks' do
      agent_dsl = <<~'RUBY'
        agent "error-producer" do
          task :division_task,
            inputs: { numerator: 'number', denominator: 'number' },
            outputs: { result: 'number' } do |inputs|
            if inputs[:denominator] == 0
              raise ZeroDivisionError, "Cannot divide by zero"
            end
            { result: inputs[:numerator] / inputs[:denominator] }
          end
          
          task :array_access_task,
            inputs: { array: 'array', index: 'integer' },
            outputs: { element: 'any' } do |inputs|
            if inputs[:index] < 0 || inputs[:index] >= inputs[:array].length
              raise IndexError, "Index #{inputs[:index]} out of bounds for array of length #{inputs[:array].length}"
            end
            { element: inputs[:array][inputs[:index]] }
          end
          
          main do |inputs|
            case inputs[:operation]
            when 'divide'
              begin
                execute_task(:division_task, inputs: inputs)
              rescue ZeroDivisionError => e
                { error: 'division_error', message: e.message, success: false }
              end
            when 'access'
              begin
                execute_task(:array_access_task, inputs: inputs)
              rescue IndexError => e
                { error: 'index_error', message: e.message, success: false }
              end
            else
              { error: 'unknown_operation', message: 'Unknown operation', success: false }
            end
          end
        end
      RUBY

      agent = create_test_agent('error-producer', agent_dsl)

      # Test division by zero
      result1 = execute_main_with_timing(agent, {
                                           operation: 'divide',
                                           numerator: 10,
                                           denominator: 0
                                         })
      expect(result1[:success]).to be(true)
      expect(result1[:output][:error]).to eq('division_error')
      expect(result1[:output][:message]).to include('Cannot divide by zero')

      # Test index out of bounds
      result2 = execute_main_with_timing(agent, {
                                           operation: 'access',
                                           array: [1, 2, 3],
                                           index: 5
                                         })
      expect(result2[:success]).to be(true)
      expect(result2[:output][:error]).to eq('index_error')
      expect(result2[:output][:message]).to include('Index 5 out of bounds')
    end

    it 'handles timeout errors in long-running tasks' do
      agent_dsl = <<~RUBY
        agent "timeout-test" do
          task :slow_task,
            inputs: { duration: 'number' },
            outputs: { result: 'string' } do |inputs|
            sleep(inputs[:duration])
            { result: 'Task completed' }
          end
        #{'  '}
          main do |inputs|
            begin
              Timeout::timeout(0.1) do  # 100ms timeout
                execute_task(:slow_task, inputs: inputs)
              end
            rescue Timeout::Error => e
              {#{' '}
                error: 'timeout',
                message: 'Task execution timed out',
                duration_attempted: inputs[:duration],
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('timeout-test', agent_dsl)

      # Test task that should timeout
      result = execute_main_with_timing(agent, { duration: 0.2 }) # 200ms, will timeout

      expect(result[:success]).to be(true)
      expect(result[:output][:error]).to eq('timeout')
      expect(result[:output][:duration_attempted]).to eq(0.2)
      expect(result[:output][:success]).to be(false)
    end

    it 'handles resource exhaustion errors' do
      agent_dsl = <<~'RUBY'
        agent "resource-exhaustion" do
          task :memory_intensive_task,
            inputs: { size: 'integer' },
            outputs: { result: 'string' } do |inputs|
            begin
              # Try to allocate a very large array
              if inputs[:size] > 1_000_000
                raise NoMemoryError, "Insufficient memory for array of size #{inputs[:size]}"
              end
              
              large_array = Array.new(inputs[:size], 'data')
              { result: "Created array of size #{large_array.length}" }
            rescue NoMemoryError => e
              raise e  # Re-raise to be caught by main
            end
          end
          
          main do |inputs|
            begin
              execute_task(:memory_intensive_task, inputs: inputs)
            rescue NoMemoryError => e
              {
                error: 'memory_exhaustion',
                message: e.message,
                requested_size: inputs[:size],
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('resource-exhaustion', agent_dsl)

      # Test with reasonable size (should succeed)
      result1 = execute_main_with_timing(agent, { size: 1000 })
      expect(result1[:success]).to be(true)
      expect(result1[:output][:result]).to include('Created array of size 1000')

      # Test with excessive size (should fail)
      result2 = execute_main_with_timing(agent, { size: 10_000_000 })
      expect(result2[:success]).to be(true)
      expect(result2[:output][:error]).to eq('memory_exhaustion')
      expect(result2[:output][:requested_size]).to eq(10_000_000)
    end
  end

  describe 'Input validation errors' do
    it 'handles missing required inputs' do
      agent_dsl = <<~RUBY
        agent "validation-test" do
          task :strict_task,
            inputs: {#{' '}
              required_string: 'string',
              required_number: 'number',
              required_array: 'array'
            },
            outputs: { processed: 'hash' } do |inputs|
            {
              processed: {
                string_length: inputs[:required_string].length,
                number_doubled: inputs[:required_number] * 2,
                array_size: inputs[:required_array].size
              }
            }
          end
        #{'  '}
          main do |inputs|
            begin
              execute_task(:strict_task, inputs: inputs)
            rescue LanguageOperator::Agent::TaskValidationError => e
              {
                error: 'validation_error',
                message: e.message,
                provided_inputs: inputs.keys.sort,
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('validation-test', agent_dsl)

      # Test with missing inputs
      result = execute_main_with_timing(agent, {
                                          required_string: 'hello',
                                          required_number: 42
                                          # missing required_array
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:error]).to eq('validation_error')
      expect(result[:output][:message]).to include('Missing required input: required_array')
      expect(result[:output][:provided_inputs]).to contain_exactly(:required_number, :required_string)
    end

    it 'handles invalid input types' do
      agent_dsl = <<~'RUBY'
        agent "type-validation" do
          task :type_strict_task,
            inputs: { 
              must_be_array: 'array',
              must_be_hash: 'hash',
              must_be_integer: 'integer'
            },
            outputs: { summary: 'string' } do |inputs|
            {
              summary: "Processed #{inputs[:must_be_array].size} items, " +
                      "#{inputs[:must_be_hash].keys.size} keys, " +
                      "number: #{inputs[:must_be_integer]}"
            }
          end
          
          main do |inputs|
            begin
              execute_task(:type_strict_task, inputs: inputs)
            rescue LanguageOperator::Agent::TaskValidationError => e
              {
                error: 'type_validation_error',
                message: e.message,
                success: false
              }
            rescue ArgumentError => e
              {
                error: 'coercion_error',
                message: e.message,
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('type-validation', agent_dsl)

      # Test with wrong types
      result = execute_main_with_timing(agent, {
                                          must_be_array: 'not-an-array',
                                          must_be_hash: [1, 2, 3],
                                          must_be_integer: 'not-a-number'
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:success]).to be(false)
      expect(result[:output][:error]).to match(/(validation_error|coercion_error)/)
    end
  end

  describe 'Output validation errors' do
    it 'handles tasks returning invalid output schema' do
      agent_dsl = <<~RUBY
        agent "output-validation" do
          task :bad_output_task,
            inputs: { mode: 'string' },
            outputs: {#{' '}
              required_field: 'string',
              another_field: 'number'
            }
          do |inputs|
            case inputs[:mode]
            when 'missing_field'
              { wrong_field: 'oops' }  # Missing required fields
            when 'wrong_type'
              {#{' '}
                required_field: 123,     # Should be string
                another_field: 'text'    # Should be number
              }
            when 'extra_field'
              {
                required_field: 'correct',
                another_field: 42,
                extra_field: 'not_expected'  # Extra field
              }
            else
              {
                required_field: 'correct',
                another_field: 42
              }
            end
          end
        #{'  '}
          main do |inputs|
            begin
              execute_task(:bad_output_task, inputs: inputs)
            rescue LanguageOperator::Agent::TaskValidationError => e
              {
                error: 'output_validation_error',
                message: e.message,
                mode: inputs[:mode],
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('output-validation', agent_dsl)

      # Test missing required field
      result1 = execute_main_with_timing(agent, { mode: 'missing_field' })
      expect(result1[:success]).to be(true)
      expect(result1[:output][:error]).to eq('output_validation_error')
      expect(result1[:output][:message]).to include('Missing required output')

      # Test correct output (should succeed)
      result2 = execute_main_with_timing(agent, { mode: 'valid' })
      expect(result2[:success]).to be(true)
      expect(result2[:output][:required_field]).to eq('correct')
      expect(result2[:output][:another_field]).to eq(42)
    end

    it 'handles output type coercion failures' do
      agent_dsl = <<~RUBY
        agent "coercion-failure" do
          task :uncoercible_output,
            inputs: { mode: 'string' },
            outputs: {#{' '}
              number_field: 'number',
              boolean_field: 'boolean'
            }
          do |inputs|
            case inputs[:mode]
            when 'bad_number'
              {
                number_field: 'definitely-not-a-number',
                boolean_field: true
              }
            when 'bad_boolean'
              {
                number_field: 3.14,
                boolean_field: 'maybe'  # Invalid boolean
              }
            else
              {
                number_field: 42,
                boolean_field: false
              }
            end
          end
        #{'  '}
          main do |inputs|
            begin
              execute_task(:uncoercible_output, inputs: inputs)
            rescue ArgumentError => e
              {
                error: 'coercion_failure',
                message: e.message,
                mode: inputs[:mode],
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('coercion-failure', agent_dsl)

      # Test uncoercible number
      result1 = execute_main_with_timing(agent, { mode: 'bad_number' })
      expect(result1[:success]).to be(true)
      expect(result1[:output][:error]).to eq('coercion_failure')
      expect(result1[:output][:message]).to include('Cannot coerce')

      # Test uncoercible boolean
      result2 = execute_main_with_timing(agent, { mode: 'bad_boolean' })
      expect(result2[:success]).to be(true)
      expect(result2[:output][:error]).to eq('coercion_failure')
      expect(result2[:output][:message]).to include('Cannot coerce')
    end
  end

  describe 'Neural task LLM errors' do
    it 'handles LLM API failures gracefully' do
      # Override LLM mock to simulate API failure
      allow_any_instance_of(LanguageOperator::Agent::Base).to receive(:send_message) do
        raise Net::ReadTimeout, 'LLM API timeout'
      end

      agent_dsl = <<~RUBY
        agent "llm-error-test" do
          task :neural_task,
            instructions: "Process the input with LLM",
            inputs: { text: 'string' },
            outputs: { processed: 'string' }
        #{'  '}
          main do |inputs|
            begin
              execute_task(:neural_task, inputs: inputs)
            rescue => e
              {
                error: 'llm_failure',
                error_type: e.class.name,
                message: e.message,
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('llm-error-test', agent_dsl)

      result = execute_main_with_timing(agent, { text: 'test input' })

      expect(result[:success]).to be(true)
      expect(result[:output][:error]).to eq('llm_failure')
      expect(result[:output][:error_type]).to include('Error')
      expect(result[:output][:message]).to include('timeout')
    end

    it 'handles malformed LLM responses' do
      # Override LLM mock to return malformed JSON
      allow_any_instance_of(LanguageOperator::Agent::Base).to receive(:send_message) do
        'This is not valid JSON response'
      end

      agent_dsl = <<~RUBY
        agent "malformed-response-test" do
          task :neural_task,
            instructions: "Generate a structured response",
            inputs: { input: 'string' },
            outputs: { result: 'hash', status: 'string' }
        #{'  '}
          main do |inputs|
            begin
              execute_task(:neural_task, inputs: inputs)
            rescue => e
              {
                error: 'malformed_response',
                error_type: e.class.name,
                message: e.message,
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('malformed-response-test', agent_dsl)

      result = execute_main_with_timing(agent, { input: 'test' })

      expect(result[:success]).to be(true)
      expect(result[:output][:error]).to eq('malformed_response')
      expect(result[:output][:message]).to include('JSON')
    end
  end

  describe 'Cascading error handling' do
    it 'handles errors that propagate through task chains' do
      agent_dsl = <<~'RUBY'
        agent "error-cascade" do
          task :step_one,
            inputs: { input: 'string' },
            outputs: { result: 'string' } do |inputs|
            if inputs[:input] == 'fail'
              raise StandardError, "Step one failed"
            end
            { result: "#{inputs[:input]}_step1" }
          end
          
          task :step_two,
            inputs: { input: 'string' },
            outputs: { result: 'string' } do |inputs|
            { result: "#{inputs[:input]}_step2" }
          end
          
          task :step_three,
            inputs: { input: 'string' },
            outputs: { result: 'string' } do |inputs|
            { result: "#{inputs[:input]}_step3" }
          end
          
          main do |inputs|
            begin
              result1 = execute_task(:step_one, inputs: inputs)
              result2 = execute_task(:step_two, inputs: { input: result1[:result] })
              result3 = execute_task(:step_three, inputs: { input: result2[:result] })
              result3
            rescue => e
              {
                error: 'cascade_failure',
                failed_step: 'step_one',
                message: e.message,
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('error-cascade', agent_dsl)

      # Test successful cascade
      result1 = execute_main_with_timing(agent, { input: 'success' })
      expect(result1[:success]).to be(true)
      expect(result1[:output][:result]).to eq('success_step1_step2_step3')

      # Test failed cascade
      result2 = execute_main_with_timing(agent, { input: 'fail' })
      expect(result2[:success]).to be(true)
      expect(result2[:output][:error]).to eq('cascade_failure')
      expect(result2[:output][:failed_step]).to eq('step_one')
      expect(result2[:output][:message]).to include('Step one failed')
    end

    it 'implements retry logic for transient failures' do
      agent_dsl = <<~'RUBY'
        agent "retry-logic" do
          task :flaky_task,
            inputs: { attempt: 'integer', max_attempts: 'integer' },
            outputs: { result: 'string', attempts: 'integer' } do |inputs|
            if inputs[:attempt] < inputs[:max_attempts]
              raise StandardError, "Transient failure on attempt #{inputs[:attempt]}"
            end
            {
              result: "Success on attempt #{inputs[:attempt]}",
              attempts: inputs[:attempt]
            }
          end
          
          main do |inputs|
            max_attempts = inputs[:max_attempts] || 3
            last_error = nil
            
            (1..max_attempts).each do |attempt|
              begin
                return execute_task(:flaky_task, inputs: { 
                  attempt: attempt,
                  max_attempts: max_attempts 
                })
              rescue => e
                last_error = e
                sleep(0.01) if attempt < max_attempts  # Brief delay between retries
              end
            end
            
            # All attempts failed
            {
              error: 'max_retries_exceeded',
              attempts: max_attempts,
              last_error: last_error.message,
              success: false
            }
          end
        end
      RUBY

      agent = create_test_agent('retry-logic', agent_dsl)

      # Test successful retry (should succeed on attempt 3)
      result1 = execute_main_with_timing(agent, { max_attempts: 3 })
      expect(result1[:success]).to be(true)
      expect(result1[:output][:result]).to include('Success on attempt 3')
      expect(result1[:output][:attempts]).to eq(3)

      # Test all retries exhausted
      result2 = execute_main_with_timing(agent, { max_attempts: 2 })
      expect(result2[:success]).to be(true)
      expect(result2[:output][:error]).to eq('max_retries_exceeded')
      expect(result2[:output][:attempts]).to eq(2)
      expect(result2[:output][:last_error]).to include('Transient failure')
    end
  end

  describe 'Error context and debugging' do
    it 'provides rich error context for debugging' do
      agent_dsl = <<~'RUBY'
        agent "error-context" do
          task :context_task,
            inputs: { data: 'hash' },
            outputs: { processed: 'hash' } do |inputs|
            # Simulate complex processing that might fail
            data = inputs[:data]
            
            begin
              processed = {
                user_id: data.fetch(:user_id),
                name: data.fetch(:name).upcase,
                age: Integer(data.fetch(:age)),
                preferences: data.fetch(:preferences, {})
              }
              
              if processed[:age] < 0
                raise ArgumentError, "Age cannot be negative: #{processed[:age]}"
              end
              
              { processed: processed }
            rescue KeyError => e
              raise LanguageOperator::Agent::TaskExecutionError.new(
                :context_task,
                "Missing required field: #{e.message}. Available fields: #{data.keys.join(', ')}"
              )
            rescue ArgumentError => e
              raise LanguageOperator::Agent::TaskExecutionError.new(
                :context_task,
                "Data validation error: #{e.message}. Input data: #{data.inspect}"
              )
            end
          end
          
          main do |inputs|
            begin
              execute_task(:context_task, inputs: inputs)
            rescue LanguageOperator::Agent::TaskExecutionError => e
              {
                error: 'task_execution_error',
                task_name: e.task_name,
                message: e.message,
                context: {
                  provided_data: inputs[:data],
                  timestamp: Time.now.iso8601
                },
                success: false
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('error-context', agent_dsl)

      # Test missing field error
      result1 = execute_main_with_timing(agent, {
                                           data: { user_id: 123, age: 25 } # Missing 'name' field
                                         })

      expect(result1[:success]).to be(true)
      expect(result1[:output][:error]).to eq('task_execution_error')
      expect(result1[:output][:task_name]).to eq(:context_task)
      expect(result1[:output][:message]).to include('Missing required field')
      expect(result1[:output][:message]).to include('Available fields: user_id, age')
      expect(result1[:output][:context][:provided_data]).to include(:user_id, :age)

      # Test validation error
      result2 = execute_main_with_timing(agent, {
                                           data: { user_id: 123, name: 'John', age: -5 } # Invalid age
                                         })

      expect(result2[:success]).to be(true)
      expect(result2[:output][:error]).to eq('task_execution_error')
      expect(result2[:output][:message]).to include('Age cannot be negative: -5')
      expect(result2[:output][:message]).to include('Input data:')
    end
  end

  describe 'Performance under error conditions' do
    it 'maintains reasonable performance even with frequent errors' do
      agent_dsl = <<~'RUBY'
        agent "error-performance" do
          task :error_prone_task,
            inputs: { success_rate: 'number', iteration: 'integer' },
            outputs: { result: 'string' } do |inputs|
            if rand() < inputs[:success_rate]
              { result: "Success on iteration #{inputs[:iteration]}" }
            else
              raise StandardError, "Random failure on iteration #{inputs[:iteration]}"
            end
          end
          
          main do |inputs|
            success_rate = inputs[:success_rate] || 0.5
            iterations = inputs[:iterations] || 10
            
            results = []
            errors = []
            
            iterations.times do |i|
              begin
                result = execute_task(:error_prone_task, inputs: {
                  success_rate: success_rate,
                  iteration: i + 1
                })
                results << result[:result]
              rescue => e
                errors << e.message
              end
            end
            
            {
              successful_iterations: results.length,
              failed_iterations: errors.length,
              success_rate_actual: results.length.to_f / iterations,
              error_sample: errors.first(3)
            }
          end
        end
      RUBY

      agent = create_test_agent('error-performance', agent_dsl)

      result = measure_performance('Performance with 50% error rate') do
        execute_main_with_timing(agent, {
                                   success_rate: 0.5, # 50% success rate
                                   iterations: 20
                                 })
      end

      expect(result[:success]).to be(true)
      expect(result[:output][:successful_iterations] + result[:output][:failed_iterations]).to eq(20)
      expect(result[:output][:success_rate_actual]).to be_between(0.2, 0.8) # Allow variance

      # Performance should still be reasonable despite errors
      expect(result[:execution_time]).to be < 0.5 # Less than 500ms for 20 iterations
    end
  end
end
