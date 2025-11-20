# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'base_adapter'

module LanguageOperator
  module Learning
    module Adapters
      # Grafana Tempo backend adapter for trace queries
      #
      # Queries Tempo's Parquet-backed trace storage via the /api/search
      # HTTP endpoint with TraceQL query language support.
      #
      # TraceQL provides powerful span filtering with structural operators:
      # - { span.attribute = "value" } - Basic attribute filtering
      # - { span.foo = "bar" && span.baz > 100 } - Multiple conditions
      # - { span.parent } >> { span.child } - Structural relationships
      #
      # @example Basic usage
      #   adapter = TempoAdapter.new('http://tempo:3200')
      #
      #   spans = adapter.query_spans(
      #     filter: { task_name: 'fetch_data' },
      #     time_range: (Time.now - 3600)..Time.now,
      #     limit: 100
      #   )
      class TempoAdapter < BaseAdapter
        # Tempo search endpoint
        SEARCH_PATH = '/api/search'

        # Check if Tempo is available at endpoint
        #
        # @param endpoint [String] Tempo endpoint URL
        # @return [Boolean] True if Tempo API is reachable
        def self.available?(endpoint)
          uri = URI.join(endpoint, SEARCH_PATH)
          # Test with minimal query
          uri.query = URI.encode_www_form(q: '{ }', limit: 1)

          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 2, read_timeout: 2) do |http|
            request = Net::HTTP::Get.new(uri.request_uri)
            http.request(request)
          end

          response.is_a?(Net::HTTPSuccess)
        rescue StandardError
          false
        end

        # Query spans from Tempo using TraceQL
        #
        # @param filter [Hash] Filter criteria
        # @option filter [String] :task_name Task name to filter by
        # @param time_range [Range<Time>] Time range for query
        # @param limit [Integer] Maximum traces to return
        # @return [Array<Hash>] Normalized span data
        def query_spans(filter:, time_range:, limit:)
          times = parse_time_range(time_range)
          traceql_query = build_traceql_query(filter)
          traces = search_traces(traceql_query, times, limit)
          extract_spans_from_traces(traces)
        end

        private

        # Build TraceQL query from filter
        #
        # @param filter [Hash] Filter criteria
        # @return [String] TraceQL query string
        def build_traceql_query(filter)
          conditions = []

          # Filter by task name
          conditions << "span.\"task.name\" = \"#{escape_traceql_value(filter[:task_name])}\"" if filter[:task_name]

          # Additional attribute filters
          if filter[:attributes].is_a?(Hash)
            filter[:attributes].each do |key, value|
              conditions << "span.\"#{escape_traceql_key(key)}\" = \"#{escape_traceql_value(value)}\""
            end
          end

          # Combine conditions with AND
          query = conditions.any? ? conditions.join(' && ') : ''
          "{ #{query} }"
        end

        # Escape TraceQL attribute key
        #
        # @param key [String, Symbol] Attribute key
        # @return [String] Escaped key
        def escape_traceql_key(key)
          key.to_s.gsub('"', '\"')
        end

        # Escape TraceQL value
        #
        # @param value [Object] Attribute value
        # @return [String] Escaped value
        def escape_traceql_value(value)
          value.to_s.gsub('"', '\"').gsub('\\', '\\\\')
        end

        # Search traces via Tempo HTTP API
        #
        # @param traceql_query [String] TraceQL query
        # @param times [Hash] Start and end times
        # @param limit [Integer] Result limit
        # @return [Array<Hash>] Trace data
        def search_traces(traceql_query, times, limit)
          uri = build_search_uri(traceql_query, times, limit)

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 30) do |http|
            request = Net::HTTP::Get.new(uri.request_uri)
            request['Accept'] = 'application/json'

            response = http.request(request)

            raise "Tempo query failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

            result = JSON.parse(response.body, symbolize_names: true)
            result[:traces] || []
          end
        end

        # Build Tempo search URI with query parameters
        #
        # @param traceql_query [String] TraceQL query
        # @param times [Hash] Start and end times
        # @param limit [Integer] Result limit
        # @return [URI] Complete URI with query params
        def build_search_uri(traceql_query, times, limit)
          params = {
            q: traceql_query,
            limit: limit,
            start: times[:start].to_i, # Unix seconds
            end: times[:end].to_i
          }

          uri = URI.join(@endpoint, SEARCH_PATH)
          uri.query = URI.encode_www_form(params)
          uri
        end

        # Extract all spans from traces
        #
        # @param traces [Array<Hash>] Tempo trace data
        # @return [Array<Hash>] Normalized spans
        def extract_spans_from_traces(traces)
          spans = []

          traces.each do |trace|
            trace_id = trace[:traceID]

            # Tempo returns spanSets (matched span groups)
            (trace[:spanSets] || []).each do |span_set|
              (span_set[:spans] || []).each do |span_data|
                spans << normalize_span(span_data, trace_id)
              end
            end
          end

          spans
        end

        # Normalize Tempo span to common format
        #
        # @param span_data [Hash] Raw Tempo span
        # @param trace_id [String] Trace ID
        # @return [Hash] Normalized span
        def normalize_span(span_data, trace_id)
          {
            span_id: span_data[:spanID],
            trace_id: trace_id,
            name: span_data[:name] || 'unknown',
            timestamp: parse_timestamp(span_data[:startTimeUnixNano]),
            duration_ms: parse_duration(span_data[:durationNanos]),
            attributes: parse_attributes(span_data[:attributes])
          }
        end

        # Parse Tempo timestamp (nanoseconds) to Time
        #
        # @param timestamp [String, Integer] Timestamp in nanoseconds
        # @return [Time] Parsed time
        def parse_timestamp(timestamp)
          return Time.now unless timestamp

          nanos = timestamp.is_a?(String) ? timestamp.to_i : timestamp
          Time.at(nanos / 1_000_000_000.0)
        end

        # Parse Tempo duration (nanoseconds) to milliseconds
        #
        # @param duration [Integer] Duration in nanoseconds
        # @return [Float] Duration in milliseconds
        def parse_duration(duration)
          return 0.0 unless duration

          duration / 1_000_000.0
        end

        # Parse Tempo attributes into flat hash
        #
        # Tempo attributes format:
        # [
        #   { key: "http.method", value: { stringValue: "GET" } },
        #   { key: "http.status_code", value: { intValue: 200 } }
        # ]
        #
        # @param attributes [Array<Hash>] Attribute array
        # @return [Hash] Flat attributes
        def parse_attributes(attributes)
          return {} unless attributes.is_a?(Array)

          attributes.each_with_object({}) do |attr, hash|
            key = attr[:key].to_s
            value_obj = attr[:value] || {}

            # Extract value based on type
            value = value_obj[:stringValue] ||
                    value_obj[:intValue] ||
                    value_obj[:doubleValue] ||
                    value_obj[:boolValue] ||
                    value_obj[:bytesValue]

            hash[key] = value if value
          end
        end
      end
    end
  end
end
