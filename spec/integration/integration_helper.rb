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
      
      # Connect agent for neural task execution using SYNTHESIS_* env vars
      begin
        puts "Attempting to connect agent..." if ENV['DEBUG']
        agent.connect!
        puts "Agent connected successfully" if ENV['DEBUG']
      rescue StandardError => e
        puts "Agent connection failed in test: #{e.message}"
        puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}" if ENV['DEBUG']
        # Try to continue anyway for symbolic-only tests
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
          'endpoint' => ENV['SYNTHESIS_ENDPOINT'],
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
    def verify_task_output(output, expected_schema)
      return false unless output.is_a?(Hash)

      expected_schema.each do |key, expected_type|
        return false unless output.key?(key)

        actual_value = output[key]
        return false unless type_matches?(actual_value, expected_type)
      end

      true
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
        puts "Using real local model at #{ENV['SYNTHESIS_ENDPOINT']}" if ENV['DEBUG']
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
    unless Integration::Config.mock_llm_responses?
      RSpec::Mocks.space.reset_all
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
      if ENV['ANTHROPIC_API_KEY']
        allowed_hosts << 'api.anthropic.com:443'
      end

      # Add OpenAI API if using OpenAI
      if ENV['OPENAI_API_KEY']
        allowed_hosts << 'api.openai.com:443'
      end

      WebMock.disable_net_connect!(allow: allowed_hosts) if allowed_hosts.any?
    else
      # When mocking, we still need to unmock RubyLLM to allow test configuration
      RSpec::Mocks.space.reset_all

      # Create a proper mock that accepts all configuration calls
      allow(RubyLLM).to receive(:configure) do |&block|
        mock_config = double('RubyLLM::Config')
        allow(mock_config).to receive(:openai_api_key=)
        allow(mock_config).to receive(:anthropic_api_key=)
        allow(mock_config).to receive(:request_timeout=)
        allow(mock_config).to receive(:respond_to?).and_return(true)
        block.call(mock_config) if block
      end

      allow(RubyLLM::MCP).to receive(:configure) do |&block|
        mock_config = double('RubyLLM::MCP::Config')
        allow(mock_config).to receive(:request_timeout=)
        allow(mock_config).to receive(:respond_to?).and_return(true)
        block.call(mock_config) if block
      end
    end

    setup_llm_mocks
  end

  config.after(:each, type: :integration) do
    teardown_llm_mocks
  end
end
