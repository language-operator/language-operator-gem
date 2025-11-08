# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Retry do
  describe '.with_backoff' do
    it 'executes block successfully without retries' do
      counter = 0
      result = described_class.with_backoff do
        counter += 1
        'success'
      end

      expect(result).to eq('success')
      expect(counter).to eq(1)
    end

    it 'retries on failure and eventually succeeds' do
      counter = 0
      result = described_class.with_backoff(max_retries: 3) do
        counter += 1
        raise StandardError, 'transient error' if counter < 3

        'success'
      end

      expect(result).to eq('success')
      expect(counter).to eq(3)
    end

    it 're-raises exception after max retries exhausted' do
      counter = 0
      expect do
        described_class.with_backoff(max_retries: 2) do
          counter += 1
          raise StandardError, 'persistent error'
        end
      end.to raise_error(StandardError, 'persistent error')

      expect(counter).to eq(3) # Initial attempt + 2 retries
    end

    it 'respects max_retries parameter' do
      counter = 0
      expect do
        described_class.with_backoff(max_retries: 5) do
          counter += 1
          raise StandardError, 'error'
        end
      end.to raise_error(StandardError)

      expect(counter).to eq(6) # Initial attempt + 5 retries
    end

    it 'calls on_retry callback with attempt number and exception' do
      callback_calls = []
      counter = 0

      expect do
        described_class.with_backoff(max_retries: 2, on_retry: lambda { |attempt, e|
          callback_calls << { attempt: attempt, message: e.message }
        }) do
          counter += 1
          raise StandardError, "error #{counter}"
        end
      end.to raise_error(StandardError)

      expect(callback_calls.length).to eq(2)
      expect(callback_calls[0][:attempt]).to eq(1)
      expect(callback_calls[0][:message]).to eq('error 1')
      expect(callback_calls[1][:attempt]).to eq(2)
      expect(callback_calls[1][:message]).to eq('error 2')
    end

    it 'sleeps with exponential backoff between retries' do
      counter = 0
      allow(described_class).to receive(:sleep)

      expect do
        described_class.with_backoff(max_retries: 3, base_delay: 1.0) do
          counter += 1
          raise StandardError, 'error'
        end
      end.to raise_error(StandardError)

      # Should have called sleep 3 times (once per retry)
      expect(described_class).to have_received(:sleep).exactly(3).times
    end
  end

  describe '.on_exceptions' do
    it 'retries on specified exception types' do
      counter = 0
      result = described_class.on_exceptions([ArgumentError, RuntimeError], max_retries: 2) do
        counter += 1
        raise ArgumentError, 'retry me' if counter < 2

        'success'
      end

      expect(result).to eq('success')
      expect(counter).to eq(2)
    end

    it 'does not retry on unspecified exception types' do
      counter = 0
      expect do
        described_class.on_exceptions([ArgumentError], max_retries: 3) do
          counter += 1
          raise 'do not retry'
        end
      end.to raise_error(RuntimeError, 'do not retry')

      expect(counter).to eq(1) # No retries
    end

    it 're-raises after max retries for specified exceptions' do
      counter = 0
      expect do
        described_class.on_exceptions([StandardError], max_retries: 2) do
          counter += 1
          raise StandardError, 'persistent'
        end
      end.to raise_error(StandardError, 'persistent')

      expect(counter).to eq(3)
    end
  end

  describe '.retryable_http_code?' do
    it 'returns true for retryable HTTP codes' do
      expect(described_class.retryable_http_code?(429)).to be true
      expect(described_class.retryable_http_code?(500)).to be true
      expect(described_class.retryable_http_code?(502)).to be true
      expect(described_class.retryable_http_code?(503)).to be true
      expect(described_class.retryable_http_code?(504)).to be true
    end

    it 'returns false for non-retryable HTTP codes' do
      expect(described_class.retryable_http_code?(200)).to be false
      expect(described_class.retryable_http_code?(400)).to be false
      expect(described_class.retryable_http_code?(404)).to be false
      expect(described_class.retryable_http_code?(422)).to be false
    end
  end

  describe '.calculate_backoff' do
    it 'calculates exponential backoff for attempt 1' do
      delay = described_class.calculate_backoff(1, 1.0, 10.0, 0.0)
      expect(delay).to eq(1.0)
    end

    it 'calculates exponential backoff for attempt 2' do
      delay = described_class.calculate_backoff(2, 1.0, 10.0, 0.0)
      expect(delay).to eq(2.0)
    end

    it 'calculates exponential backoff for attempt 3' do
      delay = described_class.calculate_backoff(3, 1.0, 10.0, 0.0)
      expect(delay).to eq(4.0)
    end

    it 'calculates exponential backoff for attempt 4' do
      delay = described_class.calculate_backoff(4, 1.0, 10.0, 0.0)
      expect(delay).to eq(8.0)
    end

    it 'caps delay at max_delay' do
      delay = described_class.calculate_backoff(10, 1.0, 10.0, 0.0)
      expect(delay).to eq(10.0) # Would be 512.0 without cap
    end

    it 'adds jitter to the delay' do
      # With jitter, delay should vary around the base value
      delays = 10.times.map { described_class.calculate_backoff(1, 1.0, 10.0, 0.1) }

      # All delays should be close to 1.0 but with some variation
      delays.each do |delay|
        expect(delay).to be_between(0.8, 1.2)
      end

      # Should have some variation (not all the same)
      expect(delays.uniq.length).to be > 1
    end

    it 'uses default parameters when not specified' do
      delay = described_class.calculate_backoff(1)
      expect(delay).to be_between(0.8, 1.2) # ~1.0 with jitter
    end

    it 'respects custom base_delay' do
      delay = described_class.calculate_backoff(1, 2.0, 10.0, 0.0)
      expect(delay).to eq(2.0)
    end
  end

  describe 'constants' do
    it 'defines DEFAULT_MAX_RETRIES' do
      expect(described_class::DEFAULT_MAX_RETRIES).to eq(3)
    end

    it 'defines DEFAULT_BASE_DELAY' do
      expect(described_class::DEFAULT_BASE_DELAY).to eq(1.0)
    end

    it 'defines DEFAULT_MAX_DELAY' do
      expect(described_class::DEFAULT_MAX_DELAY).to eq(10.0)
    end

    it 'defines DEFAULT_JITTER_FACTOR' do
      expect(described_class::DEFAULT_JITTER_FACTOR).to eq(0.1)
    end

    it 'defines RETRYABLE_HTTP_CODES' do
      expect(described_class::RETRYABLE_HTTP_CODES).to eq([429, 500, 502, 503, 504])
    end
  end
end
