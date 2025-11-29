# frozen_string_literal: true

require_relative '../spec_helper'
require 'webmock/rspec'
require 'benchmark'

# Integration test helper for DSL v1 task execution
#
# Provides utilities for testing neural, symbolic, and hybrid agents
# with comprehensive coverage of task execution scenarios.
module Integration
  # Configuration for integration tests
  module Config
    def self.mock_llm_responses?
      ENV.fetch('INTEGRATION_MOCK_LLM', 'true') == 'true'
    end

    def self.performance_benchmarks?
      ENV.fetch('INTEGRATION_BENCHMARK', 'false') == 'true'
    end

    def self.test_timeout
      ENV.fetch('INTEGRATION_TIMEOUT', '30').to_i
    end
  end

  # Helper methods for creating test agents and executing tasks
  module Helpers
    # Create a test agent with DSL v1 syntax
    #
    # @param agent_name [String] Name for the agent
    # @param dsl_code [String] Ruby DSL code defining the agent
    # @return [LanguageOperator::Agent::Base] Configured agent instance
    def create_test_agent(agent_name, dsl_code)
      # Create temporary agent file
      agent_file = "/tmp/#{agent_name}_#{Time.now.to_f}.rb"
      File.write(agent_file, dsl_code)

      # Load agent definition
      agent_registry = LanguageOperator::Dsl.load_agent_file(agent_file)
      agent_def = agent_registry.get(agent_name)

      raise "Agent '#{agent_name}' not found in DSL" unless agent_def

      # Create agent instance with mock configuration
      config = create_mock_config
      agent = LanguageOperator::Agent::Base.new(config)
      agent.instance_variable_set(:@definition, agent_def)

      # Connect agent for neural task execution if not mocking
      if Integration::Config.mock_llm_responses?
        # When mocking, create a mock chat object
        mock_chat = double('Chat')
        allow(mock_chat).to receive(:ask) do |message|
          # Generate mock response based on the message
          mock_neural_response(message)
        end
        allow(mock_chat).to receive(:messages).and_return([])

        agent.instance_variable_set(:@chat, mock_chat)
        agent.instance_variable_set(:@connected, true)
      else
        begin
          puts 'Attempting to connect agent...' if ENV['DEBUG']
          agent.connect!
          puts 'Agent connected successfully' if ENV['DEBUG']
        rescue StandardError => e
          puts "Agent connection failed in test: #{e.message}"
          puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}" if ENV['DEBUG']
          raise 'Failed to connect agent for real LLM testing' unless ENV['CI']
        end
      end

      # Clean up temporary file
      FileUtils.rm_f(agent_file)

      agent
    end

    # Create mock configuration for testing
    def create_mock_config
      {
        'model' => 'test-model',
        'persona_name' => 'test-persona',
        'mcp_servers' => [],
        'max_tokens' => 1000,
        'temperature' => 0.7,
        'llm' => {
          'provider' => if ENV['ANTHROPIC_API_KEY']
                          'anthropic'
                        elsif ENV['SYNTHESIS_ENDPOINT']
                          'openai_compatible'
                        else
                          'openai'
                        end,
          'model' => ENV['ANTHROPIC_MODEL'] || ENV['SYNTHESIS_MODEL'] || 'gpt-4o-mini',
          'api_key' => ENV['ANTHROPIC_API_KEY'] || ENV['SYNTHESIS_API_KEY'] || 'test-api-key',
          'endpoint' => ENV.fetch('SYNTHESIS_ENDPOINT', nil),
          'timeout' => 600 # 10 minutes to match task timeout
        }
      }
    end

    # Execute a main block with performance measurement
    #
    # @param agent [LanguageOperator::Agent::Base] Agent instance
    # @param inputs [Hash] Inputs for the main block
    # @return [Hash] Execution results with performance metrics
    def execute_main_with_timing(agent, inputs = {})
      results = {}

      timing = Benchmark.measure do
        results[:output] = execute_main_block(agent, inputs)
      end

      results[:execution_time] = timing.real
      results[:success] = true
      results
    rescue StandardError => e
      {
        success: false,
        error: e,
        execution_time: timing&.real || 0
      }
    end

    # Execute main block (core functionality)
    def execute_main_block(agent, inputs = {})
      agent_def = agent.instance_variable_get(:@definition)
      main_def = agent_def.main

      raise 'Agent has no main block' unless main_def

      # Create task executor with agent configuration
      executor_config = LanguageOperator::Agent.build_executor_config(agent_def)
      task_executor = LanguageOperator::Agent::TaskExecutor.new(agent, agent_def.tasks, executor_config)

      # Execute main block with task executor as context
      main_def.call(inputs, task_executor)
    end

    # Execute a single task for testing
    #
    # @param agent [LanguageOperator::Agent::Base] Agent instance
    # @param task_name [Symbol] Name of task to execute
    # @param inputs [Hash] Task inputs
    # @return [Hash] Task outputs
    def execute_task_direct(agent, task_name, inputs = {})
      agent_def = agent.instance_variable_get(:@definition)
      task_executor = LanguageOperator::Agent::TaskExecutor.new(agent, agent_def.tasks)

      task_executor.execute_task(task_name, inputs: inputs)
    end

    # Verify task output schema matches expected types
    # rubocop:disable Naming/PredicateMethod
    def verify_task_output(output, expected_schema)
      return false unless output.is_a?(Hash)

      expected_schema.each do |key, expected_type|
        return false unless output.key?(key)

        actual_value = output[key]
        return false unless type_matches?(actual_value, expected_type)
      end

      true
    end
    # rubocop:enable Naming/PredicateMethod

    # Generate mock response for neural tasks
    def mock_neural_response(message)
      # Extract task name and instructions from the message
      case message
      when /interpret.*statistical.*results.*business.*insights/im, /interpret.*results.*business.*insights/im, /task:\s*interpret_results/im
        # Mock result interpretation (hybrid tests) - MUST BE FIRST to avoid sum pattern match
        { interpretation: 'Sales data shows strong growth', recommendations: ['Increase inventory', 'Expand marketing'] }.to_json
      when /process.*numeric.*inputs.*statistics/im, /task:\s*process_numbers/im
        # Mock numeric processing (neural task tests)
        { summary: 'Processed numeric data with statistics: count=5, rate=85.5%, active=true' }.to_json
      when /convert.*number.*string/im, /task:\s*strict_task/im
        # Mock number to string conversion (neural task tests)
        { result: '42' }.to_json
      when /clean.*raw data.*identify anomalies.*validate data quality/i
        # Mock data cleaning response (comprehensive_integration_spec.rb - clean_and_validate task)
        # Outputs: clean_data (array), anomalies (array), quality_score (number)
        {
          clean_data: [{ id: 1, value: 100 }, { id: 2, value: 200 }],
          anomalies: [],
          quality_score: 0.95
        }.to_json
      when /generate.*helpful.*professional customer service response/i
        # Mock customer service response (comprehensive_integration_spec.rb - generate_response task)
        # Outputs: response (string), follow_up_questions (array), escalate_to_human (boolean)
        {
          response: 'Thank you for contacting us. Your order #12345 will arrive within 3-5 business days.',
          follow_up_questions: ['Would you like tracking information?', 'Do you need to update your delivery address?'],
          escalate_to_human: false
        }.to_json
      when /analyze.*financial.*metric.*risk|assess.*financial.*risk/i
        # Mock risk analysis (comprehensive_integration_spec.rb - assess_financial_risk task)
        # Outputs: risk_score (number), risk_factors (array), recommendations (array)
        {
          risk_score: 0.25,
          risk_factors: ['market volatility', 'currency fluctuation'],
          recommendations: ['diversify portfolio', 'hedge currency risk']
        }.to_json
      when /analyze.*transformed data.*generate business insights/i
        # Mock insights generation (comprehensive_integration_spec.rb - generate_insights task)
        # Outputs: insights (array), recommendations (array), confidence (number)
        {
          insights: [
            'Data quality has improved by 15% over the previous period',
            'High-value category accounts for 60% of total volume'
          ],
          recommendations: [
            'Focus marketing efforts on high-value category',
            'Implement additional validation for low-quality sources'
          ],
          confidence: 0.87
        }.to_json
      when /get.*current weather.*given location/i
        # Mock weather task (neural_task_execution_spec.rb - get_weather task)
        # Outputs: temperature (number), condition (string), humidity (number)
        {
          temperature: 72,
          condition: 'sunny',
          humidity: 45
        }.to_json
      when /fetch.*comprehensive user data/i
        # Mock user data fetch (neural_task_execution_spec.rb - fetch_user_data task)
        # Outputs: user (hash), preferences (hash)
        {
          user: { id: 123, name: 'Test User', email: 'test@example.com' },
          preferences: { theme: 'dark', notifications: true }
        }.to_json
      when /calculate.*total.*sum.*provided numbers/i
        # Mock calculation for specific neural test
        { total: 42.5 }.to_json
      when /^.*sum.*$(?!.*interpret)/im
        # Mock calculation (excluding interpret_results)
        { total: 42.5 }.to_json
      when /analyze.*provided data.*generate insights.*using.*tools/i
        # Mock data analysis with tools (neural_task_execution_spec.rb - analyze_data task)
        { insights: 'Data shows positive trend with 20% growth', metrics: { growth: 0.2, trend: 'positive' } }.to_json
      when /validate.*input.*properly formatted email/i
        # Mock email validation (neural_task_execution_spec.rb - validate_email task)
        { valid: false, reason: 'Missing @ symbol' }.to_json
      when /process.*required data field/i
        # Mock data processing (neural_task_execution_spec.rb - process_data task)
        { result: 'Processed successfully' }.to_json
      when /provide.*quick response.*input/i, /quick response/i
        # Mock quick response (neural_task_execution_spec.rb - quick_response task)
        { response: 'Quick response generated', timing: 0.1 }.to_json
      when /process step one/i
        # Mock task one (neural_task_execution_spec.rb - task_one)
        { result: 'Step one complete', status: 'success' }.to_json
      when /process step two/i
        # Mock task two (neural_task_execution_spec.rb - task_two)
        { result: 'Step two complete', status: 'success' }.to_json
      when /process numeric inputs.*return statistics/i, /process.*numbers/i
        # Mock numeric processing (neural_task_execution_spec.rb - process_numbers task)
        { sum: 150, average: 30, max: 50, min: 10 }.to_json
      when /validate strict input requirements/i, /strict.*task/i
        # Mock strict task validation
        { output: 'Validated successfully', passed: true }.to_json
      when /generate.*personalized welcome message/i
        # Mock welcome message generation (hybrid tests)
        { message: 'Welcome to our platform! We are excited to have you here.', tone: 'friendly' }.to_json
      when /analyze.*cleaned data.*identify patterns/i
        # Mock pattern analysis (hybrid tests)
        { insights: ['Pattern A detected', 'Trend B observed'], confidence: 0.85 }.to_json
      when /generate.*professional profile description/i
        # Mock profile generation (hybrid tests)
        { profile: 'Professional with extensive experience', keywords: %w[experienced skilled professional] }.to_json
      when /process.*enhance.*item.*batch/i
        # Mock batch processing (hybrid tests) - extract actual batch size from message
        batch_match = message.match(/batch:\s*\[(.*?)\]/m)
        if batch_match
          # Count items in the batch by counting commas + 1
          item_count = batch_match[1].split(',').length
          processed_items = (1..item_count).map { |i| "enhanced_item_#{i}" }
        else
          # Fallback for unexpected format
          processed_items = %w[enhanced_item_1 enhanced_item_2]
        end
        { processed_items: processed_items, insights: 'Batch processed successfully' }.to_json
      when /analyze trends.*data/i
        # Mock trend analysis (hybrid tests)
        { trend: 'upward' }.to_json
      when /clean.*prepare.*data array/i
        # Mock data cleaning (hybrid tests)
        { data: [1, 2, 3, 4, 5] }.to_json
      when /calculate.*sum.*average.*data/i
        # Mock calculation (hybrid tests)
        { sum: 15, avg: 3 }.to_json
      when /analyze.*sentiment/i
        # Mock sentiment analysis
        { sentiment: 'positive', confidence: 0.85, keywords: %w[good excellent] }.to_json
      when /summarize|summary/i
        # Mock summarization
        { summary: 'This is a comprehensive summary of the analyzed data.' }.to_json
      else
        # Default mock response - return generic JSON that most schemas will accept
        { result: 'Mock neural task result', success: true, data: {} }.to_json
      end
    end

    private

    def type_matches?(value, type_string)
      case type_string
      when 'string'
        value.is_a?(String)
      when 'integer'
        value.is_a?(Integer)
      when 'number'
        value.is_a?(Numeric)
      when 'boolean'
        value.is_a?(TrueClass) || value.is_a?(FalseClass)
      when 'array'
        value.is_a?(Array)
      when 'hash'
        value.is_a?(Hash)
      when 'any'
        true
      else
        false
      end
    end
  end

  # Mock LLM responses for neural task testing
  module LLMMocks
    def setup_llm_mocks
      return unless Integration::Config.mock_llm_responses?

      # If using local SYNTHESIS model, don't mock HTTP requests
      if ENV['SYNTHESIS_ENDPOINT']
        puts "Using real local model at #{ENV.fetch('SYNTHESIS_ENDPOINT', nil)}" if ENV['DEBUG']
        return
      end

      WebMock.enable!
      WebMock.reset!

      # Mock OpenAI-style LLM responses
      stub_request(:post, %r{/v1/chat/completions})
        .to_return { |request| mock_llm_response(request) }
    end

    def teardown_llm_mocks
      return unless Integration::Config.mock_llm_responses?
      return if ENV['SYNTHESIS_ENDPOINT'] # Skip if using real model

      WebMock.reset!
      WebMock.disable!
    end

    private

    def mock_llm_response(request)
      body = JSON.parse(request.body)
      messages = body['messages']

      # Extract task instructions from the prompt
      prompt = messages.last['content']

      # Generate mock response based on task type
      response_content = generate_mock_response(prompt)

      {
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          choices: [{
            message: {
              role: 'assistant',
              content: response_content
            }
          }],
          usage: {
            prompt_tokens: 100,
            completion_tokens: 50,
            total_tokens: 150
          }
        }.to_json
      }
    end

    def generate_mock_response(prompt)
      case prompt
      when /fetch.*user.*data/i
        # Mock user data fetch
        {
          user: { id: 123, name: 'Test User', email: 'test@example.com' },
          preferences: { theme: 'dark', notifications: true }
        }.to_json
      when /calculate.*total/i, /sum/i
        # Mock calculation
        { total: 42.5 }.to_json
      when /analyze.*sentiment/i
        # Mock sentiment analysis
        { sentiment: 'positive', confidence: 0.85 }.to_json
      when /generate.*report/i
        # Mock report generation
        { report: 'This is a test report generated by the mock LLM.' }.to_json
      when /weather/i
        # Mock weather data
        {
          location: 'Test City',
          temperature: 72,
          condition: 'sunny',
          humidity: 45
        }.to_json
      else
        # Default mock response
        {
          result: 'Mock LLM response',
          processed: true,
          timestamp: Time.now.iso8601
        }.to_json
      end
    end
  end

  # Performance measurement utilities
  module Performance
    def measure_performance(description, &block)
      return yield unless Integration::Config.performance_benchmarks?

      puts "\n→ Measuring performance: #{description}"

      # Warm up
      block.call

      # Measure multiple runs
      times = []
      5.times do
        timing = Benchmark.measure { block.call }
        times << timing.real
      end

      avg_time = times.sum / times.size
      min_time = times.min
      max_time = times.max

      puts "  Average: #{(avg_time * 1000).round(2)}ms"
      puts "  Range: #{(min_time * 1000).round(2)}ms - #{(max_time * 1000).round(2)}ms"

      # Return last execution result
      block.call
    end

    def benchmark_comparison(label1, block1, label2, block2)
      return unless Integration::Config.performance_benchmarks?

      puts "\n→ Performance comparison: #{label1} vs #{label2}"

      time1 = Benchmark.measure { block1.call }.real
      time2 = Benchmark.measure { block2.call }.real

      faster = time1 < time2 ? label1 : label2
      speedup = [(time1 / time2), (time2 / time1)].max

      puts "  #{label1}: #{(time1 * 1000).round(2)}ms"
      puts "  #{label2}: #{(time2 * 1000).round(2)}ms"
      puts "  #{faster} is #{speedup.round(2)}x faster"
    end
  end
