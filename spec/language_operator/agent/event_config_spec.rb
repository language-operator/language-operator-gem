# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/event_config'

RSpec.describe LanguageOperator::Agent::EventConfig do
  after do
    # Clean up environment variables
    [
      'KUBERNETES_SERVICE_HOST', 'ENABLE_K8S_EVENTS', 'DISABLE_K8S_EVENTS',
      'EMIT_SUCCESS_EVENTS', 'EMIT_FAILURE_EVENTS', 'EMIT_VALIDATION_EVENTS',
      'EVENT_RATE_LIMIT_PER_MINUTE', 'INCLUDE_TASK_METADATA', 'INCLUDE_ERROR_DETAILS',
      'TRUNCATE_LONG_MESSAGES', 'MAX_EVENT_MESSAGE_LENGTH'
    ].each { |var| ENV.delete(var) }
  end

  describe '.load' do
    it 'returns default configuration when no env vars are set' do
      config = described_class.load
      
      expect(config[:enabled]).to be true
      expect(config[:disabled]).to be false
      expect(config[:emit_success_events]).to be true
      expect(config[:emit_failure_events]).to be true
      expect(config[:emit_validation_events]).to be true
      expect(config[:rate_limit_per_minute]).to eq(60)
      expect(config[:include_task_metadata]).to be true
      expect(config[:max_message_length]).to eq(1000)
    end

    it 'respects environment variable overrides' do
      ENV['DISABLE_K8S_EVENTS'] = 'true'
      ENV['EMIT_SUCCESS_EVENTS'] = 'false'
      ENV['EVENT_RATE_LIMIT_PER_MINUTE'] = '30'
      ENV['MAX_EVENT_MESSAGE_LENGTH'] = '500'

      config = described_class.load

      expect(config[:disabled]).to be true
      expect(config[:emit_success_events]).to be false
      expect(config[:rate_limit_per_minute]).to eq(30)
      expect(config[:max_message_length]).to eq(500)
    end

    it 'properly converts string values to correct types' do
      ENV['ENABLE_K8S_EVENTS'] = 'false'
      ENV['EVENT_RATE_LIMIT_PER_MINUTE'] = '120'
      ENV['INCLUDE_TASK_METADATA'] = 'false'

      config = described_class.load

      expect(config[:enabled]).to be false
      expect(config[:rate_limit_per_minute]).to be_a(Integer)
      expect(config[:rate_limit_per_minute]).to eq(120)
      expect(config[:include_task_metadata]).to be false
    end
  end

  describe '.enabled?' do
    context 'when not in Kubernetes environment' do
      before { ENV.delete('KUBERNETES_SERVICE_HOST') }

      it 'returns false regardless of other settings' do
        ENV['ENABLE_K8S_EVENTS'] = 'true'
        expect(described_class.enabled?).to be false
      end
    end

    context 'when in Kubernetes environment' do
      before { ENV['KUBERNETES_SERVICE_HOST'] = 'kubernetes.default.svc' }

      it 'returns true by default' do
        expect(described_class.enabled?).to be true
      end

      it 'returns false when explicitly disabled via DISABLE_K8S_EVENTS' do
        ENV['DISABLE_K8S_EVENTS'] = 'true'
        expect(described_class.enabled?).to be false
      end

      it 'returns false when explicitly disabled via ENABLE_K8S_EVENTS' do
        ENV['ENABLE_K8S_EVENTS'] = 'false'
        expect(described_class.enabled?).to be false
      end

      it 'respects DISABLE_K8S_EVENTS over ENABLE_K8S_EVENTS' do
        ENV['DISABLE_K8S_EVENTS'] = 'true'
        ENV['ENABLE_K8S_EVENTS'] = 'true'
        expect(described_class.enabled?).to be false
      end
    end
  end

  describe '.should_emit?' do
    before { ENV['KUBERNETES_SERVICE_HOST'] = 'kubernetes.default.svc' }

    context 'when events are disabled globally' do
      before { ENV['DISABLE_K8S_EVENTS'] = 'true' }

      it 'returns false for all event types' do
        expect(described_class.should_emit?(:success)).to be false
        expect(described_class.should_emit?(:failure)).to be false
        expect(described_class.should_emit?(:validation)).to be false
      end
    end

    context 'when events are enabled globally' do
      it 'returns true for enabled event types by default' do
        expect(described_class.should_emit?(:success)).to be true
        expect(described_class.should_emit?(:failure)).to be true
        expect(described_class.should_emit?(:validation)).to be true
      end

      it 'respects individual event type configuration' do
        ENV['EMIT_SUCCESS_EVENTS'] = 'false'
        ENV['EMIT_FAILURE_EVENTS'] = 'true'
        ENV['EMIT_VALIDATION_EVENTS'] = 'false'

        expect(described_class.should_emit?(:success)).to be false
        expect(described_class.should_emit?(:failure)).to be true
        expect(described_class.should_emit?(:validation)).to be false
      end

      it 'returns false for unknown event types' do
        expect(described_class.should_emit?(:unknown)).to be false
      end
    end
  end

  describe '.rate_limit_config' do
    it 'returns default rate limiting configuration' do
      config = described_class.rate_limit_config

      expect(config[:per_minute]).to eq(60)
      expect(config[:batch_size]).to eq(1)
      expect(config[:batch_timeout_ms]).to eq(1000)
    end

    it 'respects environment variable overrides' do
      ENV['EVENT_RATE_LIMIT_PER_MINUTE'] = '120'
      ENV['EVENT_BATCH_SIZE'] = '5'
      ENV['EVENT_BATCH_TIMEOUT_MS'] = '2000'

      config = described_class.rate_limit_config

      expect(config[:per_minute]).to eq(120)
      expect(config[:batch_size]).to eq(5)
      expect(config[:batch_timeout_ms]).to eq(2000)
    end
  end

  describe '.retry_config' do
    it 'returns default retry configuration' do
      config = described_class.retry_config

      expect(config[:enabled]).to be true
      expect(config[:max_retries]).to eq(3)
      expect(config[:delay_ms]).to eq(1000)
    end

    it 'respects environment variable overrides' do
      ENV['RETRY_FAILED_EVENTS'] = 'false'
      ENV['MAX_EVENT_RETRIES'] = '5'
      ENV['EVENT_RETRY_DELAY_MS'] = '2500'

      config = described_class.retry_config

      expect(config[:enabled]).to be false
      expect(config[:max_retries]).to eq(5)
      expect(config[:delay_ms]).to eq(2500)
    end
  end

  describe '.content_config' do
    it 'returns default content configuration' do
      config = described_class.content_config

      expect(config[:include_task_metadata]).to be true
      expect(config[:include_error_details]).to be true
      expect(config[:truncate_long_messages]).to be true
      expect(config[:max_message_length]).to eq(1000)
    end

    it 'respects environment variable overrides' do
      ENV['INCLUDE_TASK_METADATA'] = 'false'
      ENV['INCLUDE_ERROR_DETAILS'] = 'false'
      ENV['TRUNCATE_LONG_MESSAGES'] = 'false'
      ENV['MAX_EVENT_MESSAGE_LENGTH'] = '2000'

      config = described_class.content_config

      expect(config[:include_task_metadata]).to be false
      expect(config[:include_error_details]).to be false
      expect(config[:truncate_long_messages]).to be false
      expect(config[:max_message_length]).to eq(2000)
    end
  end
end