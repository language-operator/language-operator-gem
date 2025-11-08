# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/metrics_tracker'

RSpec.describe LanguageOperator::Agent::MetricsTracker do
  let(:tracker) { described_class.new }

  describe '#initialize' do
    it 'initializes with zero metrics' do
      stats = tracker.cumulative_stats
      expect(stats[:totalTokens]).to eq(0)
      expect(stats[:requestCount]).to eq(0)
      expect(stats[:estimatedCost]).to eq(0.0)
    end
  end

  describe '#record_request' do
    context 'with complete token data' do
      let(:response) do
        double('RubyLLM::Message',
               input_tokens: 150,
               output_tokens: 50,
               cached_tokens: 10,
               cache_creation_tokens: 5)
      end

      before do
        allow(tracker).to receive(:get_pricing).and_return({ input: 0.5, output: 1.5 })
      end

      it 'records token counts' do
        tracker.record_request(response, 'test-model')
        stats = tracker.cumulative_stats

        expect(stats[:inputTokens]).to eq(150)
        expect(stats[:outputTokens]).to eq(50)
        expect(stats[:cachedTokens]).to eq(10)
        expect(stats[:cacheCreationTokens]).to eq(5)
        expect(stats[:totalTokens]).to eq(200)
      end

      it 'increments request count' do
        expect do
          tracker.record_request(response, 'test-model')
        end.to change { tracker.cumulative_stats[:requestCount] }.by(1)
      end

      it 'calculates cost correctly' do
        tracker.record_request(response, 'test-model')
        stats = tracker.cumulative_stats

        # (150 / 1_000_000) * 0.5 + (50 / 1_000_000) * 1.5
        # = 0.000075 + 0.000075 = 0.00015
        expect(stats[:estimatedCost]).to eq(0.00015)
      end

      it 'stores request history' do
        tracker.record_request(response, 'test-model')
        recent = tracker.recent_requests(1)

        expect(recent.length).to eq(1)
        expect(recent.first[:model]).to eq('test-model')
        expect(recent.first[:input_tokens]).to eq(150)
        expect(recent.first[:output_tokens]).to eq(50)
      end
    end

    context 'with nil token values' do
      let(:response) do
        double('RubyLLM::Message',
               input_tokens: nil,
               output_tokens: nil,
               cached_tokens: nil,
               cache_creation_tokens: nil)
      end

      it 'treats nil as zero' do
        tracker.record_request(response, 'test-model')
        stats = tracker.cumulative_stats

        expect(stats[:inputTokens]).to eq(0)
        expect(stats[:outputTokens]).to eq(0)
        expect(stats[:totalTokens]).to eq(0)
      end
    end

    context 'with missing token methods' do
      let(:response) do
        double('RubyLLM::Message')
      end

      it 'handles missing methods gracefully' do
        expect do
          tracker.record_request(response, 'test-model')
        end.not_to raise_error

        stats = tracker.cumulative_stats
        expect(stats[:totalTokens]).to eq(0)
      end
    end

    context 'with nil response' do
      it 'handles nil response gracefully' do
        expect do
          tracker.record_request(nil, 'test-model')
        end.not_to raise_error

        stats = tracker.cumulative_stats
        expect(stats[:requestCount]).to eq(0)
      end
    end

    context 'with multiple requests' do
      let(:response1) do
        double('RubyLLM::Message',
               input_tokens: 100,
               output_tokens: 50,
               cached_tokens: 0,
               cache_creation_tokens: 0)
      end

      let(:response2) do
        double('RubyLLM::Message',
               input_tokens: 200,
               output_tokens: 75,
               cached_tokens: 0,
               cache_creation_tokens: 0)
      end

      before do
        allow(tracker).to receive(:get_pricing).and_return({ input: 1.0, output: 2.0 })
      end

      it 'accumulates tokens across requests' do
        tracker.record_request(response1, 'test-model')
        tracker.record_request(response2, 'test-model')

        stats = tracker.cumulative_stats
        expect(stats[:inputTokens]).to eq(300)
        expect(stats[:outputTokens]).to eq(125)
        expect(stats[:totalTokens]).to eq(425)
        expect(stats[:requestCount]).to eq(2)
      end

      it 'accumulates costs across requests' do
        tracker.record_request(response1, 'test-model')
        tracker.record_request(response2, 'test-model')

        stats = tracker.cumulative_stats
        # Request 1: (100/1M)*1.0 + (50/1M)*2.0 = 0.0001 + 0.0001 = 0.0002
        # Request 2: (200/1M)*1.0 + (75/1M)*2.0 = 0.0002 + 0.00015 = 0.00035
        # Total: 0.00055
        expect(stats[:estimatedCost]).to eq(0.00055)
      end
    end
  end

  describe '#cumulative_stats' do
    it 'returns hash with required keys' do
      stats = tracker.cumulative_stats

      expect(stats).to have_key(:totalTokens)
      expect(stats).to have_key(:inputTokens)
      expect(stats).to have_key(:outputTokens)
      expect(stats).to have_key(:cachedTokens)
      expect(stats).to have_key(:cacheCreationTokens)
      expect(stats).to have_key(:requestCount)
      expect(stats).to have_key(:estimatedCost)
    end

    it 'rounds cost to 6 decimal places' do
      response = double('RubyLLM::Message',
                        input_tokens: 1,
                        output_tokens: 1,
                        cached_tokens: 0,
                        cache_creation_tokens: 0)

      allow(tracker).to receive(:get_pricing).and_return({ input: 0.333333333, output: 0.666666666 })
      tracker.record_request(response, 'test-model')

      stats = tracker.cumulative_stats
      # Should round to 6 decimal places
      expect(stats[:estimatedCost].to_s.split('.').last.length).to be <= 6
    end
  end

  describe '#recent_requests' do
    it 'returns limited number of requests' do
      response = double('RubyLLM::Message',
                        input_tokens: 100,
                        output_tokens: 50,
                        cached_tokens: 0,
                        cache_creation_tokens: 0)

      allow(tracker).to receive(:get_pricing).and_return({ input: 1.0, output: 2.0 })

      5.times { tracker.record_request(response, 'test-model') }
      recent = tracker.recent_requests(3)

      expect(recent.length).to eq(3)
    end

    it 'stores max 100 requests' do
      response = double('RubyLLM::Message',
                        input_tokens: 100,
                        output_tokens: 50,
                        cached_tokens: 0,
                        cache_creation_tokens: 0)

      allow(tracker).to receive(:get_pricing).and_return({ input: 1.0, output: 2.0 })

      150.times { tracker.record_request(response, 'test-model') }
      all_requests = tracker.instance_variable_get(:@metrics)[:requests]

      expect(all_requests.length).to eq(100)
    end
  end

  describe '#reset!' do
    it 'clears all metrics' do
      response = double('RubyLLM::Message',
                        input_tokens: 100,
                        output_tokens: 50,
                        cached_tokens: 0,
                        cache_creation_tokens: 0)

      allow(tracker).to receive(:get_pricing).and_return({ input: 1.0, output: 2.0 })
      tracker.record_request(response, 'test-model')

      tracker.reset!
      stats = tracker.cumulative_stats

      expect(stats[:totalTokens]).to eq(0)
      expect(stats[:requestCount]).to eq(0)
      expect(stats[:estimatedCost]).to eq(0.0)
    end

    it 'clears request history' do
      response = double('RubyLLM::Message',
                        input_tokens: 100,
                        output_tokens: 50,
                        cached_tokens: 0,
                        cache_creation_tokens: 0)

      allow(tracker).to receive(:get_pricing).and_return({ input: 1.0, output: 2.0 })
      tracker.record_request(response, 'test-model')

      tracker.reset!
      recent = tracker.recent_requests(10)

      expect(recent).to be_empty
    end
  end

  describe 'thread safety' do
    it 'handles concurrent requests safely' do
      response = double('RubyLLM::Message',
                        input_tokens: 100,
                        output_tokens: 50,
                        cached_tokens: 0,
                        cache_creation_tokens: 0)

      allow(tracker).to receive(:get_pricing).and_return({ input: 1.0, output: 2.0 })

      threads = 10.times.map do
        Thread.new { tracker.record_request(response, 'test-model') }
      end
      threads.each(&:join)

      stats = tracker.cumulative_stats
      expect(stats[:requestCount]).to eq(10)
      expect(stats[:inputTokens]).to eq(1000)
      expect(stats[:outputTokens]).to eq(500)
    end
  end

  describe 'pricing fallback' do
    context 'when pricing lookup fails' do
      let(:response) do
        double('RubyLLM::Message',
               input_tokens: 100,
               output_tokens: 50,
               cached_tokens: 0,
               cache_creation_tokens: 0)
      end

      before do
        allow(tracker).to receive(:get_pricing).and_return(nil)
      end

      it 'records zero cost' do
        tracker.record_request(response, 'unknown-model')
        stats = tracker.cumulative_stats

        expect(stats[:estimatedCost]).to eq(0.0)
      end

      it 'still records token counts' do
        tracker.record_request(response, 'unknown-model')
        stats = tracker.cumulative_stats

        expect(stats[:inputTokens]).to eq(100)
        expect(stats[:outputTokens]).to eq(50)
      end
    end
  end
end
