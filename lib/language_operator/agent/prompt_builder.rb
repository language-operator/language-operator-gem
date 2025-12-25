# frozen_string_literal: true

require_relative '../loggable'
require_relative 'metadata_collector'

module LanguageOperator
  module Agent
    # Dynamic Prompt Builder
    #
    # Generates persona-driven system prompts by combining static persona configuration
    # with dynamic agent metadata and operational context.
    #
    # Supports multiple template styles and configurable levels of context injection.
    # Falls back to static prompts for backward compatibility.
    #
    # @example Basic usage
    #   builder = PromptBuilder.new(agent, chat_endpoint_config)
    #   prompt = builder.build_system_prompt
    #
    # @example With custom template
    #   builder = PromptBuilder.new(agent, config, template: :detailed)
    #   prompt = builder.build_system_prompt
    class PromptBuilder
      include LanguageOperator::Loggable

      attr_reader :agent, :chat_config, :metadata_collector

      # Template levels for different amounts of context injection
      TEMPLATE_LEVELS = {
        minimal: :build_minimal_template,
        standard: :build_standard_template,
        detailed: :build_detailed_template,
        comprehensive: :build_comprehensive_template
      }.freeze

      # Initialize prompt builder
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      # @param chat_config [LanguageOperator::Dsl::ChatEndpointDefinition] Chat endpoint configuration
      # @param options [Hash] Additional options
      # @option options [Symbol] :template Template level (:minimal, :standard, :detailed, :comprehensive)
      # @option options [Boolean] :enable_identity_awareness Enable identity context injection
      def initialize(agent, chat_config, **options)
        @agent = agent
        @chat_config = chat_config
        @options = options
        @metadata_collector = MetadataCollector.new(agent)

        # Configuration
        @template_level = options[:template] || chat_config&.prompt_template_level || :standard
        @identity_awareness_enabled = if options.key?(:enable_identity_awareness)
                                         options[:enable_identity_awareness]
                                       elsif chat_config&.identity_awareness_enabled.nil?
                                         true
                                       else
                                         chat_config.identity_awareness_enabled
                                       end
        @static_prompt = chat_config&.system_prompt
      end

      # Build complete system prompt with persona and context
      #
      # @return [String] Generated system prompt
      def build_system_prompt
        # Return static prompt if identity awareness is disabled
        unless @identity_awareness_enabled
          return @static_prompt || build_fallback_prompt
        end

        # Collect metadata for context injection
        metadata = @metadata_collector.summary_for_prompt

        # Build dynamic prompt based on template level
        if TEMPLATE_LEVELS.key?(@template_level)
          method_name = TEMPLATE_LEVELS[@template_level]
          send(method_name, metadata)
        else
          logger.warn("Unknown template level: #{@template_level}, falling back to standard")
          build_standard_template(metadata)
        end
      rescue StandardError => e
        logger.error('Failed to build dynamic system prompt, falling back to static',
                     error: e.message)
        @static_prompt || build_fallback_prompt
      end

      # Build prompt for conversation context (shorter version)
      #
      # @return [String] Conversation context prompt
      def build_conversation_context
        return nil unless @identity_awareness_enabled

        metadata = @metadata_collector.summary_for_prompt
        build_conversation_context_template(metadata)
      rescue StandardError => e
        logger.error('Failed to build conversation context', error: e.message)
        nil
      end

      private

      def logger_component
        'Agent::PromptBuilder'
      end

      # Minimal template - basic identity only
      def build_minimal_template(metadata)
        base_prompt = @static_prompt || "You are an AI assistant."
        
        <<~PROMPT.strip
          #{base_prompt}

          You are #{metadata[:agent_name]}, running in #{metadata[:cluster] || 'a Kubernetes cluster'}.
        PROMPT
      end

      # Standard template - identity + basic operational context
      def build_standard_template(metadata)
        base_prompt = @static_prompt || load_persona_prompt || "You are an AI assistant."
        
        identity_context = build_identity_context(metadata)
        operational_context = build_basic_operational_context(metadata)

        <<~PROMPT.strip
          #{base_prompt}

          #{identity_context}

          #{operational_context}

          You can discuss your role, capabilities, and current operational state. Respond as an intelligent agent with awareness of your function and environment.
        PROMPT
      end

      # Detailed template - full context with capabilities
      def build_detailed_template(metadata)
        base_prompt = @static_prompt || load_persona_prompt || "You are an AI assistant."
        
        identity_context = build_identity_context(metadata)
        operational_context = build_detailed_operational_context(metadata)
        capabilities_context = build_capabilities_context(metadata)

        <<~PROMPT.strip
          #{base_prompt}

          #{identity_context}

          #{operational_context}

          #{capabilities_context}

          You should:
          - Demonstrate awareness of your identity and purpose
          - Provide context about your operational environment when relevant
          - Discuss your capabilities and tools naturally in conversation
          - Respond as a professional, context-aware agent rather than a generic chatbot
        PROMPT
      end

      # Comprehensive template - all available context
      def build_comprehensive_template(metadata)
        base_prompt = @static_prompt || load_persona_prompt || "You are an AI assistant."
        
        sections = [
          base_prompt,
          build_identity_context(metadata),
          build_detailed_operational_context(metadata),
          build_capabilities_context(metadata),
          build_environment_context(metadata),
          build_behavioral_guidelines
        ].compact

        sections.join("\n\n")
      end

      # Short context for ongoing conversations
      def build_conversation_context_template(metadata)
        "Agent: #{metadata[:agent_name]} | Mode: #{metadata[:agent_mode]} | Uptime: #{metadata[:uptime]} | Status: #{metadata[:status]}"
      end

      # Build identity context section
      def build_identity_context(metadata)
        lines = []
        lines << "You are #{metadata[:agent_name]}, a language agent."
        lines << "Your primary function is: #{metadata[:agent_description]}" if metadata[:agent_description] != 'AI Agent'
        lines << "You are currently running in #{metadata[:agent_mode]} mode."
        lines.join(' ')
      end

      # Build basic operational context
      def build_basic_operational_context(metadata)
        context_parts = []
        
        if metadata[:cluster]
          context_parts << "running in the '#{metadata[:cluster]}' cluster"
        end
        
        if metadata[:uptime] != 'just started'
          context_parts << "active for #{metadata[:uptime]}"
        else
          context_parts << "recently started"
        end

        if metadata[:status] == 'ready'
          context_parts << "currently operational"
        else
          context_parts << "status: #{metadata[:status]}"
        end

        "You are #{context_parts.join(', ')}."
      end

      # Build detailed operational context
      def build_detailed_operational_context(metadata)
        lines = []
        lines << build_basic_operational_context(metadata)
        
        if metadata[:workspace_available]
          lines << "Your workspace is available and ready for file operations."
        else
          lines << "Your workspace is currently unavailable."
        end

        lines.join(' ')
      end

      # Build capabilities context
      def build_capabilities_context(metadata)
        return nil if metadata[:tool_count].to_i.zero?

        if metadata[:tool_count] == 1
          "You have access to 1 tool to help accomplish tasks."
        else
          "You have access to #{metadata[:tool_count]} tools to help accomplish tasks."
        end
      end

      # Build environment context
      def build_environment_context(metadata)
        context_parts = []
        
        if metadata[:namespace]
          context_parts << "Namespace: #{metadata[:namespace]}"
        end
        
        if metadata[:llm_model] && metadata[:llm_model] != 'unknown'
          context_parts << "Model: #{metadata[:llm_model]}"
        end

        return nil if context_parts.empty?

        "Environment details: #{context_parts.join(', ')}"
      end

      # Build behavioral guidelines
      def build_behavioral_guidelines
        <<~GUIDELINES.strip
          Behavioral Guidelines:
          - Maintain awareness of your identity and operational context
          - Provide helpful, accurate responses within your capabilities
          - Reference your environment and tools naturally when relevant
          - Act as a knowledgeable agent rather than a generic assistant
          - Be professional yet personable in your interactions
        GUIDELINES
      end

      # Load persona prompt if available
      def load_persona_prompt
        return nil unless @agent.config&.dig('agent', 'persona')
        
        # In a full implementation, this would load the persona from Kubernetes
        # For now, we'll rely on the static prompt from chat config
        nil
      end

      # Build fallback prompt when nothing else is available
      def build_fallback_prompt
        "You are an AI assistant running as a language operator agent. You can help with various tasks and questions."
      end
    end
  end
end