# frozen_string_literal: true

module LanguageOperator
  module Client
    # Calculates LLM API costs based on token usage and model pricing
    module CostCalculator
      # Model pricing per 1M tokens (input, output) in USD
      MODEL_PRICING = {
        # OpenAI models
        'gpt-4' => [30.0, 60.0],
        'gpt-4-turbo' => [10.0, 30.0],
        'gpt-4o' => [5.0, 15.0],
        'gpt-3.5-turbo' => [0.5, 1.5],
        # Anthropic models
        'claude-3-5-sonnet-20241022' => [3.0, 15.0],
        'claude-3-opus-20240229' => [15.0, 75.0],
        'claude-3-sonnet-20240229' => [3.0, 15.0],
        'claude-3-haiku-20240307' => [0.25, 1.25]
      }.freeze

      # Calculate cost based on model and token usage
      #
      # @param model [String] Model name
      # @param input_tokens [Integer] Number of input tokens
      # @param output_tokens [Integer] Number of output tokens
      # @return [Float, nil] Cost in USD, or nil if model pricing not found
      def calculate_cost(model, input_tokens, output_tokens)
        pricing = MODEL_PRICING[model]
        return nil unless pricing

        input_cost = (input_tokens / 1_000_000.0) * pricing[0]
        output_cost = (output_tokens / 1_000_000.0) * pricing[1]
        input_cost + output_cost
      end
    end
  end
end
