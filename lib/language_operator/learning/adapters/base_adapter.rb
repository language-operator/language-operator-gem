# frozen_string_literal: true

module LanguageOperator
  module Learning
    module Adapters
      # Abstract base class for OTLP backend query adapters
      #
      # Defines the interface that all backend adapters must implement.
      # Adapters translate generic query requests into backend-specific
      # API calls and normalize responses.
      #
      # @example Implementing a custom adapter
      #   class CustomAdapter < BaseAdapter
      #     def self.available?(endpoint, api_key = nil)
      #       # Check if backend is reachable
      #       true
      #     end
      #
      #     def query_spans(filter:, time_range:, limit:)
      #       # Query backend and return normalized spans
      #       []
      #     end
      #   end
      class BaseAdapter
        # Initialize adapter with connection details
        #
        # @param endpoint [String] Backend endpoint URL
        # @param api_key [String, nil] API key for authentication (if required)
        # @param options [Hash] Additional adapter-specific options
        def initialize(endpoint, api_key = nil, **options)
          @endpoint = endpoint
          @api_key = api_key
          @logger = options[:logger] || ::Logger.new($stdout, level: ::Logger::WARN)
          @options = options
        end

        # Check if this backend is available at the given endpoint
        #
        # @param endpoint [String] Backend endpoint URL
        # @param api_key [String, nil] API key for authentication (optional)
        # @return [Boolean] True if backend is reachable and compatible
        def self.available?(endpoint, api_key = nil)
          raise NotImplementedError, "#{self}.available? must be implemented"
        end

        # Query spans from the backend
        #
        # @param filter [Hash] Filter criteria
        # @option filter [String] :task_name Task name to filter by
        # @option filter [Hash] :attributes Additional span attributes to match
        # @param time_range [Range<Time>] Time range for query
        # @param limit [Integer] Maximum number of spans to return
        # @return [Array<Hash>] Array of normalized span hashes
        def query_spans(filter:, time_range:, limit:)
          raise NotImplementedError, "#{self.class}#query_spans must be implemented"
        end

        # Extract task execution data from spans
        #
        # Groups spans by trace and extracts task-specific metadata:
        # - inputs: Task input parameters
        # - outputs: Task output values
        # - tool_calls: Sequence of tools invoked
        # - duration: Execution duration
        #
        # @param spans [Array<Hash>] Raw spans from backend
        # @return [Array<Hash>] Task execution data grouped by trace
        def extract_task_data(spans)
          spans.group_by { |span| span[:trace_id] }.map do |trace_id, trace_spans|
            task_span = trace_spans.find { |s| s[:name]&.include?('task_executor') }
            next unless task_span

            {
              trace_id: trace_id,
              task_name: task_span.dig(:attributes, 'task.name'),
              inputs: extract_inputs(task_span),
              outputs: extract_outputs(task_span),
              tool_calls: extract_tool_calls(trace_spans),
              duration_ms: task_span[:duration_ms],
              timestamp: task_span[:timestamp]
            }
          end.compact
        end

        protected

        attr_reader :endpoint, :api_key, :options

        # Extract inputs from task span attributes
        #
        # @param span [Hash] Task execution span
        # @return [Hash] Input parameters
        def extract_inputs(span)
          attrs = span[:attributes] || {}
          input_keys = attrs['task.input.keys']&.split(',') || []

          input_keys.each_with_object({}) do |key, inputs|
            value_attr = "task.input.#{key}"
            inputs[key.to_sym] = attrs[value_attr] if attrs[value_attr]
          end
        end

        # Extract outputs from task span attributes
        #
        # @param span [Hash] Task execution span
        # @return [Hash] Output values
        def extract_outputs(span)
          attrs = span[:attributes] || {}
          output_keys = attrs['task.output.keys']&.split(',') || []

          output_keys.each_with_object({}) do |key, outputs|
            value_attr = "task.output.#{key}"
            outputs[key.to_sym] = attrs[value_attr] if attrs[value_attr]
          end
        end

        # Extract tool call sequence from trace spans
        #
        # @param trace_spans [Array<Hash>] All spans in trace
        # @return [Array<Hash>] Ordered tool call sequence
        def extract_tool_calls(trace_spans)
          trace_spans
            .select { |s| s.dig(:attributes, 'gen_ai.operation.name') == 'execute_tool' }
            .sort_by { |s| s[:timestamp] }
            .map do |tool_span|
              {
                tool_name: tool_span.dig(:attributes, 'gen_ai.tool.name'),
                arguments_size: tool_span.dig(:attributes, 'gen_ai.tool.call.arguments.size'),
                result_size: tool_span.dig(:attributes, 'gen_ai.tool.call.result.size')
              }
            end
        end

        # Parse time range into backend-specific format
        #
        # @param time_range [Range<Time>] Time range
        # @return [Hash] Start and end times
        def parse_time_range(time_range)
          {
            start: time_range.begin || (Time.now - (24 * 60 * 60)),
            end: time_range.end || Time.now
          }
        end
      end
    end
  end
end
