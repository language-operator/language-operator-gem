# frozen_string_literal: true

require_relative '../loggable'

module LanguageOperator
  module Agent
    # Agent Metadata Collector
    #
    # Collects runtime and configuration metadata about an agent for use in
    # persona-driven system prompts and conversation context.
    #
    # Provides information about:
    # - Agent identity (name, description, persona)
    # - Runtime environment (cluster, namespace, mode)
    # - Operational state (uptime, workspace, status)
    # - Configuration details (capabilities, constraints)
    #
    # @example
    #   collector = MetadataCollector.new(agent)
    #   metadata = collector.collect
    #   puts metadata[:identity][:name]  # => "my-agent"
    #   puts metadata[:runtime][:uptime] # => "2h 15m"
    class MetadataCollector
      include LanguageOperator::Loggable

      attr_reader :agent, :start_time

      # Initialize metadata collector
      #
      # @param agent [LanguageOperator::Agent::Base] The agent instance
      def initialize(agent)
        @agent = agent
        @start_time = Time.now
        @logger = logger
      end

      # Collect all available metadata
      #
      # @return [Hash] Complete metadata structure
      def collect
        {
          identity: collect_identity,
          runtime: collect_runtime,
          environment: collect_environment,
          operational: collect_operational,
          capabilities: collect_capabilities
        }
      end

      # Collect basic identity information
      #
      # @return [Hash] Identity metadata
      def collect_identity
        config = @agent.config || {}
        agent_config = config.dig('agent') || {}

        {
          name: ENV.fetch('AGENT_NAME', agent_config['name'] || 'unknown'),
          description: agent_config['instructions'] || agent_config['description'] || 'AI Agent',
          persona: agent_config['persona'] || ENV.fetch('PERSONA_NAME', nil),
          mode: @agent.mode || 'unknown',
          version: LanguageOperator::VERSION
        }
      end

      # Collect runtime environment information
      #
      # @return [Hash] Runtime metadata
      def collect_runtime
        {
          uptime: calculate_uptime,
          started_at: @start_time.iso8601,
          process_id: Process.pid,
          workspace_available: @agent.workspace_available?,
          mcp_servers_connected: @agent.respond_to?(:servers_info) ? @agent.servers_info.length : 0
        }
      end

      # Collect deployment environment information
      #
      # @return [Hash] Environment metadata
      def collect_environment
        {
          cluster: ENV.fetch('AGENT_CLUSTER', nil),
          namespace: ENV.fetch('AGENT_NAMESPACE', ENV.fetch('KUBERNETES_NAMESPACE', nil)),
          workspace_path: @agent.workspace_path,
          kubernetes_enabled: !ENV.fetch('KUBERNETES_SERVICE_HOST', nil).nil?,
          telemetry_enabled: !ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', nil).nil?
        }
      end

      # Collect operational state information
      #
      # @return [Hash] Operational metadata
      def collect_operational
        status = determine_agent_status

        {
          status: status,
          ready: status == 'ready',
          mode: @agent.mode,
          workspace: {
            path: @agent.workspace_path,
            available: @agent.workspace_available?,
            writable: workspace_writable?
          }
        }
      end

      # Collect agent capabilities and constraints
      #
      # @return [Hash] Capabilities metadata
      def collect_capabilities
        config = @agent.config || {}
        
        # Extract MCP server tools if available
        tools = []
        if @agent.respond_to?(:servers_info)
          @agent.servers_info.each do |server|
            tools << {
              server: server[:name],
              tool_count: server[:tool_count] || 0
            }
          end
        end

        # Extract constraints if configured
        constraints = config.dig('constraints') || {}

        {
          tools: tools,
          total_tools: tools.sum { |t| t[:tool_count] },
          constraints: constraints.empty? ? nil : constraints,
          llm_provider: config.dig('llm', 'provider') || ENV.fetch('LLM_PROVIDER', 'unknown'),
          llm_model: config.dig('llm', 'model') || ENV.fetch('MODEL', 'unknown')
        }
      end

      # Get formatted summary suitable for system prompts
      #
      # @return [Hash] Formatted summary for prompt injection
      def summary_for_prompt
        metadata = collect
        identity = metadata[:identity]
        runtime = metadata[:runtime]
        environment = metadata[:environment]
        operational = metadata[:operational]
        capabilities = metadata[:capabilities]

        {
          agent_name: identity[:name],
          agent_description: identity[:description],
          agent_mode: identity[:mode],
          uptime: runtime[:uptime],
          cluster: environment[:cluster],
          namespace: environment[:namespace],
          status: operational[:status],
          workspace_available: operational[:ready],
          tool_count: capabilities[:total_tools],
          llm_model: capabilities[:llm_model]
        }
      end

      private

      def logger_component
        'Agent::MetadataCollector'
      end

      # Calculate human-readable uptime
      #
      # @return [String] Formatted uptime string
      def calculate_uptime
        seconds = Time.now - @start_time
        return 'just started' if seconds < 60

        minutes = (seconds / 60).floor
        hours = (minutes / 60).floor
        days = (hours / 24).floor

        if days > 0
          "#{days}d #{hours % 24}h #{minutes % 60}m"
        elsif hours > 0
          "#{hours}h #{minutes % 60}m"
        else
          "#{minutes}m"
        end
      end

      # Determine current agent status
      #
      # @return [String] Status string
      def determine_agent_status
        return 'not_ready' unless @agent.workspace_available?
        return 'starting' if calculate_uptime == 'just started'
        
        # Check if agent is connected and functional
        if @agent.respond_to?(:servers_info) && @agent.servers_info.any?
          'ready'
        elsif @agent.respond_to?(:servers_info) && @agent.servers_info.empty?
          'ready_no_tools'
        else
          'ready'
        end
      end

      # Check if workspace is writable
      #
      # @return [Boolean] True if workspace is writable
      def workspace_writable?
        return false unless @agent.workspace_available?
        
        test_file = File.join(@agent.workspace_path, '.write_test')
        File.write(test_file, 'test')
        File.delete(test_file)
        true
      rescue StandardError
        false
      end
    end
  end
end