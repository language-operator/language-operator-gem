# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Type Coercion in Task Execution', type: :integration do
  describe 'Input type coercion' do
    it 'coerces string inputs to integers' do
      agent_dsl = <<~RUBY
        agent "integer-coercion" do
          task :process_integers,
            inputs: {#{' '}
              count: 'integer',
              negative: 'integer',
              zero: 'integer'
            },
            outputs: { sum: 'integer', product: 'integer' }
          do |inputs|
            {
              sum: inputs[:count] + inputs[:negative] + inputs[:zero],
              product: inputs[:count] * inputs[:negative] * inputs[:zero]
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:process_integers, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('integer-coercion', agent_dsl)

      # Test various string-to-integer coercions
      result = execute_main_with_timing(agent, {
                                          count: '42', # Positive integer string
                                          negative: '-5',   # Negative integer string
                                          zero: '0'         # Zero string
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:sum]).to eq(37)
      expect(result[:output][:product]).to eq(0)
    end

    it 'coerces various types to numbers (float)' do
      agent_dsl = <<~RUBY
        agent "number-coercion" do
          task :process_numbers,
            inputs: {#{' '}
              decimal: 'number',
              integer_str: 'number',
              scientific: 'number',
              negative_decimal: 'number'
            },
            outputs: { sum: 'number', average: 'number' }
          do |inputs|
            values = [
              inputs[:decimal],
              inputs[:integer_str],#{' '}
              inputs[:scientific],
              inputs[:negative_decimal]
            ]
        #{'    '}
            {
              sum: values.sum,
              average: values.sum / values.length.to_f
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:process_numbers, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('number-coercion', agent_dsl)

      result = execute_main_with_timing(agent, {
                                          decimal: '3.14159', # Decimal string
                                          integer_str: '42',         # Integer string coerced to float
                                          scientific: '1.5e2',       # Scientific notation
                                          negative_decimal: '-2.5'   # Negative decimal
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:sum]).to be_within(0.001).of(192.64159)
      expect(result[:output][:average]).to be_within(0.001).of(48.160)
    end

    it 'coerces various types to booleans' do
      agent_dsl = <<~'RUBY'
        agent "boolean-coercion" do
          task :process_booleans,
            inputs: { 
              true_string: 'boolean',
              false_string: 'boolean',
              yes_string: 'boolean',
              no_string: 'boolean',
              one_string: 'boolean',
              zero_string: 'boolean'
            },
            outputs: { 
              true_count: 'integer',
              false_count: 'integer',
              summary: 'string'
            }
          do |inputs|
            values = [
              inputs[:true_string],
              inputs[:false_string],
              inputs[:yes_string],
              inputs[:no_string],
              inputs[:one_string],
              inputs[:zero_string]
            ]
            
            true_count = values.count(true)
            false_count = values.count(false)
            
            {
              true_count: true_count,
              false_count: false_count,
              summary: "#{true_count} true, #{false_count} false"
            }
          end
          
          main do |inputs|
            execute_task(:process_booleans, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('boolean-coercion', agent_dsl)

      result = execute_main_with_timing(agent, {
                                          true_string: 'true', # Standard true string
                                          false_string: 'false',     # Standard false string
                                          yes_string: 'yes',         # Yes variant
                                          no_string: 'no',           # No variant
                                          one_string: '1',           # Numeric true
                                          zero_string: '0'           # Numeric false
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:true_count]).to eq(3)
      expect(result[:output][:false_count]).to eq(3)
      expect(result[:output][:summary]).to eq('3 true, 3 false')
    end

    it 'coerces various types to strings' do
      agent_dsl = <<~RUBY
        agent "string-coercion" do
          task :process_strings,
            inputs: {#{' '}
              symbol_input: 'string',
              integer_input: 'string',
              float_input: 'string',
              boolean_input: 'string'
            },
            outputs: { concatenated: 'string', lengths: 'array' }
          do |inputs|
            strings = [
              inputs[:symbol_input],
              inputs[:integer_input],
              inputs[:float_input],
              inputs[:boolean_input]
            ]
        #{'    '}
            {
              concatenated: strings.join(' | '),
              lengths: strings.map(&:length)
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:process_strings, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('string-coercion', agent_dsl)

      result = execute_main_with_timing(agent, {
                                          symbol_input: :test_symbol, # Symbol to string
                                          integer_input: 42,            # Integer to string
                                          float_input: 3.14159,         # Float to string
                                          boolean_input: true           # Boolean to string
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:concatenated]).to eq('test_symbol | 42 | 3.14159 | true')
      expect(result[:output][:lengths]).to eq([11, 2, 7, 4])
    end

    it 'handles complex nested type coercion' do
      agent_dsl = <<~RUBY
        agent "nested-coercion" do
          task :process_nested,
            inputs: {#{' '}
              config: 'hash'
            },
            outputs: { processed_config: 'hash' }
          do |inputs|
            # Process nested hash with type-aware handling
            config = inputs[:config]
        #{'    '}
            processed = {
              name: config['name'].to_s,                    # Ensure string
              age: config['age'].to_i,                      # Ensure integer
              active: config['active'].to_s.downcase == 'true',  # Ensure boolean
              settings: {
                notifications: config.dig('settings', 'notifications').to_s.downcase == 'true',
                theme: config.dig('settings', 'theme').to_s,
                max_items: config.dig('settings', 'max_items').to_i
              }
            }
        #{'    '}
            { processed_config: processed }
          end
        #{'  '}
          main do |inputs|
            execute_task(:process_nested, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('nested-coercion', agent_dsl)

      # Test with mixed-type nested hash
      result = execute_main_with_timing(agent, {
                                          config: {
                                            'name' => :user_name,           # Symbol
                                            'age' => '25',                  # String integer
                                            'active' => 'true',             # String boolean
                                            'settings' => {
                                              'notifications' => 'false',   # String boolean
                                              'theme' => 'dark',            # Already string
                                              'max_items' => '100'          # String integer
                                            }
                                          }
                                        })

      expect(result[:success]).to be(true)
      config = result[:output][:processed_config]
      expect(config[:name]).to eq('user_name')
      expect(config[:age]).to eq(25)
      expect(config[:active]).to be(true)
      expect(config[:settings][:notifications]).to be(false)
      expect(config[:settings][:theme]).to eq('dark')
      expect(config[:settings][:max_items]).to eq(100)
    end
  end

  describe 'Output type coercion' do
    it 'coerces task output types to match schema' do
      agent_dsl = <<~RUBY
        agent "output-coercion" do
          task :flexible_output,
            inputs: { mode: 'string' },
            outputs: {#{' '}
              count: 'integer',
              rate: 'number',
              active: 'boolean',
              message: 'string'
            }
          do |inputs|
            # Return outputs that need coercion
            case inputs[:mode]
            when 'strings'
              {
                count: '42',          # String -> Integer#{'  '}
                rate: '3.14',         # String -> Number
                active: 'true',       # String -> Boolean
                message: :success     # Symbol -> String
              }
            when 'numbers'
              {
                count: 42.7,          # Float -> Integer (truncated)
                rate: 100,            # Integer -> Number
                active: 1,            # Integer -> Boolean
                message: 12345        # Number -> String
              }
            else
              {
                count: 0,
                rate: 0.0,
                active: false,
                message: 'default'
              }
            end
          end
        #{'  '}
          main do |inputs|
            execute_task(:flexible_output, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('output-coercion', agent_dsl)

      # Test string coercion
      result1 = execute_main_with_timing(agent, { mode: 'strings' })
      expect(result1[:success]).to be(true)
      expect(result1[:output][:count]).to eq(42)
      expect(result1[:output][:rate]).to eq(3.14)
      expect(result1[:output][:active]).to be(true)
      expect(result1[:output][:message]).to eq('success')

      # Test number coercion
      result2 = execute_main_with_timing(agent, { mode: 'numbers' })
      expect(result2[:success]).to be(true)
      expect(result2[:output][:count]).to eq(42) # Float truncated to integer
      expect(result2[:output][:rate]).to eq(100.0)
      expect(result2[:output][:active]).to be(true) # 1 -> true
      expect(result2[:output][:message]).to eq('12345')
    end

    it 'validates array and hash types without coercion' do
      agent_dsl = <<~RUBY
        agent "strict-collections" do
          task :collection_task,
            inputs: { mode: 'string' },
            outputs: {#{' '}
              items: 'array',
              metadata: 'hash'
            }
          do |inputs|
            if inputs[:mode] == 'invalid'
              {
                items: 'not-an-array',     # Should cause validation error
                metadata: { valid: true }
              }
            else
              {
                items: [1, 2, 3],
                metadata: { count: 3, valid: true }
              }
            end
          end
        #{'  '}
          main do |inputs|
            begin
              execute_task(:collection_task, inputs: inputs)
            rescue => e
              { error: e.message, success: false }
            end
          end
        end
      RUBY

      agent = create_test_agent('strict-collections', agent_dsl)

      # Test valid collections
      result1 = execute_main_with_timing(agent, { mode: 'valid' })
      expect(result1[:success]).to be(true)
      expect(result1[:output][:items]).to eq([1, 2, 3])
      expect(result1[:output][:metadata][:count]).to eq(3)

      # Test invalid array type (should fail validation)
      result2 = execute_main_with_timing(agent, { mode: 'invalid' })
      expect(result2[:success]).to be(true)
      expect(result2[:output][:success]).to be(false)
      expect(result2[:output][:error]).to include('Expected array')
    end
  end

  describe 'Type coercion edge cases' do
    it 'handles invalid type coercion gracefully' do
      agent_dsl = <<~RUBY
        agent "coercion-errors" do
          task :error_prone_coercion,
            inputs: {#{' '}
              bad_integer: 'integer',
              bad_number: 'number',#{' '}
              bad_boolean: 'boolean'
            },
            outputs: { result: 'string' }
          do |inputs|
            { result: 'Should not reach here' }
          end
        #{'  '}
          main do |inputs|
            begin
              execute_task(:error_prone_coercion, inputs: inputs)
            rescue => e
              {#{' '}
                error_type: e.class.name,
                error_message: e.message,
                handled: true
              }
            end
          end
        end
      RUBY

      agent = create_test_agent('coercion-errors', agent_dsl)

      # Test invalid integer coercion
      result1 = execute_main_with_timing(agent, {
                                           bad_integer: 'not-a-number',
                                           bad_number: 3.14,
                                           bad_boolean: 'true'
                                         })
      expect(result1[:success]).to be(true)
      expect(result1[:output][:handled]).to be(true)
      expect(result1[:output][:error_message]).to include('Cannot coerce')

      # Test invalid boolean coercion
      result2 = execute_main_with_timing(agent, {
                                           bad_integer: '42',
                                           bad_number: '3.14',
                                           bad_boolean: 'maybe' # Invalid boolean value
                                         })
      expect(result2[:success]).to be(true)
      expect(result2[:output][:handled]).to be(true)
      expect(result2[:output][:error_message]).to include('Cannot coerce')
    end

    it 'handles null and empty values appropriately' do
      agent_dsl = <<~RUBY
        agent "null-handling" do
          task :handle_nulls,
            inputs: {#{' '}
              nullable_string: 'string',
              nullable_integer: 'integer',
              nullable_array: 'array'
            },
            outputs: {#{' '}
              processed: 'hash',
              summary: 'string'
            }
          do |inputs|
            {
              processed: {
                string_length: inputs[:nullable_string]&.length || 0,
                integer_value: inputs[:nullable_integer] || 0,
                array_size: inputs[:nullable_array]&.size || 0
              },
              summary: "Processed nullable inputs"
            }
          end
        #{'  '}
          main do |inputs|
            begin
              execute_task(:handle_nulls, inputs: inputs)
            rescue => e
              { error: e.message, success: false }
            end
          end
        end
      RUBY

      agent = create_test_agent('null-handling', agent_dsl)

      # Test with nil values (should fail validation)
      result = execute_main_with_timing(agent, {
                                          nullable_string: nil,
                                          nullable_integer: nil,
                                          nullable_array: nil
                                        })

      # Nil values should cause validation errors since inputs are required
      expect(result[:success]).to be(true)
      expect(result[:output][:success]).to be(false)
    end

    it 'handles boundary values for numeric types' do
      agent_dsl = <<~RUBY
        agent "boundary-values" do
          task :test_boundaries,
            inputs: {#{' '}
              large_integer: 'integer',
              small_integer: 'integer',
              large_number: 'number',
              tiny_number: 'number'
            },
            outputs: {#{' '}
              integer_sum: 'integer',
              number_sum: 'number',
              ranges: 'hash'
            }
          do |inputs|
            {
              integer_sum: inputs[:large_integer] + inputs[:small_integer],
              number_sum: inputs[:large_number] + inputs[:tiny_number],
              ranges: {
                integer_range: inputs[:large_integer] - inputs[:small_integer],
                number_range: inputs[:large_number] - inputs[:tiny_number]
              }
            }
          end
        #{'  '}
          main do |inputs|
            execute_task(:test_boundaries, inputs: inputs)
          end
        end
      RUBY

      agent = create_test_agent('boundary-values', agent_dsl)

      result = execute_main_with_timing(agent, {
                                          large_integer: '9999999999', # Large integer string
                                          small_integer: '-9999999999', # Large negative integer string
                                          large_number: '1.7976931348623157e+308',  # Near Float::MAX
                                          tiny_number: '2.2250738585072014e-308'    # Near Float::MIN
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:integer_sum]).to eq(0)
      expect(result[:output][:number_sum]).to be > 0
      expect(result[:output][:ranges][:integer_range]).to eq(19_999_999_998)
    end
  end

  describe 'Performance impact of type coercion' do
    it 'measures performance overhead of type coercion vs native types' do
      # Agent with type coercion
      coercion_dsl = <<~RUBY
        agent "with-coercion" do
          task :math_operations,
            inputs: { a: 'number', b: 'number', iterations: 'integer' },
            outputs: { result: 'number' }
          do |inputs|
            result = 0
            inputs[:iterations].times do
              result += inputs[:a] * inputs[:b]
            end
            { result: result }
          end
        #{'  '}
          main do |inputs|
            execute_task(:math_operations, inputs: inputs)
          end
        end
      RUBY

      # Agent with native types (no coercion needed)
      native_dsl = <<~RUBY
        agent "native-types" do
          task :math_operations,
            inputs: { a: 'number', b: 'number', iterations: 'integer' },
            outputs: { result: 'number' }
          do |inputs|
            result = 0
            inputs[:iterations].times do
              result += inputs[:a] * inputs[:b]
            end
            { result: result }
          end
        #{'  '}
          main do |inputs|
            execute_task(:math_operations, inputs: inputs)
          end
        end
      RUBY

      coercion_agent = create_test_agent('with-coercion', coercion_dsl)
      native_agent = create_test_agent('native-types', native_dsl)

      coerced_inputs = { a: '3.14', b: '2.718', iterations: '1000' } # All strings
      native_inputs = { a: 3.14, b: 2.718, iterations: 1000 } # Native types

      benchmark_comparison(
        'Type coercion overhead',
        -> { execute_main_with_timing(coercion_agent, coerced_inputs) },
        'Native types',
        -> { execute_main_with_timing(native_agent, native_inputs) }
      )

      # Both should produce same results
      coerced_result = execute_main_with_timing(coercion_agent, coerced_inputs)
      native_result = execute_main_with_timing(native_agent, native_inputs)

      expect(coerced_result[:success]).to be(true)
      expect(native_result[:success]).to be(true)
      expect(coerced_result[:output][:result]).to be_within(0.001).of(native_result[:output][:result])
    end
  end
end
