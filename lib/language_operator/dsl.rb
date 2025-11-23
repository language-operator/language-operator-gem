# frozen_string_literal: true

require_relative 'version'
require_relative 'dsl/tool_definition'
require_relative 'dsl/parameter_definition'
require_relative 'dsl/registry'
require_relative 'dsl/adapter'
require_relative 'dsl/config'
require_relative 'dsl/helpers'
require_relative 'dsl/http'
require_relative 'dsl/shell'
require_relative 'dsl/context'
require_relative 'dsl/execution_context'
require_relative 'dsl/agent_definition'
require_relative 'dsl/agent_context'
require_relative 'dsl/schema'
require_relative 'agent/safety/ast_validator'
require_relative 'agent/safety/safe_executor'

module LanguageOperator
  # DSL for defining MCP tools and autonomous agents
  #
  # Provides a clean, Ruby-like DSL for defining tools that can be served
  # via the Model Context Protocol (MCP) and agents that can execute autonomously.
  #
  # @example Define a tool
  #   LanguageOperator::Dsl.define do
  #     tool "greet" do
  #       description "Greet a user by name"
  #
  #       parameter :name do
  #         type :string
  #         required true
  #         description "Name to greet"
  #       end
  #
  #       execute do |params|
  #         "Hello, #{params['name']}!"
  #       end
  #     end
  #   end
  #
  # @example Access tools
  #   registry = LanguageOperator::Dsl.registry
  #   tool = registry.get("greet")
  #   result = tool.call({"name" => "Alice"})
  module Dsl
    class << self
      # Global registry for tools
      #
      # @return [Registry] The global tool registry
      def registry
        @registry ||= Registry.new
      end

      # Global registry for agents
      #
      # @return [AgentRegistry] The global agent registry
      def agent_registry
        @agent_registry ||= AgentRegistry.new
      end

      # Define tools using the DSL
      #
      # @yield Block containing tool definitions
      # @return [Registry] The global registry with defined tools
      #
      # @example
      #   LanguageOperator::Dsl.define do
      #     tool "example" do
      #       # ...
      #     end
      #   end
      def define(&)
        context = Context.new(registry)
        context.instance_eval(&)
        registry
      end

      # Define agents using the DSL
      #
      # @yield Block containing agent definitions
      # @return [AgentRegistry] The global agent registry
      #
      # @example
      #   LanguageOperator::Dsl.define_agents do
      #     agent "news-summarizer" do
      #       # ...
      #     end
      #   end
      def define_agents(&)
        context = AgentContext.new(agent_registry)
        context.instance_eval(&)
        agent_registry
      end

      # Load tools from a file
      #
      # @param file_path [String] Path to the tool definition file
      # @return [Registry] The global registry with loaded tools
      # @raise [FileNotFoundError] When the file doesn't exist
      # @raise [FilePermissionError] When the file can't be read due to permissions
      # @raise [FileSyntaxError] When the file contains invalid Ruby syntax
      #
      # @example
      #   LanguageOperator::Dsl.load_file("mcp/tools.rb")
      def load_file(file_path)
        # Check if file exists
        unless File.exist?(file_path)
          raise FileNotFoundError, Errors.file_not_found(file_path, "tool definition file")
        end

        # Attempt to read the file
        begin
          code = File.read(file_path)
        rescue Errno::EACCES
          raise FilePermissionError, Errors.file_permission_denied(file_path, "tool definition file")
        rescue Errno::EISDIR
          raise FileNotFoundError, Errors.file_not_found(file_path, "tool definition file")
        rescue SystemCallError => e
          raise FileLoadError, "Error reading tool definition file '#{file_path}': #{e.message}"
        end

        context = Context.new(registry)

        # Execute in sandbox with validation
        begin
          executor = Agent::Safety::SafeExecutor.new(context)
          executor.eval(code, file_path)
        rescue SyntaxError => e
          raise FileSyntaxError, Errors.file_syntax_error(file_path, e.message, "tool definition file")
        rescue StandardError => e
          # Re-raise with additional context for other execution errors
          raise FileLoadError, "Error executing tool definition file '#{file_path}': #{e.message}"
        end

        registry
      end

      # Load agents from a file
      #
      # @param file_path [String] Path to the agent definition file
      # @return [AgentRegistry] The global agent registry
      # @raise [FileNotFoundError] When the file doesn't exist
      # @raise [FilePermissionError] When the file can't be read due to permissions
      # @raise [FileSyntaxError] When the file contains invalid Ruby syntax
      #
      # @example
      #   LanguageOperator::Dsl.load_agent_file("agents/news-summarizer.rb")
      def load_agent_file(file_path)
        # Check if file exists
        unless File.exist?(file_path)
          raise FileNotFoundError, Errors.file_not_found(file_path, "agent definition file")
        end

        # Attempt to read the file
        begin
          code = File.read(file_path)
        rescue Errno::EACCES
          raise FilePermissionError, Errors.file_permission_denied(file_path, "agent definition file")
        rescue Errno::EISDIR
          raise FileNotFoundError, Errors.file_not_found(file_path, "agent definition file")
        rescue SystemCallError => e
          raise FileLoadError, "Error reading agent definition file '#{file_path}': #{e.message}"
        end

        context = AgentContext.new(agent_registry)

        # Execute in sandbox with validation
        begin
          executor = Agent::Safety::SafeExecutor.new(context)
          executor.eval(code, file_path)
        rescue SyntaxError => e
          raise FileSyntaxError, Errors.file_syntax_error(file_path, e.message, "agent definition file")
        rescue StandardError => e
          # Re-raise with additional context for other execution errors
          raise FileLoadError, "Error executing agent definition file '#{file_path}': #{e.message}"
        end

        agent_registry
      end

      # Clear all defined tools
      #
      # @return [void]
      def clear!
        registry.clear
      end

      # Clear all defined agents
      #
      # @return [void]
      def clear_agents!
        agent_registry.clear
      end

      # Create an MCP server from the defined tools
      #
      # @param server_name [String] Name of the MCP server
      # @param server_context [Hash] Additional context for the server
      # @return [MCP::Server] The MCP server instance
      #
      # @example
      #   server = LanguageOperator::Dsl.create_server(server_name: "my-tools")
      def create_server(server_name: 'langop-tools', server_context: {})
        Adapter.create_mcp_server(registry, server_name: server_name, server_context: server_context)
      end
    end
  end
end
