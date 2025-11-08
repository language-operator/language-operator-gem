# frozen_string_literal: true

module LanguageOperator
  module Dsl
    # Chat endpoint definition for agents
    #
    # Allows agents to expose an OpenAI-compatible chat completion endpoint.
    # Other systems can treat the agent as a language model.
    #
    # @example Define chat endpoint in an agent
    #   agent "github-expert" do
    #     as_chat_endpoint do
    #       system_prompt "You are a GitHub API expert"
    #       temperature 0.7
    #       max_tokens 2000
    #     end
    #   end
    class ChatEndpointDefinition
      attr_reader :system_prompt, :temperature, :max_tokens, :model_name,
                  :top_p, :frequency_penalty, :presence_penalty, :stop_sequences

      def initialize(agent_name)
        @agent_name = agent_name
        @system_prompt = nil
        @temperature = 0.7
        @max_tokens = 2000
        @model_name = agent_name
        @top_p = 1.0
        @frequency_penalty = 0.0
        @presence_penalty = 0.0
        @stop_sequences = nil
      end

      # Set system prompt for chat mode
      #
      # @param prompt [String] System prompt
      # @return [String] Current system prompt
      def system_prompt(prompt = nil)
        return @system_prompt if prompt.nil?

        @system_prompt = prompt
      end

      # Set temperature parameter
      #
      # @param value [Float] Temperature (0.0-2.0)
      # @return [Float] Current temperature
      def temperature(value = nil)
        return @temperature if value.nil?

        @temperature = value
      end

      # Set maximum tokens
      #
      # @param value [Integer] Max tokens
      # @return [Integer] Current max tokens
      def max_tokens(value = nil)
        return @max_tokens if value.nil?

        @max_tokens = value
      end

      # Set model name exposed in API
      #
      # @param name [String] Model name
      # @return [String] Current model name
      def model(name = nil)
        return @model_name if name.nil?

        @model_name = name
      end

      # Set top_p parameter
      #
      # @param value [Float] Top-p (0.0-1.0)
      # @return [Float] Current top_p
      def top_p(value = nil)
        return @top_p if value.nil?

        @top_p = value
      end

      # Set frequency penalty
      #
      # @param value [Float] Frequency penalty (-2.0 to 2.0)
      # @return [Float] Current frequency penalty
      def frequency_penalty(value = nil)
        return @frequency_penalty if value.nil?

        @frequency_penalty = value
      end

      # Set presence penalty
      #
      # @param value [Float] Presence penalty (-2.0 to 2.0)
      # @return [Float] Current presence penalty
      def presence_penalty(value = nil)
        return @presence_penalty if value.nil?

        @presence_penalty = value
      end

      # Set stop sequences
      #
      # @param sequences [Array<String>] Stop sequences
      # @return [Array<String>] Current stop sequences
      def stop(sequences = nil)
        return @stop_sequences if sequences.nil?

        @stop_sequences = sequences
      end
    end
  end
end
