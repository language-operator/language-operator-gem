# frozen_string_literal: true

require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

module LanguageOperator
  module Agent
    # OpenTelemetry configuration for agent runtime
    #
    # Initializes distributed tracing and telemetry for language operator agents.
    # Reads configuration from environment variables and gracefully handles errors.
    #
    # @example Configure telemetry
    #   LanguageOperator::Agent::Telemetry.configure
    module Telemetry
      class << self
        # Configure OpenTelemetry for the agent
        #
        # Reads configuration from environment variables:
        # - OTEL_EXPORTER_OTLP_ENDPOINT: OTLP endpoint URL (required)
        # - TRACEPARENT: W3C trace context for distributed tracing
        # - AGENT_NAMESPACE: Kubernetes namespace
        # - AGENT_NAME: Agent name
        # - AGENT_MODE: Agent operating mode
        # - HOSTNAME: Pod hostname
        #
        # @return [void]
        def configure
          return unless ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', nil)

          # Configure custom error handler for detailed logging
          OpenTelemetry.error_handler = lambda do |exception: nil, message: nil|
            if exception
              warn "OpenTelemetry error: #{message} - #{exception.class}: #{exception.message}"
              warn exception.backtrace.first(5).join("\n") if exception.backtrace
            else
              warn "OpenTelemetry error: #{message}"
            end
          end

          # Initialize OpenTelemetry SDK with OTLP exporter
          # Uses environment variables set by the operator:
          # - OTEL_EXPORTER_OTLP_ENDPOINT: http://host:port
          # - OTEL_SERVICE_NAME: service name
          OpenTelemetry::SDK.configure do |c|
            c.service_name = ENV.fetch('OTEL_SERVICE_NAME', 'language-operator-agent')

            # Add resource attributes
            c.resource = OpenTelemetry::SDK::Resources::Resource.create(build_resource_attributes)

            # Use OTLP HTTP exporter (reads endpoint from OTEL_EXPORTER_OTLP_ENDPOINT env var)
            c.add_span_processor(
              OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
                OpenTelemetry::Exporter::OTLP::Exporter.new(
                  endpoint: "#{ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT')}/v1/traces",
                  headers: {}
                )
              )
            )
          end

          # Restore trace context from TRACEPARENT if present for distributed tracing
          restore_trace_context if ENV['TRACEPARENT']
        rescue StandardError => e
          warn "Failed to configure OpenTelemetry: #{e.message}"
          warn e.backtrace.join("\n")
        end

        private

        # Build resource attributes from environment variables
        #
        # @return [Hash] Resource attributes
        def build_resource_attributes
          attributes = {}

          # Service namespace
          if (namespace = ENV.fetch('AGENT_NAMESPACE', nil))
            attributes['service.namespace'] = namespace
            attributes['k8s.namespace.name'] = namespace
          end

          # Kubernetes pod name
          attributes['k8s.pod.name'] = ENV['HOSTNAME'] if ENV['HOSTNAME']

          # Agent-specific attributes
          attributes['agent.name'] = ENV['AGENT_NAME'] if ENV['AGENT_NAME']
          attributes['agent.mode'] = ENV['AGENT_MODE'] if ENV['AGENT_MODE']

          attributes
        end

        # Restore trace context from TRACEPARENT environment variable
        #
        # Extracts W3C trace context and sets it as the current context,
        # enabling distributed tracing across service boundaries.
        #
        # @return [void]
        def restore_trace_context
          traceparent = ENV.fetch('TRACEPARENT', nil)
          return unless traceparent

          # Parse TRACEPARENT (format: version-trace_id-parent_id-flags)
          parts = traceparent.split('-')
          return unless parts.length == 4

          _version, trace_id, parent_id, _flags = parts

          # Create span context from extracted values
          span_context = OpenTelemetry::Trace::SpanContext.new(
            trace_id: [trace_id].pack('H*'),
            span_id: [parent_id].pack('H*'),
            trace_flags: OpenTelemetry::Trace::TraceFlags::SAMPLED,
            remote: true
          )

          # Set as current context using proper OpenTelemetry API
          span = OpenTelemetry::Trace.non_recording_span(span_context)
          context = OpenTelemetry::Trace.context_with_span(span)
          OpenTelemetry::Context.attach(context)
        rescue StandardError => e
          warn "Failed to restore trace context: #{e.message}"
        end
      end
    end
  end
end
