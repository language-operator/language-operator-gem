# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'base_adapter'

module LanguageOperator
  module Learning
    module Adapters
      # Jaeger backend adapter for trace queries
      #
      # Queries Jaeger's trace storage via gRPC QueryService API (port 16685).
      # Falls back to HTTP API (port 16686) if gRPC is unavailable, though
      # HTTP API is undocumented and not recommended for production use.
      #
      # Note: This implementation uses HTTP fallback initially. Full gRPC support
      # requires the 'grpc' gem and generated protobuf stubs.
      #
      # @example Basic usage
      #   adapter = JaegerAdapter.new('http://jaeger-query:16686')
      #
      #   spans = adapter.query_spans(
      #     filter: { task_name: 'fetch_data' },
      #     time_range: (Time.now - 3600)..Time.now,
      #     limit: 100
      #   )
      class JaegerAdapter < BaseAdapter
        # Jaeger HTTP API search endpoint
        SEARCH_PATH = '/api/traces'

        # Jaeger gRPC port (for future gRPC implementation)
        GRPC_PORT = 16_685

        # Check if Jaeger is available at endpoint
        #
        # @param endpoint [String] Jaeger endpoint URL
        # @param _api_key [String, nil] API key (unused, Jaeger typically doesn't require auth)
        # @return [Boolean] True if Jaeger API is reachable
        def self.available?(endpoint, _api_key = nil)
          # Try HTTP query endpoint first
          uri = URI.join(endpoint, SEARCH_PATH)
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 2, read_timeout: 2) do |http|
            request = Net::HTTP::Get.new("#{uri.path}?service=test&limit=1")
            http.request(request)
          end

          response.is_a?(Net::HTTPSuccess)
        rescue StandardError
          false
        end

        # Query spans from Jaeger
        #
        # Uses HTTP API for search. Note: Jaeger searches by trace attributes (tags),
        # returning traces that contain at least one matching span.
        #
        # @param filter [Hash] Filter criteria
        # @option filter [String] :task_name Task name to filter by
        # @param time_range [Range<Time>] Time range for query
        # @param limit [Integer] Maximum traces to return
        # @return [Array<Hash>] Normalized span data
        def query_spans(filter:, time_range:, limit:)
          times = parse_time_range(time_range)
          traces = search_traces(filter, times, limit)
          extract_spans_from_traces(traces)
        end

        private

        # Search traces via Jaeger HTTP API
        #
        # @param filter [Hash] Filter criteria
        # @param times [Hash] Start and end times
        # @param limit [Integer] Result limit
        # @return [Array<Hash>] Trace data
        def search_traces(filter, times, limit)
          uri = build_search_uri(filter, times, limit)

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 30) do |http|
            request = Net::HTTP::Get.new(uri.request_uri)
            request['Accept'] = 'application/json'

            response = http.request(request)

            raise "Jaeger query failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

            result = JSON.parse(response.body, symbolize_names: true)
            result[:data] || []
          end
        end

        # Build Jaeger search URI with query parameters
        #
        # @param filter [Hash] Filter criteria
        # @param times [Hash] Start and end times
        # @param limit [Integer] Result limit
        # @return [URI] Complete URI with query params
        def build_search_uri(filter, times, limit)
          params = {
            limit: limit,
            start: (times[:start].to_f * 1_000_000).to_i, # Microseconds
            end: (times[:end].to_f * 1_000_000).to_i
          }

          # Jaeger requires a service name for search
          # We use a wildcard or extract from task name
          params[:service] = extract_service_name(filter)

          # Add tag filters
          params[:tags] = { 'task.name' => filter[:task_name] }.to_json if filter[:task_name]

          uri = URI.join(@endpoint, SEARCH_PATH)
          uri.query = URI.encode_www_form(params)
          uri
        end

        # Extract service name from filter or use wildcard
        #
        # @param filter [Hash] Filter criteria
        # @return [String] Service name
        def extract_service_name(filter)
          # Jaeger requires service name, but we don't always know it
          # Use task name prefix or wildcard
          if filter[:task_name]
            # Assume service name from task (e.g., "user_service.fetch_user")
            parts = filter[:task_name].split('.')
            parts.size > 1 ? parts[0] : 'agent'
          else
            'agent' # Default service name
          end
        end

        # Extract all spans from traces
        #
        # @param traces [Array<Hash>] Jaeger trace data
        # @return [Array<Hash>] Normalized spans
        def extract_spans_from_traces(traces)
          spans = []

          traces.each do |trace|
            trace_id = trace[:traceID]
            process_map = build_process_map(trace[:processes])

            (trace[:spans] || []).each do |span_data|
              spans << normalize_span(span_data, trace_id, process_map)
            end
          end

          spans
        end

        # Build process map for resource attributes
        #
        # @param processes [Hash] Process definitions
        # @return [Hash] Process ID to name mapping
        def build_process_map(processes)
          return {} unless processes.is_a?(Hash)

          processes.transform_values do |process|
            process[:serviceName] || 'unknown'
          end
        end

        # Normalize Jaeger span to common format
        #
        # @param span_data [Hash] Raw Jaeger span
        # @param trace_id [String] Trace ID
        # @param process_map [Hash] Process mapping
        # @return [Hash] Normalized span
        def normalize_span(span_data, trace_id, process_map)
          process_id = span_data[:processID] || 'p1'
          service_name = process_map[process_id] || 'unknown'

          {
            span_id: span_data[:spanID],
            trace_id: trace_id,
            name: span_data[:operationName] || service_name,
            timestamp: parse_timestamp(span_data[:startTime]),
            duration_ms: (span_data[:duration] || 0) / 1000.0, # Microseconds to milliseconds
            attributes: parse_tags(span_data[:tags])
          }
        end

        # Parse Jaeger timestamp (microseconds) to Time
        #
        # @param timestamp [Integer] Timestamp in microseconds
        # @return [Time] Parsed time
        def parse_timestamp(timestamp)
          return Time.now unless timestamp

          Time.at(timestamp / 1_000_000.0)
        end

        # Parse Jaeger tags into flat attributes hash
        #
        # @param tags [Array<Hash>] Tag array
        # @return [Hash] Flat attributes
        def parse_tags(tags)
          return {} unless tags.is_a?(Array)

          tags.each_with_object({}) do |tag, attrs|
            key = tag[:key].to_s
            value = tag[:value]

            # Jaeger tags have type-specific value fields
            # Extract the actual value
            attrs[key] = if value.is_a?(Hash)
                           value[:stringValue] || value[:intValue] || value[:floatValue] || value[:boolValue]
                         else
                           value
                         end
          end
        end
      end
    end
  end
end
