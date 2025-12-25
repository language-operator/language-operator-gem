# frozen_string_literal: true

module LanguageOperator
  module Dsl
    # Chat endpoint definition for agents
    #
    # Allows agents to expose an OpenAI-compatible chat completion endpoint.
    # Other systems can treat the agent as a language model.
    #
    # @example Define basic chat endpoint
    #   agent "github-expert" do
    #     as_chat_endpoint do
    #       system_prompt "You are a GitHub API expert"
    #       temperature 0.7
    #       max_tokens 2000
    #     end
    #   end
    #
    # @example Define chat endpoint with identity awareness
    #   agent "support-bot" do
    #     as_chat_endpoint do
    #       system_prompt "You are a helpful customer support assistant"
    #       
    #       # Configure identity awareness and context injection
    #       identity_awareness do
    #         enabled true
    #         prompt_template :detailed
    #         context_injection :standard
    #       end
    #       
    #       temperature 0.8
    #     end
    #   end
    class ChatEndpointDefinition
      attr_reader :system_prompt, :temperature, :max_tokens, :model_name,
                  :top_p, :frequency_penalty, :presence_penalty, :stop_sequences,
                  :identity_awareness_enabled, :prompt_template_level, :context_injection_level

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
        
        # Identity awareness and context injection settings
        @identity_awareness_enabled = true
        @prompt_template_level = :standard
        @context_injection_level = :standard
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

      # Enable or disable identity awareness and context injection
      #
      # When enabled, the system prompt will be dynamically enhanced with
      # agent identity, operational context, and environment information.
      #
      # @param enabled [Boolean] Whether to enable identity awareness
      # @return [Boolean] Current setting
      def enable_identity_awareness(enabled = nil)
        return @identity_awareness_enabled if enabled.nil?

        @identity_awareness_enabled = enabled
      end

      # Set the prompt template level for context injection
      #
      # Available levels:
      # - :minimal - Basic agent identity only
      # - :standard - Identity + basic operational context (default)
      # - :detailed - Full context with capabilities
      # - :comprehensive - All available context and guidelines
      #
      # @param level [Symbol] Template level
      # @return [Symbol] Current template level
      def prompt_template(level = nil)
        return @prompt_template_level if level.nil?

        valid_levels = [:minimal, :standard, :detailed, :comprehensive]
        unless valid_levels.include?(level)
          raise ArgumentError, "Invalid template level: #{level}. Must be one of: #{valid_levels.join(', ')}"
        end

        @prompt_template_level = level
      end

      # Set the context injection level for conversations
      #
      # Controls how much operational context is injected into ongoing conversations.
      #
      # Available levels:
      # - :none - No context injection
      # - :minimal - Basic status only
      # - :standard - Standard operational context (default)
      # - :detailed - Full context with metrics
      #
      # @param level [Symbol] Context injection level
      # @return [Symbol] Current context injection level
      def context_injection(level = nil)
        return @context_injection_level if level.nil?

        valid_levels = [:none, :minimal, :standard, :detailed]
        unless valid_levels.include?(level)
          raise ArgumentError, "Invalid context level: #{level}. Must be one of: #{valid_levels.join(', ')}"
        end

        @context_injection_level = level
      end

      # Configure identity awareness with options block
      #
      # @example
      #   identity_awareness do
      #     enabled true
      #     prompt_template :detailed
      #     context_injection :standard
      #   end
      #
      # @yield Block for configuring identity awareness options
      def identity_awareness(&block)
        if block_given?
          instance_eval(&block)
        else
          {
            enabled: @identity_awareness_enabled,
            prompt_template: @prompt_template_level,
            context_injection: @context_injection_level
          }
        end
      end

      # Alias methods for convenience
      alias_method :enabled, :enable_identity_awareness
      alias_method :template, :prompt_template
      alias_method :context, :context_injection
    end
  end
end
