# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Hybrid Agent Execution', type: :integration do
  describe 'Neural and symbolic task combinations' do
    it 'executes mixed neural and symbolic tasks in sequence' do
      agent_dsl = <<~'RUBY'
        agent "hybrid-processor" do
          description "Agent with both neural and symbolic tasks"
          
          # Symbolic task - fast, deterministic data fetch
          task :fetch_user_data,
            inputs: { user_id: 'integer' },
            outputs: { user: 'hash', preferences: 'hash' }
          do |inputs|
            {
              user: { 
                id: inputs[:user_id], 
                name: "User #{inputs[:user_id]}", 
                email: "user#{inputs[:user_id]}@example.com" 
              },
              preferences: { 
                theme: 'dark', 
                notifications: true,
                language: 'en'
              }
            }
          end
          
          # Neural task - creative content generation
          task :generate_welcome_message,
            instructions: "Generate a personalized welcome message for the user",
            inputs: { user: 'hash', preferences: 'hash' },
            outputs: { message: 'string', tone: 'string' }
          
          # Symbolic task - deterministic message formatting
          task :format_response,
            inputs: { message: 'string', user: 'hash', tone: 'string' },
            outputs: { 
              formatted_message: 'string',
              metadata: 'hash'
            }
          do |inputs|
            {
              formatted_message: "#{inputs[:tone].upcase}: #{inputs[:message]} (for #{inputs[:user][:name]})",
              metadata: {
                user_id: inputs[:user][:id],
                timestamp: Time.now.iso8601,
                processed_by: 'hybrid-processor'
              }
            }
          end
          
          main do |inputs|
            # Step 1: Symbolic data fetch
            user_data = execute_task(:fetch_user_data, inputs: { user_id: inputs[:user_id] })
            
            # Step 2: Neural content generation
            welcome = execute_task(:generate_welcome_message, inputs: user_data)
            
            # Step 3: Symbolic formatting
            execute_task(:format_response, inputs: {
              message: welcome[:message],
              user: user_data[:user],
              tone: welcome[:tone]
            })
          end
        end
      RUBY

      agent = create_test_agent('hybrid-processor', agent_dsl)

      result = execute_main_with_timing(agent, { user_id: 123 })

      expect(result[:success]).to be(true)
      expect(result[:output]).to include(:formatted_message, :metadata)
      expect(result[:output][:formatted_message]).to include('User 123')
      expect(result[:output][:metadata][:user_id]).to eq(123)
      expect(result[:output][:metadata]).to include(:timestamp, :processed_by)
    end

    it 'handles data flow between neural and symbolic tasks' do
      agent_dsl = <<~'RUBY'
        agent "data-flow" do
          # Symbolic preprocessing
          task :preprocess_data,
            inputs: { raw_data: 'array' },
            outputs: { cleaned_data: 'array', stats: 'hash' }
          do |inputs|
            cleaned = inputs[:raw_data].compact.reject { |x| x.to_s.strip.empty? }
            {
              cleaned_data: cleaned,
              stats: {
                original_count: inputs[:raw_data].length,
                cleaned_count: cleaned.length,
                removed_count: inputs[:raw_data].length - cleaned.length
              }
            }
          end
          
          # Neural analysis
          task :analyze_patterns,
            instructions: "Analyze the cleaned data and identify patterns or insights",
            inputs: { cleaned_data: 'array', stats: 'hash' },
            outputs: { insights: 'array', confidence: 'number' }
          
          # Symbolic report generation
          task :generate_report,
            inputs: { insights: 'array', confidence: 'number', stats: 'hash' },
            outputs: { report: 'string', summary: 'hash' }
          do |inputs|
            report_lines = [
              "Data Analysis Report",
              "=" * 20,
              "Original records: #{inputs[:stats][:original_count]}",
              "Cleaned records: #{inputs[:stats][:cleaned_count]}",
              "Removed records: #{inputs[:stats][:removed_count]}",
              "",
              "Analysis Insights:",
              *inputs[:insights].map.with_index { |insight, i| "#{i+1}. #{insight}" },
              "",
              "Confidence Level: #{(inputs[:confidence] * 100).round(1)}%"
            ]
            
            {
              report: report_lines.join("\n"),
              summary: {
                total_insights: inputs[:insights].length,
                data_quality: inputs[:stats][:cleaned_count].to_f / inputs[:stats][:original_count],
                confidence: inputs[:confidence]
              }
            }
          end
          
          main do |inputs|
            # Symbolic preprocessing
            processed = execute_task(:preprocess_data, inputs: inputs)
            
            # Neural analysis
            analysis = execute_task(:analyze_patterns, inputs: processed)
            
            # Symbolic report generation
            execute_task(:generate_report, inputs: {
              insights: analysis[:insights],
              confidence: analysis[:confidence],
              stats: processed[:stats]
            })
          end
        end
      RUBY

      agent = create_test_agent('data-flow', agent_dsl)

      test_data = ['valid_data', nil, '', 'more_data', '  ', 'final_data']
      result = execute_main_with_timing(agent, { raw_data: test_data })

      expect(result[:success]).to be(true)
      expect(result[:output][:report]).to include('Data Analysis Report')
      expect(result[:output][:report]).to include('Original records: 6')
      expect(result[:output][:report]).to include('Cleaned records: 3')
      expect(result[:output][:summary][:total_insights]).to be > 0
      expect(result[:output][:summary][:data_quality]).to eq(0.5)
    end

    it 'optimizes execution by choosing appropriate task types' do
      agent_dsl = <<~'RUBY'
        agent "smart-optimizer" do
          # Fast symbolic computation
          task :calculate_statistics,
            inputs: { numbers: 'array' },
            outputs: { 
              sum: 'number', 
              average: 'number', 
              median: 'number',
              count: 'integer'
            }
          do |inputs|
            sorted = inputs[:numbers].sort
            {
              sum: inputs[:numbers].sum,
              average: inputs[:numbers].sum.to_f / inputs[:numbers].length,
              median: sorted[sorted.length / 2],
              count: inputs[:numbers].length
            }
          end
          
          # Creative neural interpretation
          task :interpret_results,
            instructions: "Interpret the statistical results and provide business insights",
            inputs: { 
              sum: 'number',
              average: 'number', 
              median: 'number',
              count: 'integer'
            },
            outputs: { interpretation: 'string', recommendations: 'array' }
          
          # Fast symbolic summary
          task :create_executive_summary,
            inputs: { 
              interpretation: 'string',
              recommendations: 'array',
              stats: 'hash'
            },
            outputs: { executive_summary: 'string' }
          do |inputs|
            {
              executive_summary: [
                "Executive Summary",
                "================",
                "",
                "Key Statistics:",
                "- Total data points: #{inputs[:stats][:count]}",
                "- Sum: #{inputs[:stats][:sum]}",
                "- Average: #{inputs[:stats][:average].round(2)}",
                "",
                "Analysis:",
                inputs[:interpretation],
                "",
                "Recommendations:",
                *inputs[:recommendations].map.with_index { |rec, i| "#{i+1}. #{rec}" }
              ].join("\n")
            }
          end
          
          main do |inputs|
            # Fast symbolic computation
            stats = execute_task(:calculate_statistics, inputs: inputs)
            
            # Creative neural interpretation
            insights = execute_task(:interpret_results, inputs: stats)
            
            # Fast symbolic summary
            execute_task(:create_executive_summary, inputs: {
              interpretation: insights[:interpretation],
              recommendations: insights[:recommendations],
              stats: stats
            })
          end
        end
      RUBY

      agent = create_test_agent('smart-optimizer', agent_dsl)

      # Test with realistic business data
      sales_data = [1200, 1500, 980, 1800, 1350, 1100, 1650, 1400, 1250, 1750]

      result = measure_performance('Hybrid optimization') do
        execute_main_with_timing(agent, { numbers: sales_data })
      end

      expect(result[:success]).to be(true)
      expect(result[:output][:executive_summary]).to include('Executive Summary')
      expect(result[:output][:executive_summary]).to include('Total data points: 10')
      expect(result[:output][:executive_summary]).to include('Average:')
      expect(result[:output][:executive_summary]).to include('Recommendations:')
    end
  end

  describe 'Complex hybrid workflows' do
    it 'handles conditional execution based on task outputs' do
      agent_dsl = <<~'RUBY'
        agent "conditional-processor" do
          # Symbolic validation
          task :validate_input,
            inputs: { data: 'hash' },
            outputs: { valid: 'boolean', errors: 'array' }
          do |inputs|
            errors = []
            data = inputs[:data]
            
            errors << 'Missing name' unless data[:name] && !data[:name].empty?
            errors << 'Invalid age' unless data[:age] && data[:age] > 0
            errors << 'Missing email' unless data[:email] && data[:email].include?('@')
            
            {
              valid: errors.empty?,
              errors: errors
            }
          end
          
          # Neural content generation (only for valid data)
          task :generate_profile,
            instructions: "Generate a professional profile description for the person",
            inputs: { data: 'hash' },
            outputs: { profile: 'string', keywords: 'array' }
          
          # Symbolic error formatting
          task :format_errors,
            inputs: { errors: 'array' },
            outputs: { error_message: 'string' }
          do |inputs|
            {
              error_message: "Validation failed:\n" + inputs[:errors].map { |e| "- #{e}" }.join("\n")
            }
          end
          
          main do |inputs|
            # Always validate first
            validation = execute_task(:validate_input, inputs: inputs)
            
            if validation[:valid]
              # Generate profile for valid data
              execute_task(:generate_profile, inputs: inputs)
            else
              # Format errors for invalid data
              execute_task(:format_errors, inputs: { errors: validation[:errors] })
            end
          end
        end
      RUBY

      agent = create_test_agent('conditional-processor', agent_dsl)

      # Test with valid data
      valid_data = {
        name: 'John Doe',
        age: 30,
        email: 'john@example.com'
      }

      result = execute_main_with_timing(agent, { data: valid_data })
      expect(result[:success]).to be(true)
      expect(result[:output]).to include(:profile, :keywords)

      # Test with invalid data
      invalid_data = {
        name: '',
        age: -5,
        email: 'invalid-email'
      }

      result = execute_main_with_timing(agent, { data: invalid_data })
      expect(result[:success]).to be(true)
      expect(result[:output]).to include(:error_message)
      expect(result[:output][:error_message]).to include('Missing name')
      expect(result[:output][:error_message]).to include('Invalid age')
      expect(result[:output][:error_message]).to include('Missing email')
    end

    it 'handles iterative processing with neural and symbolic tasks' do
      agent_dsl = <<~'RUBY'
        agent "iterative-processor" do
          # Symbolic batch preparation
          task :prepare_batch,
            inputs: { items: 'array', batch_size: 'integer' },
            outputs: { batches: 'array', total_batches: 'integer' }
          do |inputs|
            items = inputs[:items]
            batch_size = inputs[:batch_size]
            
            batches = items.each_slice(batch_size).to_a
            
            {
              batches: batches,
              total_batches: batches.length
            }
          end
          
          # Neural processing for each batch
          task :process_batch,
            instructions: "Process and enhance each item in the batch",
            inputs: { batch: 'array', batch_number: 'integer' },
            outputs: { processed_items: 'array', insights: 'string' }
          
          # Symbolic result aggregation
          task :aggregate_results,
            inputs: { all_results: 'array' },
            outputs: { 
              total_processed: 'integer',
              summary: 'string',
              performance_stats: 'hash'
            }
          do |inputs|
            all_items = inputs[:all_results].flat_map { |r| r[:processed_items] }
            all_insights = inputs[:all_results].map { |r| r[:insights] }
            
            {
              total_processed: all_items.length,
              summary: "Processed #{all_items.length} items in #{inputs[:all_results].length} batches",
              performance_stats: {
                batches_processed: inputs[:all_results].length,
                items_per_batch: all_items.length.to_f / inputs[:all_results].length,
                total_insights: all_insights.length
              }
            }
          end
          
          main do |inputs|
            # Prepare batches symbolically
            batch_info = execute_task(:prepare_batch, inputs: inputs)
            
            # Process each batch with neural task
            results = []
            batch_info[:batches].each_with_index do |batch, index|
              result = execute_task(:process_batch, inputs: {
                batch: batch,
                batch_number: index + 1
              })
              results << result
            end
            
            # Aggregate symbolically
            execute_task(:aggregate_results, inputs: { all_results: results })
          end
        end
      RUBY

      agent = create_test_agent('iterative-processor', agent_dsl)

      test_items = (1..15).map { |i| "item_#{i}" }
      result = execute_main_with_timing(agent, {
                                          items: test_items,
                                          batch_size: 5
                                        })

      expect(result[:success]).to be(true)
      expect(result[:output][:total_processed]).to eq(15)
      expect(result[:output][:performance_stats][:batches_processed]).to eq(3)
      expect(result[:output][:performance_stats][:items_per_batch]).to eq(5.0)
    end
  end

  describe 'Performance optimization in hybrid agents' do
    it 'demonstrates performance benefits of strategic task type selection' do
      # Create two versions: one optimized, one suboptimal

      optimized_dsl = <<~RUBY
        agent "optimized" do
          # Fast symbolic preprocessing
          task :preprocess do |inputs|
            { data: inputs[:data].map(&:to_i).select(&:positive?) }
          end
        #{'  '}
          # Neural analysis only where needed
          task :analyze,
            instructions: "Analyze trends in the data",
            inputs: { data: 'array' },
            outputs: { trend: 'string' }
        #{'  '}
          # Fast symbolic calculation
          task :calculate do |inputs|
            { sum: inputs[:data].sum, avg: inputs[:data].sum.to_f / inputs[:data].length }
          end
        #{'  '}
          main do |inputs|
            cleaned = execute_task(:preprocess, inputs: inputs)
            stats = execute_task(:calculate, inputs: cleaned)
            trend = execute_task(:analyze, inputs: cleaned)
            stats.merge(trend)
          end
        end
      RUBY

      suboptimal_dsl = <<~RUBY
        agent "suboptimal" do
          # Neural preprocessing (unnecessarily slow)
          task :preprocess,
            instructions: "Clean and prepare the data array",
            inputs: { data: 'array' },
            outputs: { data: 'array' }
        #{'  '}
          # Neural analysis
          task :analyze,
            instructions: "Analyze trends in the data",#{' '}
            inputs: { data: 'array' },
            outputs: { trend: 'string' }
        #{'  '}
          # Neural calculation (unnecessarily slow)
          task :calculate,
            instructions: "Calculate sum and average of the data",
            inputs: { data: 'array' },
            outputs: { sum: 'number', avg: 'number' }
        #{'  '}
          main do |inputs|
            cleaned = execute_task(:preprocess, inputs: inputs)
            stats = execute_task(:calculate, inputs: cleaned)#{' '}
            trend = execute_task(:analyze, inputs: cleaned)
            stats.merge(trend)
          end
        end
      RUBY

      optimized_agent = create_test_agent('optimized', optimized_dsl)
      suboptimal_agent = create_test_agent('suboptimal', suboptimal_dsl)

      test_data = { data: ['1', '2', '0', '3', '-1', '4', '5'] }

      benchmark_comparison(
        'Optimized (strategic symbolic tasks)',
        -> { execute_main_with_timing(optimized_agent, test_data) },
        'Suboptimal (unnecessary neural tasks)',
        -> { execute_main_with_timing(suboptimal_agent, test_data) }
      )
    end
  end
end
