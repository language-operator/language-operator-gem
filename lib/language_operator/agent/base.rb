# frozen_string_literal: true

require_relative '../client'
require_relative '../constants'
require_relative 'telemetry'
require_relative 'instrumentation'

module LanguageOperator
  module Agent
    # Base Agent Class
    #
    # Extends LanguageOperator::Client::Base with agent-specific functionality including:
    # - Workspace integration
    # - Goal-directed execution
    # - Autonomous operation modes
    #
    # @example Basic agent
    #   agent = LanguageOperator::Agent::Base.new(config)
    #   agent.connect!
    #   agent.execute_goal("Complete the task")
    class Base < LanguageOperator::Client::Base
      include Instrumentation

      attr_reader :workspace_path, :mode

      # Initialize the agent
      #
      # @param config [Hash] Configuration hash
      def initialize(config)
        super

        # Log version
        logger.info "Language Operator v#{LanguageOperator::VERSION}"

        # Initialize OpenTelemetry
        LanguageOperator::Agent::Telemetry.configure
        otel_enabled = !ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', nil).nil?
        logger.info "OpenTelemetry #{otel_enabled ? 'enabled' : 'disabled'}"

        @workspace_path = ENV.fetch('WORKSPACE_PATH', '/workspace')
        @mode = ENV.fetch('AGENT_MODE', 'autonomous')
        @executor = nil
      end

      # Run the agent in its configured mode
      #
      # @return [void]
      def run
        # Normalize mode to canonical form
        normalized_mode = Constants.normalize_mode(@mode)

        with_span('agent.run', attributes: {
                    'agent.name' => ENV.fetch('AGENT_NAME', nil),
                    'agent.mode' => normalized_mode,
                    'agent.workspace_available' => workspace_available?
                  }) do
          connect!

          case normalized_mode
          when 'autonomous'
            run_autonomous
          when 'scheduled'
            run_scheduled
          when 'reactive'
            run_reactive
          else
            raise "Unknown agent mode: #{normalized_mode}"
          end
        ensure
          # Flush telemetry for short-lived processes (scheduled mode)
          flush_telemetry if normalized_mode == 'scheduled'
        end
      end

      # Execute a single goal
      #
      # @param goal [String] The goal to achieve
      # @return [String] The result
      def execute_goal(goal)
        @executor ||= Executor.new(self)
        @executor.execute(goal)
      end

      # Check if workspace is available
      #
      # @return [Boolean]
      def workspace_available?
        File.directory?(@workspace_path) && File.writable?(@workspace_path)
      end

      private

      # Run in autonomous mode
      #
      # @return [void]
      def run_autonomous
        @executor = Executor.new(self)
        @executor.run_loop
      end

      # Run in scheduled mode (execute once - Kubernetes CronJob handles scheduling)
      #
      # @return [void]
      def run_scheduled
        logger.info('Agent running in scheduled mode without definition - executing goal once')

        goal = ENV.fetch('AGENT_INSTRUCTIONS', 'Complete the assigned task')
        execute_goal(goal)

        logger.info('Scheduled execution completed - exiting')
      end

      # Run in reactive mode (HTTP server)
      #
      # @return [void]
      def run_reactive
        require_relative 'web_server'
        @web_server = WebServer.new(self)
        @web_server.start
      end

      # Flush OpenTelemetry spans to ensure they're exported before process exits
      #
      # Critical for short-lived processes (CronJobs) that exit quickly.
      # BatchSpanProcessor buffers spans and exports periodically, so without
      # explicit flushing, spans may be lost when the process terminates.
      #
      # @return [void]
      def flush_telemetry
        return unless ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', nil)

        OpenTelemetry.tracer_provider.force_flush
        logger.info('OpenTelemetry spans flushed to OTLP endpoint')
      rescue StandardError => e
        logger.warn("Failed to flush telemetry: #{e.message}")
      end
    end
  end
end
