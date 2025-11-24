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
      # @raise [PathTraversalError] When the file path attempts path traversal
      # @raise [FileNotFoundError] When the file doesn't exist
      # @raise [FilePermissionError] When the file can't be read due to permissions
      # @raise [FileSyntaxError] When the file contains invalid Ruby syntax
      #
      # @example
      #   LanguageOperator::Dsl.load_file("mcp/tools.rb")
      def load_file(file_path)
        # Validate file path to prevent path traversal attacks
        validated_path = validate_file_path!(file_path, context: 'tool definition file loading')

        # Check if file exists
        raise FileNotFoundError, Errors.file_not_found(file_path, 'tool definition file') unless File.exist?(validated_path)

        # Attempt to read the file
        begin
          code = File.read(validated_path)
        rescue Errno::EACCES
          raise FilePermissionError, Errors.file_permission_denied(file_path, 'tool definition file')
        rescue Errno::EISDIR
          raise FileNotFoundError, Errors.file_not_found(file_path, 'tool definition file')
        rescue SystemCallError => e
          raise FileLoadError, "Error reading tool definition file '#{file_path}': #{e.message}"
        end

        context = Context.new(registry)

        # Execute in sandbox with validation
        begin
          executor = Agent::Safety::SafeExecutor.new(context)
          executor.eval(code, validated_path)
        rescue SyntaxError => e
          raise FileSyntaxError, Errors.file_syntax_error(file_path, e.message, 'tool definition file')
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
      # @raise [PathTraversalError] When the file path attempts path traversal
      # @raise [FileNotFoundError] When the file doesn't exist
      # @raise [FilePermissionError] When the file can't be read due to permissions
      # @raise [FileSyntaxError] When the file contains invalid Ruby syntax
      #
      # @example
      #   LanguageOperator::Dsl.load_agent_file("agents/news-summarizer.rb")
      def load_agent_file(file_path)
        # Validate file path to prevent path traversal attacks
        validated_path = validate_file_path!(file_path, context: 'agent definition file loading')

        # Check if file exists
        raise FileNotFoundError, Errors.file_not_found(file_path, 'agent definition file') unless File.exist?(validated_path)

        # Attempt to read the file
        begin
          code = File.read(validated_path)
        rescue Errno::EACCES
          raise FilePermissionError, Errors.file_permission_denied(file_path, 'agent definition file')
        rescue Errno::EISDIR
          raise FileNotFoundError, Errors.file_not_found(file_path, 'agent definition file')
        rescue SystemCallError => e
          raise FileLoadError, "Error reading agent definition file '#{file_path}': #{e.message}"
        end

        context = AgentContext.new(agent_registry)

        # Execute in sandbox with validation
        begin
          executor = Agent::Safety::SafeExecutor.new(context)
          executor.eval(code, validated_path)
        rescue SyntaxError => e
          raise FileSyntaxError, Errors.file_syntax_error(file_path, e.message, 'agent definition file')
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

      private

      # Validate file path to prevent path traversal attacks
      #
      # @param file_path [String] The file path to validate
      # @param context [String] Context for error messages
      # @return [String] The validated and resolved absolute path
      # @raise [PathTraversalError] When path traversal is detected
      def validate_file_path!(file_path, context: 'file loading')
        # Check for suspicious patterns before path resolution
        raise PathTraversalError, Errors.path_traversal_blocked(context) if contains_path_traversal_patterns?(file_path)

        # Resolve the path to handle relative paths and symlinks
        begin
          resolved_path = File.expand_path(file_path)
        rescue ArgumentError => e
          raise PathTraversalError, "Invalid file path during #{context}: #{e.message}"
        end

        # Get allowed base directories
        allowed_bases = get_allowed_base_paths

        # Check if resolved path is within any allowed base directory
        raise PathTraversalError, Errors.path_traversal_blocked(context) unless allowed_bases.any? { |base| path_within_base?(resolved_path, base) }

        resolved_path
      end

      # Check for common path traversal patterns in the raw path
      #
      # @param file_path [String] The file path to check
      # @return [Boolean] True if suspicious patterns are detected
      def contains_path_traversal_patterns?(file_path)
        # List of suspicious patterns that indicate path traversal attempts
        # Focus on actual traversal patterns, not just any relative path
        patterns = [
          /\.\./, # Parent directory references (classic traversal)
          /\x00/, # Null byte injection
          /%2e%2e/i,                # URL-encoded parent directory
          /%2f/i,                   # URL-encoded path separator
          /%5c/i,                   # URL-encoded backslash
          /\\+\.\./,                # Windows-style parent directory with backslashes
          %r{/\.\.+},                # Multiple dots after slash
          %r{\.\.[/\\]}              # Parent directory followed by path separator
        ]

        patterns.any? { |pattern| file_path.match?(pattern) }
      end

      # Get list of allowed base directories for file operations
      #
      # @return [Array<String>] List of allowed base directory paths
      def get_allowed_base_paths
        # Start with current working directory
        allowed_paths = [File.expand_path('.')]

        # Add paths from environment variable if set
        if ENV['LANGOP_ALLOWED_PATHS']
          custom_paths = ENV['LANGOP_ALLOWED_PATHS'].split(':').map { |path| File.expand_path(path.strip) }
          allowed_paths.concat(custom_paths)
        end

        # Add common subdirectories for typical usage patterns
        %w[agents tools examples].each do |subdir|
          subdir_path = File.expand_path(subdir)
          allowed_paths << subdir_path if Dir.exist?(subdir_path)
        end

        # In test environment, be more permissive (allow /tmp and similar)
        if defined?(RSpec) || ENV['RAILS_ENV'] == 'test' || ENV['RACK_ENV'] == 'test'
          allowed_paths.concat([
            '/tmp',
            File.expand_path('spec'),
            File.expand_path('test')
          ].map { |path| File.expand_path(path) })
        end

        allowed_paths.uniq
      end

      # Check if a resolved path is within an allowed base directory
      #
      # @param resolved_path [String] The resolved absolute path to check
      # @param base_path [String] The base directory path
      # @return [Boolean] True if path is within the base directory
      def path_within_base?(resolved_path, base_path)
        # Ensure base path ends with separator for accurate prefix matching
        normalized_base = File.join(base_path, '')

        # Allow exact matches or paths that start with the base directory
        resolved_path == base_path || resolved_path.start_with?(normalized_base)
      end
    end
  end
end
