# frozen_string_literal: true

require_relative 'agent/base'
require_relative 'agent/executor'
require_relative 'agent/task_executor'
require_relative 'agent/scheduler'
require_relative 'agent/web_server'
require_relative 'dsl'
require_relative 'logger'

module LanguageOperator
  # Agent Framework
  #
  # Provides autonomous execution capabilities for language agents.
  # Extends LanguageOperator::Client with agent-specific features like scheduling,
  # goal evaluation, and workspace integration.
  #
  # @example Running an agent
  #   config = LanguageOperator::Client::Config.from_env
  #   agent = LanguageOperator::Agent::Base.new(config)
  #   agent.run
  #
  # @example Creating a custom agent
  #   agent = LanguageOperator::Agent::Base.new(config)
  #   agent.execute_goal("Summarize daily news")
  module Agent
    # Module-level logger for Agent framework
    @logger = LanguageOperator::Logger.new(component: 'Agent')

    def self.logger
      @logger
    end

    # Run the default agent based on environment configuration
    #
    # @param config_path [String] Path to configuration file
    # @return [void]
    def self.run(config_path: nil)
      # Disable stdout buffering for real-time logging in containers
      $stdout.sync = true
      $stderr.sync = true

      config_path ||= ENV.fetch('CONFIG_PATH', 'config.yaml')
      config = LanguageOperator::Client::Config.load_with_fallback(config_path)

      # Create agent instance
      agent = LanguageOperator::Agent::Base.new(config)

      # Load and run with synthesized code if available
      load_and_run(agent)
    end

    # Load and run agent from a specific file path
    #
    # @param code_path [String] Path to agent DSL code file
    # @param agent_name [String, nil] Name of the agent definition to run
    # @param config_path [String, nil] Path to configuration file
    # @return [void]
    def self.load_and_run_from_file(code_path, agent_name = nil, config_path: nil)
      # Disable stdout buffering for real-time logging in containers
      $stdout.sync = true
      $stderr.sync = true

      config_path ||= ENV.fetch('CONFIG_PATH', 'config.yaml')
      config = LanguageOperator::Client::Config.load_with_fallback(config_path)

      # Create agent instance
      agent = LanguageOperator::Agent::Base.new(config)

      # Load and run the specified agent code
      load_synthesized_agent(agent, code_path, agent_name)
    end

    # Load synthesized agent code and run with definition if available
    #
    # @param agent [LanguageOperator::Agent::Base] The agent instance
    # @return [void]
    def self.load_and_run(agent)
      agent_code_path = ENV.fetch('AGENT_CODE_PATH', nil)
      agent_name = ENV.fetch('AGENT_NAME', nil)

      if agent_code_path && File.exist?(agent_code_path)
        load_synthesized_agent(agent, agent_code_path, agent_name)
      else
        logger.info('No synthesized code found, running in standard mode',
                    agent_code_path: agent_code_path)
        agent.run
      end
    end

    # Load synthesized agent code and execute
    #
    # @param agent [LanguageOperator::Agent::Base] The agent instance
    # @param code_path [String] Path to synthesized code
    # @param agent_name [String] Name of agent definition
    # @return [void]
    def self.load_synthesized_agent(agent, code_path, agent_name)
      logger.info('DSL code loading',
                  path: code_path,
                  agent_name: agent_name)

      # Load synthesized DSL code
      LanguageOperator::Dsl.load_agent_file(code_path)

      # Get agent definition from registry
      agent_def = LanguageOperator::Dsl.agent_registry.get(agent_name) if agent_name

      if agent_def
        logger.info('Agent definition loaded',
                    agent_name: agent_name,
                    has_workflow: !agent_def.workflow.nil?)
        run_with_definition(agent, agent_def)
      else
        log_definition_not_found(agent_name)
        agent.run
      end
    rescue StandardError => e
      log_load_error(e)
      agent.run
    end

    # Log when agent definition is not found
    #
    # @param agent_name [String] Name of agent
    # @return [void]
    def self.log_definition_not_found(agent_name)
      logger.warn('Agent definition not found in registry',
                  agent_name: agent_name,
                  available: LanguageOperator::Dsl.agent_registry.all.map(&:name))
      logger.info('Falling back to autonomous mode')
    end

    # Log agent code loading error
    #
    # @param error [StandardError] The error
    # @return [void]
    def self.log_load_error(error)
      logger.error('Failed to load agent code',
                   error: error.message,
                   backtrace: error.backtrace[0..3])
      logger.info('Falling back to autonomous mode')
    end

    # Run agent with a loaded definition
    #
    # @param agent [LanguageOperator::Agent::Base] The agent instance
    # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition
    # @return [void]
    def self.run_with_definition(agent, agent_def)
      agent.connect!

      # Check if agent uses DSL v1 (task/main) or v0 (workflow/step)
      uses_dsl_v1 = agent_def.main&.defined?
      uses_dsl_v0 = agent_def.respond_to?(:workflow) && agent_def.workflow

      case agent.mode
      when 'autonomous', 'interactive'
        if uses_dsl_v1
          # DSL v1: Execute main block with task executor
          execute_main_block(agent, agent_def)
        elsif uses_dsl_v0
          # DSL v0: Execute workflow in autonomous mode
          executor = LanguageOperator::Agent::Executor.new(agent)
          executor.execute_workflow(agent_def)
        else
          raise 'Agent definition must have either main block (DSL v1) or workflow (DSL v0)'
        end
      when 'scheduled', 'event-driven'
        if uses_dsl_v1
          # DSL v1: Schedule main block execution
          scheduler = LanguageOperator::Agent::Scheduler.new(agent)
          scheduler.start_with_main(agent_def)
        elsif uses_dsl_v0
          # DSL v0: Schedule workflow execution
          scheduler = LanguageOperator::Agent::Scheduler.new(agent)
          scheduler.start_with_workflow(agent_def)
        else
          raise 'Agent definition must have either main block (DSL v1) or workflow (DSL v0)'
        end
      when 'reactive', 'http', 'webhook'
        # Start web server with webhooks, MCP tools, and chat endpoint
        web_server = LanguageOperator::Agent::WebServer.new(agent)
        agent_def.webhooks.each { |webhook_def| webhook_def.register(web_server) }
        web_server.register_mcp_tools(agent_def.mcp_server) if agent_def.mcp_server&.tools?
        web_server.register_chat_endpoint(agent_def.chat_endpoint, agent) if agent_def.chat_endpoint
        web_server.start
      else
        raise "Unknown agent mode: #{agent.mode}"
      end
    end

    # Execute main block (DSL v1) in autonomous mode
    #
    # @param agent [LanguageOperator::Agent::Base] The agent instance
    # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition
    # @return [void]
    def self.execute_main_block(agent, agent_def)
      # Build executor config from agent constraints
      config = build_executor_config(agent_def)
      task_executor = LanguageOperator::Agent::TaskExecutor.new(agent, agent_def.tasks, config)

      logger.info('Executing main block',
                  agent: agent_def.name,
                  task_count: agent_def.tasks.size)

      # Get inputs from environment or default to empty hash
      inputs = {}

      # Execute main block with task executor as context
      result = agent_def.main.call(inputs, task_executor)

      logger.info('Main block execution completed',
                  result: result)

      # Call output handler if defined
      if agent_def.output
        logger.debug('Executing output handler', outputs: result)
        execute_output_handler(agent_def, result, task_executor)
      end

      result
    end

    # Execute the output handler (neural or symbolic)
    #
    # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition
    # @param outputs [Hash] The outputs from main execution
    # @param task_executor [LanguageOperator::Agent::TaskExecutor] Task executor for context
    # @return [void]
    def self.execute_output_handler(agent_def, outputs, task_executor)
      output_config = agent_def.output

      # If symbolic implementation exists, use it
      if output_config.symbolic?
        logger.debug('Executing symbolic output handler')
        # execute_symbolic takes (inputs, context) - outputs are the inputs, task_executor is context
        output_config.execute_symbolic(outputs, task_executor)
      elsif output_config.neural?
        # Neural output - would need LLM access to execute
        # For now, just log the instruction
        logger.info('Neural output handler',
                    instruction: output_config.instructions_text,
                    outputs: outputs)
        logger.warn('Neural output execution not yet implemented - instruction logged only')
      end
    rescue StandardError => e
      logger.error('Output handler failed',
                   error: e.message,
                   backtrace: e.backtrace[0..5])
    end

    # Build executor configuration from agent definition constraints
    #
    # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition
    # @return [Hash] Executor configuration
    def self.build_executor_config(agent_def)
      config = {}

      if agent_def.constraints
        if agent_def.constraints[:timeout]
          timeout = agent_def.constraints[:timeout]
          config[:timeout] = timeout.is_a?(String) ? parse_duration(timeout) : timeout
        end
        config[:max_retries] = agent_def.constraints[:max_retries] if agent_def.constraints[:max_retries]
      end

      config
    end

    # Parse duration string to seconds
    #
    # @param duration [String] Duration string (e.g., "10m", "2h", "30s")
    # @return [Numeric] Duration in seconds
    def self.parse_duration(duration)
      case duration
      when /^(\d+)s$/
        ::Regexp.last_match(1).to_i
      when /^(\d+)m$/
        ::Regexp.last_match(1).to_i * 60
      when /^(\d+)h$/
        ::Regexp.last_match(1).to_i * 3600
      when Numeric
        duration
      else
        raise ArgumentError, "Invalid duration format: #{duration}. Use format like '10m', '2h', '30s'"
      end
    end
  end
end
