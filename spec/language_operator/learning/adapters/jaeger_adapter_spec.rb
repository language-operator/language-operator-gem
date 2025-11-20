# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/learning/adapters/jaeger_adapter'
require 'webmock/rspec'

RSpec.describe LanguageOperator::Learning::Adapters::JaegerAdapter do
  let(:endpoint) { 'http://jaeger:16686' }
  let(:adapter) { described_class.new(endpoint) }

  describe '.available?' do
    it 'returns true when Jaeger API is reachable' do
      stub_request(:get, "#{endpoint}/api/traces?service=test&limit=1")
        .to_return(status: 200, body: '{"data":[]}')

      expect(described_class.available?(endpoint)).to be true
    end

    it 'returns false when endpoint is unreachable' do
      stub_request(:get, %r{#{endpoint}/api/traces})
        .to_timeout

      expect(described_class.available?(endpoint)).to be false
    end
  end

  describe '#query_spans' do
    it 'queries Jaeger search endpoint' do
      stub = stub_request(:get, %r{#{endpoint}/api/traces})
             .to_return(status: 200, body: JSON.generate({ data: [] }))

      adapter.query_spans(
        filter: { task_name: 'test_task' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(stub).to have_been_requested
    end

    it 'includes task name in tags filter' do
      stub = stub_request(:get, %r{#{endpoint}/api/traces})
             .with(query: hash_including(tags: /"task\.name":"fetch_user"/))
             .to_return(status: 200, body: JSON.generate({ data: [] }))

      adapter.query_spans(
        filter: { task_name: 'fetch_user' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(stub).to have_been_requested
    end

    it 'parses Jaeger trace response' do
      stub_request(:get, %r{#{endpoint}/api/traces})
        .to_return(status: 200, body: JSON.generate(sample_jaeger_response))

      result = adapter.query_spans(
        filter: { task_name: 'test' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first).to include(:span_id, :trace_id, :name)
    end
  end

  def sample_jaeger_response
    {
      data: [
        {
          traceID: 'trace-1',
          processes: {
            p1: { serviceName: 'agent' }
          },
          spans: [
            {
              spanID: 'span-1',
              operationName: 'task_executor.execute_task',
              processID: 'p1',
              startTime: (Time.now.to_f * 1_000_000).to_i,
              duration: 100_000,
              tags: [
                { key: 'task.name', value: { stringValue: 'test_task' } }
              ]
            }
          ]
        }
      ]
    }
  end
end
