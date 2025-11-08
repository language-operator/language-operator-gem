# frozen_string_literal: true

require_relative 'agent/base'
require_relative 'agent/executor'
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
        LanguageOperator::Logger.info('No synthesized code found, running in standard mode',
                                      component: 'Agent',
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
      LanguageOperator::Logger.info('DSL code loading',
                                    component: 'Agent',
                                    path: code_path,
                                    agent_name: agent_name)

      # Load synthesized DSL code
      LanguageOperator::Dsl.load_agent_file(code_path)

      # Get agent definition from registry
      agent_def = LanguageOperator::Dsl.agent_registry.get(agent_name) if agent_name

      if agent_def
        LanguageOperator::Logger.info('Agent definition loaded',
                                      component: 'Agent',
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
      LanguageOperator::Logger.warn('Agent definition not found in registry',
                                    component: 'Agent',
                                    agent_name: agent_name,
                                    available: LanguageOperator::Dsl.agent_registry.all.map(&:name))
      LanguageOperator::Logger.info('Falling back to autonomous mode', component: 'Agent')
    end

    # Log agent code loading error
    #
    # @param error [StandardError] The error
    # @return [void]
    def self.log_load_error(error)
      LanguageOperator::Logger.error('Failed to load agent code',
                                     component: 'Agent',
                                     error: error.message,
                                     backtrace: error.backtrace[0..3])
      LanguageOperator::Logger.info('Falling back to autonomous mode', component: 'Agent')
    end

    # Run agent with a loaded definition
    #
    # @param agent [LanguageOperator::Agent::Base] The agent instance
    # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition
    # @return [void]
    def self.run_with_definition(agent, agent_def)
      agent.connect!

      case agent.mode
      when 'autonomous', 'interactive'
        # Execute workflow in autonomous mode
        executor = LanguageOperator::Agent::Executor.new(agent)
        executor.execute_workflow(agent_def)
      when 'scheduled', 'event-driven'
        # Schedule workflow execution
        scheduler = LanguageOperator::Agent::Scheduler.new(agent)
        scheduler.start_with_workflow(agent_def)
      when 'reactive', 'http', 'webhook'
        # Start web server with webhooks
        web_server = LanguageOperator::Agent::WebServer.new(agent)
        agent_def.webhooks.each { |webhook_def| webhook_def.register(web_server) }
        web_server.start
      else
        raise "Unknown agent mode: #{agent.mode}"
      end
    end
  end
end
