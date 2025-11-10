# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/telemetry'

RSpec.describe LanguageOperator::Agent::Telemetry do
  describe '.configure' do
    let(:endpoint) { 'http://otel-collector:4318' }

    before do
      # Reset OpenTelemetry between tests
      config_double = double('Config')
      allow(config_double).to receive(:service_name=)
      allow(config_double).to receive(:service_version=)
      allow(config_double).to receive(:resource=)
      allow(config_double).to receive(:add_span_processor)
      allow(OpenTelemetry::SDK).to receive(:configure).and_yield(config_double)
    end

    after do
      # Clean up environment
      ENV.delete('OTEL_EXPORTER_OTLP_ENDPOINT')
      ENV.delete('TRACEPARENT')
      ENV.delete('AGENT_NAMESPACE')
      ENV.delete('AGENT_NAME')
      ENV.delete('AGENT_MODE')
      ENV.delete('HOSTNAME')
    end

    context 'when OTEL_EXPORTER_OTLP_ENDPOINT is not set' do
      it 'returns early without configuring OpenTelemetry' do
        expect(OpenTelemetry::SDK).not_to receive(:configure)
        described_class.configure
      end
    end

    context 'when OTEL_EXPORTER_OTLP_ENDPOINT is set' do
      before do
        ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = endpoint
      end

      it 'configures OpenTelemetry SDK' do
        expect(OpenTelemetry::SDK).to receive(:configure)
        described_class.configure
      end

      it 'sets service name to language-operator-agent' do
        config = double
        allow(OpenTelemetry::SDK).to receive(:configure).and_yield(config)
        expect(config).to receive(:service_name=).with('language-operator-agent')
        allow(config).to receive(:service_version=)
        allow(config).to receive(:resource=)
        allow(config).to receive(:add_span_processor)
        described_class.configure
      end

      it 'sets service version from LanguageOperator::VERSION' do
        config = double
        allow(OpenTelemetry::SDK).to receive(:configure).and_yield(config)
        allow(config).to receive(:service_name=)
        expect(config).to receive(:service_version=).with(LanguageOperator::VERSION)
        allow(config).to receive(:resource=)
        allow(config).to receive(:add_span_processor)
        described_class.configure
      end

      context 'with resource attributes' do
        before do
          ENV['AGENT_NAMESPACE'] = 'test-namespace'
          ENV['AGENT_NAME'] = 'test-agent'
          ENV['AGENT_MODE'] = 'autonomous'
          ENV['HOSTNAME'] = 'test-pod-123'
        end

        it 'configures resource with environment attributes' do
          config = double
          allow(OpenTelemetry::SDK).to receive(:configure).and_yield(config)
          allow(config).to receive(:service_name=)
          allow(config).to receive(:service_version=)
          allow(config).to receive(:add_span_processor)

          resource_double = double
          expect(OpenTelemetry::SDK::Resources::Resource).to receive(:create).with(
            hash_including(
              'service.namespace' => 'test-namespace',
              'k8s.namespace.name' => 'test-namespace',
              'k8s.pod.name' => 'test-pod-123',
              'agent.name' => 'test-agent',
              'agent.mode' => 'autonomous'
            )
          ).and_return(resource_double)

          expect(config).to receive(:resource=).with(resource_double)
          described_class.configure
        end
      end

      context 'with partial resource attributes' do
        before do
          ENV['AGENT_NAME'] = 'test-agent'
        end

        it 'configures resource with only available attributes' do
          config = double
          allow(OpenTelemetry::SDK).to receive(:configure).and_yield(config)
          allow(config).to receive(:service_name=)
          allow(config).to receive(:service_version=)
          allow(config).to receive(:add_span_processor)

          resource_double = double
          expect(OpenTelemetry::SDK::Resources::Resource).to receive(:create).with(
            hash_including('agent.name' => 'test-agent')
          ).and_return(resource_double)

          expect(config).to receive(:resource=).with(resource_double)
          described_class.configure
        end
      end

      it 'configures OTLP exporter with endpoint' do
        config = double
        allow(OpenTelemetry::SDK).to receive(:configure).and_yield(config)
        allow(config).to receive(:service_name=)
        allow(config).to receive(:service_version=)
        allow(config).to receive(:resource=)

        exporter_double = double
        processor_double = double

        expect(OpenTelemetry::Exporter::OTLP::Exporter).to receive(:new).with(
          endpoint: endpoint
        ).and_return(exporter_double)

        expect(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor).to receive(:new).with(
          exporter_double
        ).and_return(processor_double)

        expect(config).to receive(:add_span_processor).with(processor_double)

        described_class.configure
      end
    end

    context 'with TRACEPARENT for distributed tracing' do
      let(:trace_id) { '4bf92f3577b34da6a3ce929d0e0e4736' }
      let(:parent_id) { '00f067aa0ba902b7' }
      let(:traceparent) { "00-#{trace_id}-#{parent_id}-01" }

      before do
        ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = endpoint
        ENV['TRACEPARENT'] = traceparent
      end

      it 'restores trace context from TRACEPARENT' do
        # Mock the span context creation
        span_context_double = double('SpanContext')
        span_double = double('Span')

        expect(OpenTelemetry::Trace::SpanContext).to receive(:new).with(
          hash_including(
            trace_id: [trace_id].pack('H*'),
            span_id: [parent_id].pack('H*'),
            remote: true
          )
        ).and_return(span_context_double)

        expect(OpenTelemetry::Trace).to receive(:non_recording_span).with(
          span_context_double
        ).and_return(span_double)

        expect(OpenTelemetry::Trace).to receive(:context_with_span).with(span_double)

        described_class.configure
      end
    end

    context 'with malformed TRACEPARENT' do
      before do
        ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = endpoint
        ENV['TRACEPARENT'] = 'invalid'
      end

      it 'handles error gracefully and continues' do
        expect { described_class.configure }.not_to raise_error
      end

      it 'returns early without logging for malformed format' do
        # Malformed TRACEPARENT (not 4 parts) returns early without error
        expect(described_class).not_to receive(:warn)
        described_class.configure
      end
    end

    context 'with invalid TRACEPARENT data' do
      before do
        ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = endpoint
        # Valid format but will cause error in OpenTelemetry API
        ENV['TRACEPARENT'] = '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'

        # Mock SpanContext creation to raise error
        allow(OpenTelemetry::Trace::SpanContext).to receive(:new).and_raise(
          StandardError.new('Invalid trace data')
        )
      end

      it 'handles error gracefully and continues' do
        expect { described_class.configure }.not_to raise_error
      end

      it 'logs warning about failed trace context restoration' do
        expect(described_class).to receive(:warn).with(/Failed to restore trace context/)
        described_class.configure
      end
    end

    context 'when OpenTelemetry configuration raises error' do
      before do
        ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = endpoint
        allow(OpenTelemetry::SDK).to receive(:configure).and_raise(StandardError.new('Test error'))
      end

      it 'handles error gracefully' do
        expect { described_class.configure }.not_to raise_error
      end

      it 'logs warning with error message' do
        expect(described_class).to receive(:warn).with(/Failed to configure OpenTelemetry: Test error/)
        expect(described_class).to receive(:warn).with(kind_of(String)) # backtrace
        described_class.configure
      end
    end
  end
end
