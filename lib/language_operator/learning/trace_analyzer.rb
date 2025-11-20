# frozen_string_literal: true

require 'logger'
require_relative 'adapters/base_adapter'

module LanguageOperator
  module Learning
    # Analyzes OpenTelemetry traces to detect patterns in task execution
    #
    # The TraceAnalyzer queries OTLP backends (SigNoz, Jaeger, Tempo) to retrieve
    # execution traces for neural tasks, then analyzes them to determine if they
    # exhibit consistent patterns that can be codified into symbolic implementations.
    #
    # Auto-detects available backends in order: SigNoz → Jaeger → Tempo
    # Falls back gracefully if no backend is available (learning disabled).
    #
    # @example Basic usage
    #   analyzer = TraceAnalyzer.new(
    #     endpoint: ENV['OTEL_QUERY_ENDPOINT'],
    #     api_key: ENV['OTEL_QUERY_API_KEY']
    #   )
    #
    #   analysis = analyzer.analyze_patterns(task_name: 'fetch_user_data')
    #   if analysis && analysis[:consistency] >= 0.85
    #     puts "Task is ready for learning!"
    #     puts "Tool sequence: #{analysis[:common_pattern]}"
    #   end
    #
    # @example Explicit backend selection
    #   ENV['OTEL_QUERY_BACKEND'] = 'signoz'
    #   analyzer = TraceAnalyzer.new(endpoint: 'https://signoz.example.com')
    class TraceAnalyzer
      # Minimum pattern consistency required for learning (configurable)
      DEFAULT_CONSISTENCY_THRESHOLD = 0.85

      # Default time range for queries (24 hours)
      DEFAULT_TIME_RANGE = 24 * 60 * 60

      # Initialize trace analyzer with backend connection
      #
      # @param endpoint [String, nil] OTLP backend endpoint (auto-detected from ENV if nil)
      # @param api_key [String, nil] API key for authentication (if required)
      # @param backend [String, nil] Explicit backend type ('signoz', 'jaeger', 'tempo')
      # @param logger [Logger, nil] Logger instance (creates default if nil)
      def initialize(endpoint: nil, api_key: nil, backend: nil, logger: nil)
        @endpoint = endpoint || ENV.fetch('OTEL_QUERY_ENDPOINT', nil)
        @api_key = api_key || ENV.fetch('OTEL_QUERY_API_KEY', nil)
        @backend_type = backend || ENV.fetch('OTEL_QUERY_BACKEND', nil)
        @logger = logger || ::Logger.new($stdout, level: ::Logger::WARN)
        @adapter = detect_backend_adapter
      end

      # Check if learning is available (backend connected)
      #
      # @return [Boolean] True if a backend adapter is available
      def available?
        !@adapter.nil?
      end

      # Query task execution traces from backend
      #
      # @param task_name [String] Name of task to query
      # @param limit [Integer] Maximum number of traces to return
      # @param time_range [Integer, Range<Time>] Time range in seconds or explicit range
      # @return [Array<Hash>] Task execution data
      def query_task_traces(task_name:, limit: 100, time_range: DEFAULT_TIME_RANGE)
        unless available?
          @logger.warn('No OTLP backend available, learning disabled')
          return []
        end

        range = normalize_time_range(time_range)

        spans = @adapter.query_spans(
          filter: { task_name: task_name },
          time_range: range,
          limit: limit
        )

        @adapter.extract_task_data(spans)
      rescue StandardError => e
        @logger.error("Failed to query task traces: #{e.message}")
        @logger.debug(e.backtrace.join("\n"))
        []
      end

      # Analyze task execution patterns for consistency
      #
      # Determines if a neural task exhibits consistent behavior that can be
      # learned and converted to a symbolic implementation.
      #
      # @param task_name [String] Name of task to analyze
      # @param min_executions [Integer] Minimum executions required for analysis
      # @param consistency_threshold [Float] Required consistency (0.0-1.0)
      # @return [Hash, nil] Analysis results or nil if insufficient data
      def analyze_patterns(task_name:, min_executions: 10, consistency_threshold: DEFAULT_CONSISTENCY_THRESHOLD)
        executions = query_task_traces(task_name: task_name, limit: 1000)

        if executions.empty?
          @logger.info("No executions found for task '#{task_name}'")
          return nil
        end

        if executions.size < min_executions
          @logger.info("Insufficient executions for task '#{task_name}': #{executions.size}/#{min_executions}")
          return {
            task_name: task_name,
            execution_count: executions.size,
            required_count: min_executions,
            ready_for_learning: false,
            reason: "Need #{min_executions - executions.size} more executions"
          }
        end

        consistency_data = calculate_consistency(executions)

        {
          task_name: task_name,
          execution_count: executions.size,
          consistency_score: consistency_data[:score],
          consistency_threshold: consistency_threshold,
          ready_for_learning: consistency_data[:score] >= consistency_threshold,
          common_pattern: consistency_data[:common_pattern],
          input_signatures: consistency_data[:input_signatures],
          analysis_timestamp: Time.now.iso8601
        }
      end

      # Calculate pattern consistency across executions
      #
      # Groups executions by input signature and analyzes tool call sequences
      # to determine how often the same pattern is used for the same inputs.
      #
      # @param executions [Array<Hash>] Task execution data
      # @return [Hash] Consistency analysis with score and common pattern
      def calculate_consistency(executions)
        # Group by input signature
        by_inputs = executions.group_by { |ex| normalize_inputs(ex[:inputs]) }

        # For each input signature, find the most common tool call pattern
        signature_patterns = by_inputs.map do |input_sig, execs|
          patterns = execs.map { |ex| normalize_tool_calls(ex[:tool_calls]) }
          pattern_counts = patterns.tally
          most_common = pattern_counts.max_by { |_, count| count }

          {
            input_signature: input_sig,
            total_executions: execs.size,
            most_common_pattern: most_common[0],
            pattern_count: most_common[1],
            consistency: most_common[1].to_f / execs.size
          }
        end

        # Overall consistency is weighted average across input signatures
        total_execs = executions.size
        weighted_consistency = signature_patterns.sum do |sig_data|
          weight = sig_data[:total_executions].to_f / total_execs
          weight * sig_data[:consistency]
        end

        # Find the globally most common pattern
        all_patterns = signature_patterns.map { |s| s[:most_common_pattern] }
        common_pattern = all_patterns.max_by { |p| all_patterns.count(p) }

        {
          score: weighted_consistency.round(3),
          common_pattern: common_pattern,
          input_signatures: signature_patterns.size
        }
      end

      private

      # Detect and initialize the appropriate backend adapter
      #
      # Auto-detection order: SigNoz → Jaeger → Tempo
      # Falls back to nil if no backend is available
      #
      # @return [BaseAdapter, nil] Initialized adapter or nil
      def detect_backend_adapter
        return nil unless @endpoint

        # Explicit backend selection
        if @backend_type
          adapter = create_adapter(@backend_type)
          return adapter if adapter

          @logger.warn("Requested backend '#{@backend_type}' not available, trying auto-detection")
        end

        # Auto-detect with fallback chain
        %w[signoz jaeger tempo].each do |backend|
          adapter = create_adapter(backend)
          if adapter
            @logger.info("Detected OTLP backend: #{backend} at #{@endpoint}")
            return adapter
          end
        end

        @logger.warn("No OTLP backend available at #{@endpoint}, learning disabled")
        nil
      end

      # Create adapter instance for specified backend
      #
      # @param backend_type [String] Backend type
      # @return [BaseAdapter, nil] Adapter instance or nil if unavailable
      def create_adapter(backend_type)
        require_relative "adapters/#{backend_type}_adapter"

        adapter_class = case backend_type.downcase
                        when 'signoz'
                          Adapters::SignozAdapter
                        when 'jaeger'
                          Adapters::JaegerAdapter
                        when 'tempo'
                          Adapters::TempoAdapter
                        else
                          @logger.error("Unknown backend type: #{backend_type}")
                          return nil
                        end

        return nil unless adapter_class.available?(@endpoint)

        adapter_class.new(@endpoint, @api_key, logger: @logger)
      rescue LoadError => e
        @logger.debug("Adapter #{backend_type} not available: #{e.message}")
        nil
      rescue StandardError => e
        @logger.error("Failed to create #{backend_type} adapter: #{e.message}")
        nil
      end

      # Normalize time range to Range<Time>
      #
      # @param time_range [Integer, Range<Time>] Time range
      # @return [Range<Time>] Normalized time range
      def normalize_time_range(time_range)
        case time_range
        when Range
          time_range
        when Integer
          (Time.now - time_range)..Time.now
        else
          (Time.now - DEFAULT_TIME_RANGE)..Time.now
        end
      end

      # Normalize inputs for comparison
      #
      # @param inputs [Hash] Task inputs
      # @return [String] Normalized input signature
      def normalize_inputs(inputs)
        return '' unless inputs.is_a?(Hash)

        inputs.sort.to_h.to_s
      end

      # Normalize tool calls for pattern matching
      #
      # @param tool_calls [Array<Hash>] Tool call sequence
      # @return [String] Normalized pattern signature
      def normalize_tool_calls(tool_calls)
        return '' unless tool_calls.is_a?(Array)

        tool_calls.map { |tc| tc[:tool_name] }.join(' → ')
      end
    end
  end
end
