# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/learning/adapters/signoz_adapter'
require 'webmock/rspec'

RSpec.describe LanguageOperator::Learning::Adapters::SignozAdapter do
  let(:endpoint) { 'https://example.signoz.io' }
  let(:api_key) { 'test-api-key' }
  let(:adapter) { described_class.new(endpoint, api_key) }

  describe '.available?' do
    it 'returns true when SigNoz API is reachable' do
      stub_request(:head, "#{endpoint}/api/v5/query_range")
        .to_return(status: 405) # SigNoz returns 405 for HEAD (POST only)

      expect(described_class.available?(endpoint)).to be true
    end

    it 'returns true for 200 response' do
      stub_request(:head, "#{endpoint}/api/v5/query_range")
        .to_return(status: 200)

      expect(described_class.available?(endpoint)).to be true
    end

    it 'returns false when endpoint is unreachable' do
      stub_request(:head, "#{endpoint}/api/v5/query_range")
        .to_timeout

      expect(described_class.available?(endpoint)).to be false
    end

    it 'returns false for error responses' do
      stub_request(:head, "#{endpoint}/api/v5/query_range")
        .to_return(status: 404)

      expect(described_class.available?(endpoint)).to be false
    end
  end

  describe '#query_spans' do
    it 'sends POST request to SigNoz query endpoint' do
      stub = stub_request(:post, "#{endpoint}/api/v5/query_range")
             .with(
               headers: {
                 'Content-Type' => 'application/json',
                 'SIGNOZ-API-KEY' => api_key
               }
             )
             .to_return(status: 200, body: JSON.generate(empty_response))

      adapter.query_spans(
        filter: { task_name: 'test_task' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(stub).to have_been_requested
    end

    it 'includes task name filter in query' do
      received_body = nil
      stub = stub_request(:post, "#{endpoint}/api/v5/query_range")
             .to_return do |request|
        received_body = JSON.parse(request.body, symbolize_names: true)
        { status: 200, body: JSON.generate(empty_response) }
      end

      adapter.query_spans(
        filter: { task_name: 'fetch_user' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(stub).to have_been_requested
      filters = received_body.dig(:compositeQuery, :builderQueries, :A, :filters, :items)
      expect(filters).to include(hash_including(key: hash_including(key: 'task.name'), value: 'fetch_user'))
    end

    it 'converts time range to unix milliseconds' do
      start_time = Time.parse('2025-01-01 00:00:00 UTC')
      end_time = Time.parse('2025-01-01 01:00:00 UTC')

      stub = stub_request(:post, "#{endpoint}/api/v5/query_range")
             .with(body: hash_including(
               start: (start_time.to_f * 1000).to_i,
               end: (end_time.to_f * 1000).to_i
             ))
             .to_return(status: 200, body: JSON.generate(empty_response))

      adapter.query_spans(
        filter: { task_name: 'test' },
        time_range: start_time..end_time,
        limit: 100
      )

      expect(stub).to have_been_requested
    end

    it 'parses SigNoz response into normalized spans' do
      stub_request(:post, "#{endpoint}/api/v5/query_range")
        .to_return(status: 200, body: JSON.generate(sample_response))

      result = adapter.query_spans(
        filter: { task_name: 'test_task' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)

      span = result.first
      expect(span).to include(:span_id, :trace_id, :name, :timestamp, :duration_ms, :attributes)
      expect(span[:attributes]).to include('task.name' => 'test_task')
    end

    it 'raises error on API failure' do
      stub_request(:post, "#{endpoint}/api/v5/query_range")
        .to_return(status: 500, body: 'Internal Server Error')

      expect do
        adapter.query_spans(
          filter: { task_name: 'test' },
          time_range: (Time.now - 3600)..Time.now,
          limit: 100
        )
      end.to raise_error(/SigNoz query failed/)
    end
  end

  describe '#extract_task_data' do
    it 'groups spans by trace ID' do
      spans = [
        { trace_id: 'trace-1', span_id: 'span-1', name: 'task_executor.execute_task', attributes: { 'task.name' => 'test' }, duration_ms: 100, timestamp: Time.now },
        { trace_id: 'trace-1', span_id: 'span-2', name: 'gen_ai.chat', attributes: {}, duration_ms: 50, timestamp: Time.now },
        { trace_id: 'trace-2', span_id: 'span-3', name: 'task_executor.execute_task', attributes: { 'task.name' => 'test' }, duration_ms: 200, timestamp: Time.now }
      ]

      result = adapter.extract_task_data(spans)

      expect(result.size).to eq(2)
      expect(result.map { |r| r[:trace_id] }).to match_array(%w[trace-1 trace-2])
    end

    it 'extracts inputs from task.input.* attributes' do
      spans = [
        {
          trace_id: 'trace-1',
          span_id: 'span-1',
          name: 'task_executor.execute_task',
          attributes: {
            'task.name' => 'fetch_user',
            'task.input.keys' => 'user_id,include_profile',
            'task.input.user_id' => '123',
            'task.input.include_profile' => 'true'
          },
          duration_ms: 100,
          timestamp: Time.now
        }
      ]

      result = adapter.extract_task_data(spans)

      expect(result.first[:inputs]).to eq({
                                            user_id: '123',
                                            include_profile: 'true'
                                          })
    end

    it 'extracts outputs from task.output.* attributes' do
      spans = [
        {
          trace_id: 'trace-1',
          span_id: 'span-1',
          name: 'task_executor.execute_task',
          attributes: {
            'task.name' => 'fetch_user',
            'task.output.keys' => 'user,metadata',
            'task.output.user' => 'john_doe',
            'task.output.metadata' => 'active'
          },
          duration_ms: 100,
          timestamp: Time.now
        }
      ]

      result = adapter.extract_task_data(spans)

      expect(result.first[:outputs]).to eq({
                                             user: 'john_doe',
                                             metadata: 'active'
                                           })
    end

    it 'extracts tool calls from child spans' do
      now = Time.now
      spans = [
        {
          trace_id: 'trace-1',
          span_id: 'span-1',
          name: 'task_executor.execute_task',
          attributes: { 'task.name' => 'test' },
          duration_ms: 200,
          timestamp: now
        },
        {
          trace_id: 'trace-1',
          span_id: 'span-2',
          name: 'execute_tool database',
          attributes: {
            'gen_ai.operation.name' => 'execute_tool',
            'gen_ai.tool.name' => 'database',
            'gen_ai.tool.call.arguments.size' => 100,
            'gen_ai.tool.call.result.size' => 500
          },
          duration_ms: 50,
          timestamp: now + 1
        },
        {
          trace_id: 'trace-1',
          span_id: 'span-3',
          name: 'execute_tool cache',
          attributes: {
            'gen_ai.operation.name' => 'execute_tool',
            'gen_ai.tool.name' => 'cache',
            'gen_ai.tool.call.arguments.size' => 200,
            'gen_ai.tool.call.result.size' => 300
          },
          duration_ms: 30,
          timestamp: now + 2
        }
      ]

      result = adapter.extract_task_data(spans)

      tool_calls = result.first[:tool_calls]
      expect(tool_calls.size).to eq(2)
      expect(tool_calls.map { |tc| tc[:tool_name] }).to eq(%w[database cache])
    end
  end

  # Helper methods

  def empty_response
    {
      data: {
        result: []
      }
    }
  end

  def sample_response
    {
      data: {
        result: [
          {
            list: [
              {
                spanID: 'span-1',
                traceID: 'trace-1',
                name: 'task_executor.execute_task',
                timestamp: (Time.now.to_f * 1_000_000_000).to_i,
                durationNano: 100_000_000,
                stringTagMap: {
                  'task.name' => 'test_task'
                },
                numberTagMap: {}
              },
              {
                spanID: 'span-2',
                traceID: 'trace-2',
                name: 'task_executor.execute_task',
                timestamp: (Time.now.to_f * 1_000_000_000).to_i,
                durationNano: 200_000_000,
                stringTagMap: {
                  'task.name' => 'test_task'
                },
                numberTagMap: {}
              }
            ]
          }
        ]
      }
    }
  end
end
