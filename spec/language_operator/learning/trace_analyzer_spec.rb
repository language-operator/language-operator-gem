# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/learning/trace_analyzer'
require 'webmock/rspec'

RSpec.describe LanguageOperator::Learning::TraceAnalyzer do
  let(:endpoint) { 'https://example.signoz.io' }
  let(:api_key) { 'test-api-key' }

  before do
    # Stub all backend availability checks to fail by default
    stub_request(:head, %r{/api/v5/query_range}).to_return(status: 404)
    stub_request(:get, %r{/api/traces}).to_return(status: 404)
    stub_request(:get, %r{/api/search}).to_return(status: 404)
  end

  describe '#initialize' do
    it 'accepts endpoint and api_key parameters' do
      analyzer = described_class.new(endpoint: endpoint, api_key: api_key)
      expect(analyzer).to be_a(described_class)
    end

    it 'reads endpoint from ENV if not provided' do
      ENV['OTEL_QUERY_ENDPOINT'] = endpoint
      analyzer = described_class.new
      expect(analyzer.available?).to be false # No backend mocked

      ENV.delete('OTEL_QUERY_ENDPOINT')
    end

    it 'accepts explicit backend parameter' do
      analyzer = described_class.new(endpoint: endpoint, backend: 'signoz')
      expect(analyzer).to be_a(described_class)
    end
  end

  describe '#available?' do
    it 'returns false when no endpoint configured' do
      analyzer = described_class.new
      expect(analyzer.available?).to be false
    end

    it 'returns false when no backends are available' do
      analyzer = described_class.new(endpoint: endpoint)
      expect(analyzer.available?).to be false
    end

    it 'returns true when a backend is available' do
      # Stub SigNoz availability check to succeed
      stub_request(:head, "#{endpoint}/api/v5/query_range")
        .to_return(status: 405) # SigNoz returns 405 for HEAD

      analyzer = described_class.new(endpoint: endpoint)
      expect(analyzer.available?).to be true
    end
  end

  describe '#query_task_traces' do
    it 'returns empty array when no backend available' do
      analyzer = described_class.new
      result = analyzer.query_task_traces(task_name: 'test_task')
      expect(result).to eq([])
    end

    it 'queries backend when available' do
      stub_request(:head, "#{endpoint}/api/v5/query_range").to_return(status: 405)
      stub_request(:post, "#{endpoint}/api/v5/query_range")
        .to_return(status: 200, body: JSON.generate(sample_signoz_response))

      analyzer = described_class.new(endpoint: endpoint, api_key: api_key)
      result = analyzer.query_task_traces(task_name: 'fetch_data', limit: 100)

      expect(result).to be_an(Array)
    end

    it 'handles errors gracefully' do
      stub_request(:head, "#{endpoint}/api/v5/query_range").to_return(status: 405)
      stub_request(:post, "#{endpoint}/api/v5/query_range")
        .to_return(status: 500, body: 'Internal Server Error')

      analyzer = described_class.new(endpoint: endpoint, api_key: api_key)
      result = analyzer.query_task_traces(task_name: 'test_task')
      expect(result).to eq([])
    end
  end

  describe '#analyze_patterns' do
    it 'returns nil when no executions found' do
      stub_request(:head, "#{endpoint}/api/v5/query_range").to_return(status: 405)
      stub_request(:post, "#{endpoint}/api/v5/query_range")
        .to_return(status: 200, body: JSON.generate({ data: { result: [] } }))

      analyzer = described_class.new(endpoint: endpoint, api_key: api_key)
      result = analyzer.analyze_patterns(task_name: 'missing_task')
      expect(result).to be_nil
    end

    it 'returns insufficient data status when < min_executions' do
      stub_request(:head, "#{endpoint}/api/v5/query_range").to_return(status: 405)
      stub_request(:post, "#{endpoint}/api/v5/query_range")
        .to_return(status: 200, body: JSON.generate(sample_signoz_response(execution_count: 5)))

      analyzer = described_class.new(endpoint: endpoint, api_key: api_key)
      result = analyzer.analyze_patterns(task_name: 'new_task', min_executions: 10)

      expect(result).to be_a(Hash)
      expect(result[:execution_count]).to eq(5)
      expect(result[:ready_for_learning]).to be false
    end

    it 'analyzes patterns and returns consistency score' do
      stub_request(:head, "#{endpoint}/api/v5/query_range").to_return(status: 405)
      stub_request(:post, "#{endpoint}/api/v5/query_range")
        .to_return(status: 200, body: JSON.generate(sample_signoz_response(execution_count: 15)))

      analyzer = described_class.new(endpoint: endpoint, api_key: api_key)
      result = analyzer.analyze_patterns(task_name: 'consistent_task', min_executions: 10)

      expect(result).to be_a(Hash)
      expect(result[:execution_count]).to eq(15)
      expect(result[:consistency_score]).to be_a(Float)
      expect(result[:consistency_score]).to be >= 0.0
      expect(result[:consistency_score]).to be <= 1.0
    end
  end

  describe '#calculate_consistency' do
    let(:analyzer) { described_class.new }

    it 'calculates 100% consistency for identical patterns' do
      executions = [
        { inputs: { id: 1 }, tool_calls: [{ tool_name: 'db' }, { tool_name: 'cache' }] },
        { inputs: { id: 2 }, tool_calls: [{ tool_name: 'db' }, { tool_name: 'cache' }] },
        { inputs: { id: 3 }, tool_calls: [{ tool_name: 'db' }, { tool_name: 'cache' }] }
      ]

      result = analyzer.calculate_consistency(executions)

      expect(result[:score]).to eq(1.0)
      expect(result[:common_pattern]).to eq('db → cache')
    end

    it 'calculates partial consistency for mixed patterns with same input' do
      # All executions have the same input signature (empty hash)
      executions = [
        { inputs: {}, tool_calls: [{ tool_name: 'db' }] },
        { inputs: {}, tool_calls: [{ tool_name: 'db' }] },
        { inputs: {}, tool_calls: [{ tool_name: 'db' }] },
        { inputs: {}, tool_calls: [{ tool_name: 'api' }] } # Different!
      ]

      result = analyzer.calculate_consistency(executions)

      # Most common is 'db' (3/4 = 75%)
      expect(result[:score]).to eq(0.75)
    end

    it 'handles different input signatures separately' do
      executions = [
        # Input signature 1: always uses 'db'
        { inputs: { type: 'user' }, tool_calls: [{ tool_name: 'db' }] },
        { inputs: { type: 'user' }, tool_calls: [{ tool_name: 'db' }] },
        # Input signature 2: always uses 'api'
        { inputs: { type: 'admin' }, tool_calls: [{ tool_name: 'api' }] },
        { inputs: { type: 'admin' }, tool_calls: [{ tool_name: 'api' }] }
      ]

      result = analyzer.calculate_consistency(executions)

      # Both signatures are 100% consistent internally
      expect(result[:score]).to eq(1.0)
      expect(result[:input_signatures]).to eq(2)
    end
  end

  # Helper methods

  def sample_signoz_response(execution_count: 1)
    spans = execution_count.times.map do |i|
      {
        spanID: "span-#{i}",
        traceID: "trace-#{i}",
        name: 'task_executor.execute_task',
        timestamp: (Time.now.to_f * 1_000_000_000).to_i - (i * 1000),
        durationNano: 500_000_000,
        stringTagMap: {
          'task.name' => 'fetch_data',
          'task.input.keys' => 'user_id',
          'task.output.keys' => 'user'
        },
        numberTagMap: {}
      }
    end

    {
      data: {
        result: [
          {
            list: spans
          }
        ]
      }
    }
  end
end
