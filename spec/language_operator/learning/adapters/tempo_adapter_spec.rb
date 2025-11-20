# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/learning/adapters/tempo_adapter'
require 'webmock/rspec'

RSpec.describe LanguageOperator::Learning::Adapters::TempoAdapter do
  let(:endpoint) { 'http://tempo:3200' }
  let(:adapter) { described_class.new(endpoint) }

  describe '.available?' do
    it 'returns true when Tempo API is reachable' do
      stub_request(:get, %r{#{endpoint}/api/search})
        .to_return(status: 200, body: '{"traces":[]}')

      expect(described_class.available?(endpoint)).to be true
    end

    it 'returns false when endpoint is unreachable' do
      stub_request(:get, %r{#{endpoint}/api/search})
        .to_timeout

      expect(described_class.available?(endpoint)).to be false
    end
  end

  describe '#query_spans' do
    it 'queries Tempo search endpoint with TraceQL' do
      stub = stub_request(:get, %r{#{endpoint}/api/search})
             .to_return(status: 200, body: JSON.generate({ traces: [] }))

      adapter.query_spans(
        filter: { task_name: 'test_task' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(stub).to have_been_requested
    end

    it 'builds TraceQL query from filter' do
      stub = stub_request(:get, %r{#{endpoint}/api/search})
             .with(query: hash_including(q: /span\."task\.name" = "fetch_user"/))
             .to_return(status: 200, body: JSON.generate({ traces: [] }))

      adapter.query_spans(
        filter: { task_name: 'fetch_user' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(stub).to have_been_requested
    end

    it 'parses Tempo response with spanSets' do
      stub_request(:get, %r{#{endpoint}/api/search})
        .to_return(status: 200, body: JSON.generate(sample_tempo_response))

      result = adapter.query_spans(
        filter: { task_name: 'test' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first).to include(:span_id, :trace_id, :name)
    end

    it 'escapes special characters in TraceQL values' do
      stub = stub_request(:get, %r{#{endpoint}/api/search})
             .with(query: hash_including(q: /span\."task\.name" = "test\\"quote"/))
             .to_return(status: 200, body: JSON.generate({ traces: [] }))

      adapter.query_spans(
        filter: { task_name: 'test"quote' },
        time_range: (Time.now - 3600)..Time.now,
        limit: 100
      )

      expect(stub).to have_been_requested
    end
  end

  def sample_tempo_response
    {
      traces: [
        {
          traceID: 'trace-1',
          spanSets: [
            {
              spans: [
                {
                  spanID: 'span-1',
                  name: 'task_executor.execute_task',
                  startTimeUnixNano: (Time.now.to_f * 1_000_000_000).to_s,
                  durationNanos: 100_000_000,
                  attributes: [
                    { key: 'task.name', value: { stringValue: 'test_task' } }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  end
end
