# frozen_string_literal: true

require 'rufus-scheduler'
require_relative 'executor'
require_relative 'instrumentation'
require_relative '../logger'
require_relative '../loggable'

module LanguageOperator
  module Agent
    # Task Scheduler
    #
    # Handles scheduled and event-driven task execution using rufus-scheduler.
    #
    # @example
    #   scheduler = Scheduler.new(agent)
    #   scheduler.start
    class Scheduler
      include LanguageOperator::Loggable
      include LanguageOperator::Agent::Instrumentation

      attr_reader :agent, :rufus_scheduler

      # Initialize the scheduler
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      def initialize(agent)
        @agent = agent
        @rufus_scheduler = Rufus::Scheduler.new
        @executor = Executor.new(agent)

        logger.debug('Scheduler initialized',
                     workspace: @agent.workspace_path,
                     servers: @agent.servers_info.length)
      end

      # Start the scheduler
      #
      # @return [void]
      def start
        logger.info('Agent starting in scheduled mode')
        logger.info("Workspace: #{@agent.workspace_path}")
        logger.info("Connected to #{@agent.servers_info.length} MCP server(s)")

        setup_schedules
        logger.info('Scheduler started, waiting for scheduled tasks')
        @rufus_scheduler.join
      end

      # Start the scheduler with a workflow definition
      #
      # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition with workflow
      # @return [void]
      def start_with_workflow(agent_def)
        logger.info('Agent starting in scheduled mode with workflow',
                    agent_name: agent_def.name,
                    has_workflow: !agent_def.workflow.nil?)
        logger.info("Workspace: #{@agent.workspace_path}")
        logger.info("Connected to #{@agent.servers_info.length} MCP server(s)")

        # Extract schedule from agent definition or use default
        cron_schedule = agent_def.schedule&.cron || '0 6 * * *'

        logger.info('Scheduling workflow', cron: cron_schedule, agent: agent_def.name)

        @rufus_scheduler.cron(cron_schedule) do
          with_span('agent.scheduler.execute', attributes: {
                      'scheduler.cron_expression' => cron_schedule,
                      'agent.name' => agent_def.name,
                      'scheduler.task_type' => 'workflow'
                    }) do
            logger.timed('Scheduled workflow execution') do
              logger.info('Executing scheduled workflow', agent: agent_def.name)
              result = @executor.execute_workflow(agent_def)
              result_text = result.is_a?(String) ? result : result.content
              preview = result_text[0..200]
              preview += '...' if result_text.length > 200
              logger.info('Workflow completed', result_preview: preview)
            end
          end
        end

        logger.info('Scheduler started, waiting for scheduled tasks')
        @rufus_scheduler.join
      end

      # Start the scheduler with a main block (DSL v1)
      #
      # @param agent_def [LanguageOperator::Dsl::AgentDefinition] The agent definition with main block
      # @return [void]
      def start_with_main(agent_def)
        logger.info('Agent starting in scheduled mode with main block',
                    agent_name: agent_def.name,
                    task_count: agent_def.tasks.size)
        logger.info("Workspace: #{@agent.workspace_path}")
        logger.info("Connected to #{@agent.servers_info.length} MCP server(s)")

        # Extract schedule from agent definition or use default
        cron_schedule = agent_def.schedule&.cron || '0 6 * * *'

        logger.info('Scheduling main block execution', cron: cron_schedule, agent: agent_def.name)

        # Create task executor
        require_relative 'task_executor'
        task_executor = TaskExecutor.new(@agent, agent_def.tasks)

        @rufus_scheduler.cron(cron_schedule) do
          with_span('agent.scheduler.execute', attributes: {
                      'scheduler.cron_expression' => cron_schedule,
                      'agent.name' => agent_def.name,
                      'scheduler.task_type' => 'main_block'
                    }) do
            logger.timed('Scheduled main block execution') do
              logger.info('Executing scheduled main block', agent: agent_def.name)

              # Get inputs from environment or default to empty hash
              inputs = {}

              # Execute main block
              result = agent_def.main.call(inputs, task_executor)

              logger.info('Main block completed', result: result)
            end
          end
        end

        logger.info('Scheduler started, waiting for scheduled tasks')
        @rufus_scheduler.join
      end

      # Stop the scheduler
      #
      # @return [void]
      def stop
        logger.info('Shutting down scheduler')
        @rufus_scheduler.shutdown
        logger.info('Scheduler stopped')
      end

      private

      def logger_component
        'Agent::Scheduler'
      end

      # Setup schedules from config
      #
      # @return [void]
      def setup_schedules
        schedules = @agent.config.dig('agent', 'schedules') || []

        logger.debug('Loading schedules from config', count: schedules.length)

        if schedules.empty?
          logger.warn('No schedules configured, using default daily schedule')
          setup_default_schedule
          return
        end

        schedules.each do |schedule|
          add_schedule(schedule)
        end

        logger.info("#{schedules.length} schedule(s) configured")
      end

      # Add a single schedule
      #
      # @param schedule [Hash] Schedule configuration
      # @return [void]
      def add_schedule(schedule)
        cron = schedule['cron']
        task = schedule['task']
        agent_name = @agent.config.dig('agent', 'name')

        logger.info('Scheduling task', cron: cron, task: task[0..100])

        @rufus_scheduler.cron(cron) do
          with_span('agent.scheduler.execute', attributes: {
                      'scheduler.cron_expression' => cron,
                      'agent.name' => agent_name,
                      'scheduler.task_type' => 'scheduled'
                    }) do
            logger.timed('Scheduled task execution') do
              logger.info('Executing scheduled task', task: task[0..100])
              result = @executor.execute(task)
              preview = result[0..200]
              preview += '...' if result.length > 200
              logger.info('Task completed', result_preview: preview)
            end
          end
        end
      end

      # Setup default daily schedule
      #
      # @return [void]
      def setup_default_schedule
        instructions = @agent.config.dig('agent', 'instructions') ||
                       'Check for updates and report status'
        agent_name = @agent.config.dig('agent', 'name')
        cron = '0 6 * * *'

        logger.info('Setting up default schedule', cron: cron,
                                                   instructions: instructions[0..100])

        @rufus_scheduler.cron(cron) do
          with_span('agent.scheduler.execute', attributes: {
                      'scheduler.cron_expression' => cron,
                      'agent.name' => agent_name,
                      'scheduler.task_type' => 'default'
                    }) do
            logger.timed('Daily task execution') do
              logger.info('Executing daily task')
              result = @executor.execute(instructions)
              preview = result[0..200]
              preview += '...' if result.length > 200
              logger.info('Daily task completed', result_preview: preview)
            end
          end
        end

        logger.info('Scheduled: Daily at 6:00 AM')
      end
    end
  end
end
