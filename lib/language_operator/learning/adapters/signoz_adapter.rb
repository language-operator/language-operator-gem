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
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 2, read_timeout: 2) do |http|
            request = Net::HTTP::Head.new(uri.path)
            http.request(request)
          end

          # SigNoz returns 405 for HEAD (only POST supported), but endpoint exists
          [200, 405].include?(response.code.to_i)
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

        # Build SigNoz query request body
        #
        # @param filter [Hash] Filter criteria
        # @param times [Hash] Start and end times
        # @param limit [Integer] Result limit
        # @return [Hash] Request body
        def build_query_request(filter, times, limit)
          {
            start: (times[:start].to_f * 1000).to_i, # Unix milliseconds
            end: (times[:end].to_f * 1000).to_i,
            step: 60,
            compositeQuery: {
              queryType: 'builder',
              panelType: 'list',
              builderQueries: {
                A: {
                  dataSource: 'traces',
                  queryName: 'A',
                  aggregateOperator: 'noop',
                  filters: build_filters(filter),
                  limit: limit,
                  offset: 0,
                  orderBy: [
                    {
                      columnName: 'timestamp',
                      order: 'desc'
                    }
                  ]
                }
              }
            }
          }
        end

        # Build filter items for SigNoz query
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

            response = http.request(request)

            raise "SigNoz query failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

            JSON.parse(response.body, symbolize_names: true)
          end
        end

        # Parse SigNoz response into normalized spans
        #
        # @param response [Hash] SigNoz API response
        # @return [Array<Hash>] Normalized span data
        def parse_response(response)
          # SigNoz response structure:
          # {
          #   data: {
          #     result: [
          #       {
          #         list: [
          #           { spanID, traceID, timestamp, attributes, ... }
          #         ]
          #       }
          #     ]
          #   }
          # }

          results = response.dig(:data, :result) || []
          spans = []

          results.each do |result|
            list = result[:list] || []
            list.each do |span_data|
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
            span_id: span_data[:spanID],
            trace_id: span_data[:traceID],
            name: span_data[:name] || span_data[:serviceName],
            timestamp: parse_timestamp(span_data[:timestamp]),
            duration_ms: (span_data[:durationNano] || 0) / 1_000_000.0,
            attributes: parse_attributes(span_data[:stringTagMap], span_data[:numberTagMap])
          }
        end

        # Parse SigNoz timestamp (nanoseconds) to Time
        #
        # @param timestamp [Integer] Timestamp in nanoseconds
        # @return [Time] Parsed time
        def parse_timestamp(timestamp)
          return Time.now unless timestamp

          Time.at(timestamp / 1_000_000_000.0)
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
