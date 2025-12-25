# frozen_string_literal: true

require_relative '../client'
require_relative '../constants'
require_relative '../kubernetes/client'
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

      attr_reader :workspace_path, :mode, :kubernetes_client

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
        @mode = agent_mode_with_default
        @executor = nil

        # Initialize Kubernetes client for event emission (only in K8s environments)
        @kubernetes_client = begin
          LanguageOperator::Kubernetes::Client.instance if ENV.fetch('KUBERNETES_SERVICE_HOST', nil)
        rescue StandardError => e
          logger.warn('Failed to initialize Kubernetes client', error: e.message)
          nil
        end
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

      # Run in scheduled mode (standby - waits for HTTP triggers)
      #
      # @return [void]
      def run_scheduled
        logger.info('Agent running in scheduled mode (standby) - waiting for HTTP triggers')

        require_relative 'web_server'
        @web_server = WebServer.new(self)
        @web_server.register_execute_endpoint(self, nil)
        @web_server.start
      end

      # Run in reactive mode (standby - HTTP server with execute endpoint)
      #
      # @return [void]
      def run_reactive
        logger.info('Agent running in reactive mode (standby) - web server only')

        require_relative 'web_server'
        @web_server = WebServer.new(self)
        @web_server.register_execute_endpoint(self, nil) # Enable /api/v1/execute endpoint
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

      # Get AGENT_MODE with fallback to default, handling empty/whitespace values
      #
      # @return [String] The agent mode to use
      def agent_mode_with_default
        mode = ENV.fetch('AGENT_MODE', nil)
        return 'autonomous' if mode.nil? || mode.strip.empty?

        mode
      end
    end
  end
end
