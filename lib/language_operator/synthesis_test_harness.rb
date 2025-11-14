# frozen_string_literal: true

require 'yaml'
require 'json'
require 'ruby_llm'
require_relative 'agent/safety/ast_validator'

module LanguageOperator
  # SynthesisTestHarness replicates the Go operator's synthesis logic for local testing.
  # This allows testing agent code generation without requiring a Kubernetes cluster.
  #
  # Usage:
  #   harness = LanguageOperator::SynthesisTestHarness.new
  #   code = harness.synthesize('synth/001/agent.yaml', model: 'claude-3-5-sonnet-20241022')
  #   File.write('agent.rb', code)
  #
  class SynthesisTestHarness
    attr_reader :template_content, :model

    def initialize(model: nil)
      @model = model || detect_default_model
      @synthesis_endpoint = ENV['SYNTHESIS_ENDPOINT']
      @synthesis_api_key = ENV['SYNTHESIS_API_KEY'] || 'dummy'
      @template_path = File.join(__dir__, 'templates', 'examples', 'agent_synthesis.tmpl')
      load_template
    end

    # Synthesize agent code from a LanguageAgent YAML file
    #
    # @param yaml_path [String] Path to LanguageAgent YAML file
    # @param model [String, nil] LLM model to use (overrides default)
    # @return [String] Generated Ruby DSL code
    def synthesize(yaml_path, model: nil)
      agent_spec = load_agent_spec(yaml_path)

      # Build synthesis request
      request = build_synthesis_request(agent_spec)

      # Build prompt from template
      prompt = build_prompt(request)

      # Call LLM
      response = call_llm(prompt, model: model || @model)

      # Extract code from markdown
      code = extract_code_from_markdown(response)

      # Validate code
      validate_code(code)

      code
    end

    private

    def load_template
      unless File.exist?(@template_path)
        raise "Synthesis template not found at: #{@template_path}"
      end

      @template_content = File.read(@template_path)
    end

    def load_agent_spec(yaml_path)
      unless File.exist?(yaml_path)
        raise "Agent YAML file not found: #{yaml_path}"
      end

      yaml_content = File.read(yaml_path)
      full_spec = YAML.safe_load(yaml_content, permitted_classes: [Symbol])

      unless full_spec['kind'] == 'LanguageAgent'
        raise "Invalid kind: expected LanguageAgent, got #{full_spec['kind']}"
      end

      # Extract agent name from metadata and merge into spec
      agent_spec = full_spec['spec'].dup
      agent_spec['agentName'] = full_spec.dig('metadata', 'name') if full_spec.dig('metadata', 'name')

      agent_spec
    end

    def build_synthesis_request(agent_spec)
      # Note: agent_spec is the 'spec' section from the YAML
      # The agent name comes from metadata.name, which we need to extract from the full YAML
      {
        instructions: agent_spec['instructions'],
        agent_name: agent_spec['agentName'] || 'test-agent',  # Will be overridden by metadata.name
        tools: agent_spec['toolRefs'] || [],
        models: agent_spec['modelRefs'] || [],
        persona: agent_spec['personaRefs']&.first || nil
      }
    end

    def build_prompt(request)
      # Detect temporal intent from instructions
      temporal_intent = detect_temporal_intent(request[:instructions])

      # Format tools list
      tools_list = format_list(request[:tools], 'No tools specified')

      # Format models list
      models_list = format_list(request[:models], 'No models specified')

      # Build persona section
      persona_section = ''
      if request[:persona]
        persona_section = "  persona <<~PERSONA\n    #{request[:persona]}\n  PERSONA\n"
      end

      # Build schedule section
      schedule_section = ''
      schedule_rules = ''

      # Build constraints section
      constraints_section = build_constraints_section(temporal_intent)

      case temporal_intent
      when :scheduled
        schedule_section = "\n  # Extract schedule from instructions (e.g., \"daily at noon\" -> \"0 12 * * *\")\n  schedule \"CRON_EXPRESSION\""
        schedule_rules = "2. Schedule detected - extract cron expression from instructions\n3. Set schedule block with appropriate cron expression\n4. Use high max_iterations for continuous scheduled operation"
      when :oneshot
        schedule_rules = "2. One-shot execution detected - agent will run a limited number of times\n3. Do NOT include a schedule block for one-shot agents"
      when :continuous
        schedule_rules = "2. No temporal intent detected - defaulting to continuous execution\n3. Do NOT include a schedule block unless explicitly mentioned\n4. Use high max_iterations for continuous operation"
      end

      # Render template with variable substitution
      rendered = @template_content.dup

      # Handle conditional sections (simple implementation for {{if .ErrorContext}})
      rendered.gsub!(/\{\{if \.ErrorContext\}\}.*?\{\{else\}\}/m, '')
      rendered.gsub!(/\{\{end\}\}/, '')

      # Replace variables
      rendered.gsub!('{{.Instructions}}', request[:instructions])
      rendered.gsub!('{{.ToolsList}}', tools_list)
      rendered.gsub!('{{.ModelsList}}', models_list)
      rendered.gsub!('{{.AgentName}}', request[:agent_name])
      rendered.gsub!('{{.TemporalIntent}}', temporal_intent.to_s.capitalize)
      rendered.gsub!('{{.PersonaSection}}', persona_section)
      rendered.gsub!('{{.ScheduleSection}}', schedule_section)
      rendered.gsub!('{{.ConstraintsSection}}', constraints_section)
      rendered.gsub!('{{.ScheduleRules}}', schedule_rules)

      rendered
    end

    def detect_temporal_intent(instructions)
      return :continuous if instructions.nil? || instructions.strip.empty?

      lower = instructions.downcase

      # One-shot indicators
      oneshot_keywords = ['run once', 'one time', 'single time', 'execute once', 'just once']
      return :oneshot if oneshot_keywords.any? { |keyword| lower.include?(keyword) }

      # Schedule indicators
      schedule_keywords = ['every', 'daily', 'hourly', 'weekly', 'monthly', 'cron', 'schedule', 'periodically']
      return :scheduled if schedule_keywords.any? { |keyword| lower.include?(keyword) }

      # Default to continuous
      :continuous
    end

    def build_constraints_section(temporal_intent)
      case temporal_intent
      when :oneshot
        <<~CONSTRAINTS.chomp
          # One-shot execution detected from instructions
            constraints do
              max_iterations 10
              timeout "10m"
            end
        CONSTRAINTS
      when :scheduled
        <<~CONSTRAINTS.chomp
          # Scheduled execution - high iteration limit for continuous operation
            constraints do
              max_iterations 999999
              timeout "10m"
            end
        CONSTRAINTS
      when :continuous
        <<~CONSTRAINTS.chomp
          # Continuous execution - no specific schedule or one-shot indicator found
            constraints do
              max_iterations 999999
              timeout "10m"
            end
        CONSTRAINTS
      end
    end

    def format_list(items, default_text)
      return default_text if items.nil? || items.empty?

      items.map { |item| "  - #{item}" }.join("\n")
    end

    def call_llm(prompt, model:)
      # Priority 1: Use SYNTHESIS_ENDPOINT if configured (OpenAI-compatible)
      if @synthesis_endpoint
        return call_openai_compatible(prompt, model)
      end

      # Priority 2: Detect provider from model name
      provider, api_key = detect_provider(model)

      unless api_key
        raise "No API key found. Set either:\n" \
              "  SYNTHESIS_ENDPOINT (for local/OpenAI-compatible)\n" \
              "  ANTHROPIC_API_KEY (for Claude)\n" \
              "  OPENAI_API_KEY (for GPT)"
      end

      # Configure RubyLLM for the provider
      RubyLLM.configure do |config|
        case provider
        when :anthropic
          config.anthropic_api_key = api_key
        when :openai
          config.openai_api_key = api_key
        end
      end

      # Create chat and send message
      chat = RubyLLM.chat(model: model, provider: provider)
      response = chat.ask(prompt)

      # Extract content
      if response.respond_to?(:content)
        response.content
      elsif response.is_a?(Hash) && response.key?('content')
        response['content']
      elsif response.is_a?(String)
        response
      else
        response.to_s
      end
    rescue StandardError => e
      raise "LLM call failed: #{e.message}"
    end

    def call_openai_compatible(prompt, model)
      # Configure RubyLLM for OpenAI-compatible endpoint
      RubyLLM.configure do |config|
        config.openai_api_key = @synthesis_api_key
        config.openai_api_base = @synthesis_endpoint
        config.openai_use_system_role = true  # Better compatibility with local models
      end

      # Create chat with OpenAI provider (will use configured endpoint)
      chat = RubyLLM.chat(model: model, provider: :openai, assume_model_exists: true)

      # Send message
      response = chat.ask(prompt)

      # Extract content
      if response.respond_to?(:content)
        response.content
      elsif response.is_a?(Hash) && response.key?('content')
        response['content']
      elsif response.is_a?(String)
        response
      else
        response.to_s
      end
    rescue StandardError => e
      raise "OpenAI-compatible endpoint call failed: #{e.message}"
    end

    def detect_provider(model)
      if model.start_with?('claude')
        [:anthropic, ENV['ANTHROPIC_API_KEY']]
      elsif model.start_with?('gpt')
        [:openai, ENV['OPENAI_API_KEY']]
      else
        # Default to Anthropic
        [:anthropic, ENV['ANTHROPIC_API_KEY']]
      end
    end

    def detect_default_model
      # Priority 1: Use SYNTHESIS_MODEL if configured
      return ENV['SYNTHESIS_MODEL'] if ENV['SYNTHESIS_MODEL']

      # Priority 2: Use cloud providers
      if ENV['ANTHROPIC_API_KEY']
        'claude-3-5-sonnet-20241022'
      elsif ENV['OPENAI_API_KEY']
        'gpt-4-turbo'
      else
        # Default to a reasonable model name for local endpoints
        'mistralai/magistral-small-2509'
      end
    end

    def extract_code_from_markdown(content)
      content = content.strip

      # Try ```ruby first
      if (match = content.match(/```ruby\n(.*?)```/m))
        return match[1].strip
      end

      # Try generic ``` blocks
      if (match = content.match(/```\n(.*?)```/m))
        return match[1].strip
      end

      # If no code blocks, return as-is and let validation catch it
      content
    end

    def validate_code(code)
      # Basic checks
      raise "Empty code generated" if code.strip.empty?
      raise "Code does not contain 'agent' definition" unless code.include?('agent ')
      raise "Code does not require 'language_operator'" unless code.match?(/require ['"]language_operator['"]/)

      # AST validation for security
      validator = LanguageOperator::Agent::Safety::ASTValidator.new
      violations = validator.validate(code, '(generated)')

      unless violations.empty?
        error_msgs = violations.map { |v| v[:message] }.join("\n")
        raise "Security validation failed:\n#{error_msgs}"
      end

      true
    end
  end
end