end

# Include helpers in RSpec
RSpec.configure do |config|
  config.include Integration::Helpers, type: :integration
  config.include Integration::LLMMocks, type: :integration
  config.include Integration::Performance, type: :integration

  config.before(:each, type: :integration) do
    # If using real LLM (not mocked), unmock RubyLLM and allow HTTP
    RSpec::Mocks.space.reset_all
    if Integration::Config.mock_llm_responses?
      # When mocking, we still need to unmock RubyLLM to allow test configuration

      # Create a proper mock that accepts all configuration calls
      allow(RubyLLM).to receive(:configure) do |&block|
        mock_config = double('RubyLLM::Config')
        allow(mock_config).to receive(:openai_api_key=)
        allow(mock_config).to receive(:anthropic_api_key=)
        allow(mock_config).to receive(:request_timeout=)
        allow(mock_config).to receive(:respond_to?).and_return(true)
        block&.call(mock_config)
      end

      allow(RubyLLM::MCP).to receive(:configure) do |&block|
        mock_config = double('RubyLLM::MCP::Config')
        allow(mock_config).to receive(:request_timeout=)
        allow(mock_config).to receive(:respond_to?).and_return(true)
        block&.call(mock_config)
      end
    else
      allow(RubyLLM).to receive(:configure).and_call_original
      allow(RubyLLM::MCP).to receive(:configure).and_call_original

      # Allow HTTP connections to local model and cloud APIs
      allowed_hosts = []

      # Add local synthesis endpoint if available
      if ENV['SYNTHESIS_ENDPOINT']
        synthesis_host = URI(ENV['SYNTHESIS_ENDPOINT']).host
        synthesis_port = URI(ENV['SYNTHESIS_ENDPOINT']).port
        allowed_hosts << "#{synthesis_host}:#{synthesis_port}"
      end

      # Add Anthropic API if using Claude
      allowed_hosts << 'api.anthropic.com:443' if ENV['ANTHROPIC_API_KEY']

      # Add OpenAI API if using OpenAI
      allowed_hosts << 'api.openai.com:443' if ENV['OPENAI_API_KEY']

      WebMock.disable_net_connect!(allow: allowed_hosts) if allowed_hosts.any?
    end

    setup_llm_mocks
  end

  config.after(:each, type: :integration) do
    teardown_llm_mocks
  end
end
