# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'base_adapter'

module LanguageOperator
  module Learning
    module Adapters
      # SigNoz backend adapter for trace queries
      #
      # Queries SigNoz's ClickHouse-backed trace storage via the /api/v5/query_range
      # HTTP endpoint. Supports filtering by span attributes with AND/OR logic.
      #
      # @example Basic usage
      #   adapter = SignozAdapter.new(
      #     'https://example.signoz.io',
      #     'your-api-key'
      #   )
      #
      #   spans = adapter.query_spans(
      #     filter: { task_name: 'fetch_data' },
      #     time_range: (Time.now - 3600)..Time.now,
      #     limit: 100
      #   )
      class SignozAdapter < BaseAdapter
        # SigNoz query endpoint path
        QUERY_PATH = '/api/v5/query_range'

        # Check if SigNoz is available at endpoint
        #
        # @param endpoint [String] SigNoz endpoint URL
        # @return [Boolean] True if SigNoz API is reachable
        def self.available?(endpoint)
          uri = URI.join(endpoint, QUERY_PATH)

          # Test with minimal POST request since HEAD returns HTML web UI
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 2, read_timeout: 2) do |http|
            request = Net::HTTP::Post.new(uri.path)
            request['Content-Type'] = 'application/json'
            request.body = '{}'
            http.request(request)
          end

          # Accept both success (200) and error responses (400) - both indicate API is working
          # Reject only network/auth failures
          response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPClientError)
        rescue StandardError
          false
        end

        # Query spans from SigNoz
        #
        # @param filter [Hash] Filter criteria
        # @option filter [String] :task_name Task name to filter by
        # @param time_range [Range<Time>] Time range for query
        # @param limit [Integer] Maximum spans to return
        # @return [Array<Hash>] Normalized span data
        def query_spans(filter:, time_range:, limit:)
          times = parse_time_range(time_range)
          request_body = build_query_request(filter, times, limit)

          response = execute_query(request_body)
          parse_response(response)
        end

        private

        # Build SigNoz v5 query request body
        #
        # @param filter [Hash] Filter criteria
        # @param times [Hash] Start and end times
        # @param limit [Integer] Result limit
        # @return [Hash] Request body
        def build_query_request(filter, times, limit)
          {
            start: (times[:start].to_f * 1000).to_i, # Unix milliseconds
            end: (times[:end].to_f * 1000).to_i,
            requestType: 'raw',
            variables: {},
            compositeQuery: {
              queries: [
                {
                  type: 'builder_query',
                  spec: {
                    name: 'A',
                    signal: 'traces',
                    filter: build_filter_expression(filter),
                    selectFields: [
                      { name: 'spanID' },
                      { name: 'traceID' },
                      { name: 'timestamp' },
                      { name: 'durationNano' },
                      { name: 'name' },
                      { name: 'serviceName' }
                    ],
                    order: [
                      {
                        key: { name: 'timestamp' },
                        direction: 'desc'
                      }
                    ],
                    limit: limit,
                    offset: 0,
                    disabled: false
                  }
                }
              ]
            }
          }
        end

        # Build filter expression for SigNoz v5 query
        #
        # SigNoz v5 filter syntax: attribute_name = 'value' (attribute name unquoted)
        #
        # @param filter [Hash] Filter criteria
        # @return [Hash] Filter expression structure
        def build_filter_expression(filter)
          expressions = []

          # Filter by task name (attribute name should NOT be quoted)
          expressions << "task.name = '#{filter[:task_name]}'" if filter[:task_name]

          # Additional attribute filters
          if filter[:attributes].is_a?(Hash)
            filter[:attributes].each do |key, value|
              expressions << "#{key} = '#{value}'"
            end
          end

          # Return filter expression (v5 format)
          if expressions.empty?
            { expression: '' }
          else
            { expression: expressions.join(' AND ') }
          end
        end

        # Build filter items for SigNoz query (legacy, kept for reference)
        #
        # @param filter [Hash] Filter criteria
        # @return [Hash] Filters structure
        def build_filters(filter)
          items = []

          # Filter by task name (tag attribute)
          if filter[:task_name]
            items << {
              key: {
                key: 'task.name',
                dataType: 'string',
                type: 'tag'
              },
              op: '=',
              value: filter[:task_name]
            }
          end

          # Additional attribute filters
          if filter[:attributes].is_a?(Hash)
            filter[:attributes].each do |key, value|
              items << {
                key: {
                  key: key.to_s,
                  dataType: infer_data_type(value),
                  type: 'tag'
                },
                op: '=',
                value: value
              }
            end
          end

          {
            items: items,
            op: 'AND'
          }
        end

        # Infer SigNoz data type from value
        #
        # @param value [Object] Value to inspect
        # @return [String] Data type ('string', 'int64', 'float64', 'bool')
        def infer_data_type(value)
          case value
          when Integer then 'int64'
          when Float then 'float64'
          when TrueClass, FalseClass then 'bool'
          else 'string'
          end
        end

        # Execute HTTP query to SigNoz
        #
        # @param request_body [Hash] Request body
        # @return [Hash] Parsed response
        def execute_query(request_body)
          uri = URI.join(@endpoint, QUERY_PATH)

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 30) do |http|
            request = Net::HTTP::Post.new(uri.path)
            request['Content-Type'] = 'application/json'
            request['SIGNOZ-API-KEY'] = @api_key if @api_key
            request.body = JSON.generate(request_body)

            @logger&.debug("SigNoz Query: #{JSON.pretty_generate(request_body)}")

            response = http.request(request)

            unless response.is_a?(Net::HTTPSuccess)
              @logger&.error("SigNoz Error Response: #{response.body}")
              raise "SigNoz query failed: #{response.code} #{response.message}"
            end

            JSON.parse(response.body, symbolize_names: true)
          end
        end

        # Parse SigNoz v5 response into normalized spans
        #
        # @param response [Hash] SigNoz API response
        # @return [Array<Hash>] Normalized span data
        def parse_response(response)
          # SigNoz v5 response structure:
          # {
          #   data: {
          #     data: {
          #       results: [
          #         {
          #           queryName: 'A',
          #           rows: [
          #             { data: { spanID, traceID, ... }, timestamp: '...' }
          #           ]
          #         }
          #       ]
          #     }
          #   }
          # }

          results = response.dig(:data, :data, :results) || []
          spans = []

          results.each do |result|
            rows = result[:rows] || []
            rows.each do |row|
              span_data = row[:data] || {}
              spans << normalize_span(span_data)
            end
          end

          spans
        end

        # Normalize SigNoz span to common format
        #
        # @param span_data [Hash] Raw SigNoz span
        # @return [Hash] Normalized span
        def normalize_span(span_data)
          {
            span_id: span_data[:spanID] || span_data[:span_id],
            trace_id: span_data[:traceID] || span_data[:trace_id],
            name: span_data[:name] || span_data[:serviceName],
            timestamp: parse_timestamp(span_data[:timestamp]),
            duration_ms: (span_data[:durationNano] || 0) / 1_000_000.0,
            attributes: parse_attributes(span_data[:stringTagMap], span_data[:numberTagMap])
          }
        end

        # Parse SigNoz timestamp (v5 uses ISO 8601 strings, legacy uses nanoseconds)
        #
        # @param timestamp [String, Integer] ISO 8601 timestamp string or nanoseconds
        # @return [Time] Parsed time
        def parse_timestamp(timestamp)
          return Time.now unless timestamp

          # v5 returns ISO 8601 strings
          if timestamp.is_a?(String)
            Time.parse(timestamp)
          else
            # Legacy format: nanoseconds
            Time.at(timestamp / 1_000_000_000.0)
          end
        end

        # Parse SigNoz tag maps into flat attributes hash
        #
        # @param string_tags [Hash] String tag map
        # @param number_tags [Hash] Number tag map
        # @return [Hash] Flat attributes
        def parse_attributes(string_tags, number_tags)
          attrs = {}

          (string_tags || {}).each do |key, value|
            attrs[key.to_s] = value
          end

          (number_tags || {}).each do |key, value|
            attrs[key.to_s] = value
          end

          attrs
        end
      end
    end
  end
end
