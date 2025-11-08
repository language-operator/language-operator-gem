# frozen_string_literal: true

module LanguageOperator
  module Agent
    class MetricsTracker
      attr_reader :metrics

      def initialize
        @mutex = Mutex.new
        @metrics = {
          total_input_tokens: 0,
          total_output_tokens: 0,
          total_cached_tokens: 0,
          total_cache_creation_tokens: 0,
          request_count: 0,
          total_cost: 0.0,
          requests: []
        }
        @pricing_cache = {}
      end

      # Record token usage from an LLM response
      # @param response [Object] RubyLLM response object
      # @param model_id [String] Model identifier
      def record_request(response, model_id)
        return unless response

        @mutex.synchronize do
          # Extract token counts with defensive checks
          input_tokens = extract_token_count(response, :input_tokens)
          output_tokens = extract_token_count(response, :output_tokens)
          cached_tokens = extract_token_count(response, :cached_tokens)
          cache_creation_tokens = extract_token_count(response, :cache_creation_tokens)

          # Calculate cost for this request
          cost = calculate_cost(input_tokens, output_tokens, model_id)

          # Update cumulative metrics
          @metrics[:total_input_tokens] += input_tokens
          @metrics[:total_output_tokens] += output_tokens
          @metrics[:total_cached_tokens] += cached_tokens
          @metrics[:total_cache_creation_tokens] += cache_creation_tokens
          @metrics[:request_count] += 1
          @metrics[:total_cost] += cost

          # Store per-request history (limited to last 100 requests)
          @metrics[:requests] << {
            timestamp: Time.now.iso8601,
            model: model_id,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            cached_tokens: cached_tokens,
            cache_creation_tokens: cache_creation_tokens,
            cost: cost.round(6)
          }
          @metrics[:requests].shift if @metrics[:requests].size > 100
        end
      end

      # Get cumulative statistics
      # @return [Hash] Hash with totalTokens, estimatedCost, requestCount
      def cumulative_stats
        @mutex.synchronize do
          {
            totalTokens: @metrics[:total_input_tokens] + @metrics[:total_output_tokens],
            inputTokens: @metrics[:total_input_tokens],
            outputTokens: @metrics[:total_output_tokens],
            cachedTokens: @metrics[:total_cached_tokens],
            cacheCreationTokens: @metrics[:total_cache_creation_tokens],
            requestCount: @metrics[:request_count],
            estimatedCost: @metrics[:total_cost].round(6)
          }
        end
      end

      # Get recent request history
      # @param limit [Integer] Number of recent requests to return
      # @return [Array<Hash>] Array of request details
      def recent_requests(limit = 10)
        @mutex.synchronize do
          @metrics[:requests].last(limit)
        end
      end

      # Reset all metrics (for testing)
      def reset!
        @mutex.synchronize do
          @metrics = {
            total_input_tokens: 0,
            total_output_tokens: 0,
            total_cached_tokens: 0,
            total_cache_creation_tokens: 0,
            request_count: 0,
            total_cost: 0.0,
            requests: []
          }
          @pricing_cache = {}
        end
      end

      private

      # Extract token count from response with defensive checks
      # @param response [Object] Response object
      # @param method [Symbol] Method name to call
      # @return [Integer] Token count or 0 if unavailable
      def extract_token_count(response, method)
        return 0 unless response.respond_to?(method)

        value = response.public_send(method)
        value.is_a?(Integer) ? value : 0
      rescue StandardError
        0
      end

      # Calculate cost based on token usage and model pricing
      # @param input_tokens [Integer] Number of input tokens
      # @param output_tokens [Integer] Number of output tokens
      # @param model_id [String] Model identifier
      # @return [Float] Estimated cost in USD
      def calculate_cost(input_tokens, output_tokens, model_id)
        pricing = get_pricing(model_id)
        return 0.0 unless pricing

        input_cost = (input_tokens / 1_000_000.0) * pricing[:input]
        output_cost = (output_tokens / 1_000_000.0) * pricing[:output]
        input_cost + output_cost
      rescue StandardError => e
        LanguageOperator.logger.warn('Cost calculation failed',
                                     model: model_id,
                                     error: e.message)
        0.0
      end

      # Get pricing for a model (with caching)
      # @param model_id [String] Model identifier
      # @return [Hash, nil] Hash with :input and :output prices per million tokens
      def get_pricing(model_id)
        # Return cached pricing if available
        return @pricing_cache[model_id] if @pricing_cache.key?(model_id)

        # Try to fetch from RubyLLM registry
        pricing = fetch_ruby_llm_pricing(model_id)

        # Cache and return
        @pricing_cache[model_id] = pricing
        pricing
      rescue StandardError => e
        LanguageOperator.logger.warn('Pricing lookup failed',
                                     model: model_id,
                                     error: e.message)
        # Cache nil to avoid repeated failures
        @pricing_cache[model_id] = nil
        nil
      end

      # Fetch pricing from RubyLLM registry
      # @param model_id [String] Model identifier
      # @return [Hash, nil] Pricing hash or nil
      def fetch_ruby_llm_pricing(model_id)
        # Check if RubyLLM is available
        return nil unless defined?(RubyLLM)

        # Try to find model in registry
        model_info = RubyLLM.models.find(model_id)
        return nil unless model_info

        # Extract pricing (assuming RubyLLM provides these attributes)
        if model_info.respond_to?(:input_price_per_million) &&
           model_info.respond_to?(:output_price_per_million)
          {
            input: model_info.input_price_per_million,
            output: model_info.output_price_per_million
          }
        else
          nil
        end
      rescue StandardError
        nil
      end
    end
  end
end
