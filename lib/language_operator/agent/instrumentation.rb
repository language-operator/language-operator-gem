# frozen_string_literal: true

require 'opentelemetry/sdk'

module LanguageOperator
  module Agent
    # OpenTelemetry instrumentation helpers for agent methods
    #
    # Provides reusable patterns for tracing agent operations with
    # automatic error handling and span status management.
    #
    # @example Instrument a method
    #   include LanguageOperator::Agent::Instrumentation
    #
    #   def my_method
    #     with_span('my_method', attributes: { 'key' => 'value' }) do
    #       # Method implementation
    #     end
    #   end
    module Instrumentation
      private

      # Get the configured OpenTelemetry tracer
      #
      # @return [OpenTelemetry::Trace::Tracer]
      def tracer
        @tracer ||= OpenTelemetry.tracer_provider.tracer(
          'language-operator-agent',
          LanguageOperator::VERSION
        )
      end

      # Execute block within a traced span with automatic error handling
      #
      # Creates a span with the given name and attributes, executes the block,
      # and automatically records exceptions and sets error status if raised.
      #
      # @param name [String] Span name
      # @param attributes [Hash] Span attributes
      # @yield [OpenTelemetry::Trace::Span] The created span
      # @return [Object] Result of the block
      # @raise Re-raises any exception after recording it on the span
      def with_span(name, attributes: {})
        tracer.in_span(name, attributes: attributes) do |span|
          yield span
        rescue StandardError => e
          span.record_exception(e)
          span.status = OpenTelemetry::Trace::Status.error(e.message)
          raise
        end
      end
    end
  end
end
