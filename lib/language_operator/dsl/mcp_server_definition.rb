# frozen_string_literal: true

require_relative 'tool_definition'

module LanguageOperator
  module Dsl
    # MCP server definition for agents
    #
    # Allows agents to expose their own tools via the MCP protocol.
    # Tools defined here can be called by other agents or MCP clients.
    #
    # @example Define tools in an agent
    #   agent "data-processor" do
    #     as_mcp_server do
    #       tool "process_csv" do
    #         description "Process CSV data"
    #         parameter :url do
    #           type :string
    #           required true
    #         end
    #         execute do |params|
    #           # Processing logic
    #         end
    #       end
    #     end
    #   end
    class McpServerDefinition
      attr_reader :tools, :server_name

      def initialize(agent_name)
        @agent_name = agent_name
        @server_name = "#{agent_name}-mcp"
        @tools = {}
      end

      # Define a tool that this agent exposes
      #
      # @param name [String] Tool name
      # @yield Tool definition block
      # @return [ToolDefinition] The tool definition
      def tool(name, &block)
        tool_def = ToolDefinition.new(name)
        tool_def.instance_eval(&block) if block
        @tools[name] = tool_def
        tool_def
      end

      # Set custom server name
      #
      # @param name [String] Server name
      # @return [String] Current server name
      def name(name = nil)
        return @server_name if name.nil?

        @server_name = name
      end

      # Get all tool definitions
      #
      # @return [Array<ToolDefinition>] Array of tool definitions
      def all_tools
        @tools.values
      end

      # Check if any tools are defined
      #
      # @return [Boolean] True if tools are defined
      def tools?
        !@tools.empty?
      end
    end
  end
end
