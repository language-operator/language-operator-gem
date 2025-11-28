# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/telemetry'

RSpec.describe LanguageOperator::Agent::Telemetry do
  after do
    # Clean up environment variables
    ENV.delete('OTEL_EXPORTER_OTLP_ENDPOINT')
    ENV.delete('AGENT_NAME')
    ENV.delete('AGENT_MODE')
    ENV.delete('AGENT_CLUSTER')
    ENV.delete('AGENT_NAMESPACE')
    ENV.delete('HOSTNAME')
    ENV.delete('TRACEPARENT')
  end

  describe '.configure' do
    it 'skips configuration when OTEL endpoint not provided' do
      expect { described_class.configure }.not_to raise_error
    end

    it 'warns when AGENT_NAME not set during resource attributes building' do
      expect do
        described_class.send(:build_resource_attributes)
      end.to output(/AGENT_NAME environment variable not set/).to_stderr
    end
  end

  describe '.build_resource_attributes' do
    it 'builds semantic attributes for learning system' do
      ENV['AGENT_NAME'] = 'test-agent'
      ENV['AGENT_MODE'] = 'autonomous'
      ENV['AGENT_CLUSTER'] = 'test-cluster'
      ENV['AGENT_NAMESPACE'] = 'production'
      ENV['HOSTNAME'] = 'agent-pod-123'

      # Call private method for testing
      attributes = described_class.send(:build_resource_attributes)

      # Agent identification (CRITICAL for learning system)
      expect(attributes['agent.name']).to eq('test-agent')
      expect(attributes['agent.mode']).to eq('autonomous')
      expect(attributes['agent.cluster']).to eq('test-cluster')
      expect(attributes['service.name']).to eq('language-operator-agent-test-agent')

      # Kubernetes context
      expect(attributes['service.namespace']).to eq('production')
      expect(attributes['k8s.namespace.name']).to eq('production')
      expect(attributes['k8s.pod.name']).to eq('agent-pod-123')

      # Service metadata
      expect(attributes['service.version']).to eq(LanguageOperator::VERSION) if defined?(LanguageOperator::VERSION)
    end

    it 'handles missing environment variables gracefully' do
      attributes = described_class.send(:build_resource_attributes)

      expect(attributes['agent.name']).to be_nil
      expect(attributes['agent.mode']).to be_nil
      expect(attributes['agent.cluster']).to be_nil
      expect(attributes['service.namespace']).to be_nil
      expect(attributes['k8s.pod.name']).to be_nil
    end

    it 'sets agent-specific service name when AGENT_NAME provided' do
      ENV['AGENT_NAME'] = 'my-agent'

      attributes = described_class.send(:build_resource_attributes)

      expect(attributes['service.name']).to eq('language-operator-agent-my-agent')
    end

    it 'does not set agent-specific service name when AGENT_NAME missing' do
      attributes = described_class.send(:build_resource_attributes)

      expect(attributes['service.name']).to be_nil
    end
  end

  describe '.restore_trace_context' do
    it 'handles missing TRACEPARENT gracefully' do
      expect { described_class.send(:restore_trace_context) }.not_to raise_error
    end

    it 'handles invalid TRACEPARENT format gracefully' do
      ENV['TRACEPARENT'] = 'invalid-format'
      expect { described_class.send(:restore_trace_context) }.not_to raise_error
    end

    it 'handles malformed TRACEPARENT gracefully' do
      ENV['TRACEPARENT'] = '00-invalid-trace-format'
      expect { described_class.send(:restore_trace_context) }.not_to raise_error
    end
  end
end
