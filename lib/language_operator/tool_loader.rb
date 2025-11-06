# frozen_string_literal: true

require_relative 'dsl'
require 'mcp'

module LanguageOperator
  # Loads tool definitions from Ruby files
  #
  # Scans a directory for Ruby files containing tool definitions and loads them
  # into a registry. Provides hot-reloading capability for development.
  #
  # @example Basic usage
  #   registry = LanguageOperator::Dsl::Registry.new
  #   loader = LanguageOperator::ToolLoader.new(registry, '/mcp/tools')
  #   loader.load_tools
  #   puts "Loaded #{registry.all.length} tools"
  #
  # @example With custom context
  #   loader = LanguageOperator::ToolLoader.new(registry)
  #   loader.load_tools
  #   loader.reload  # Hot reload tools
  #
  # @example Start MCP server
  #   LanguageOperator::ToolLoader.start  # Loads tools and starts MCP server
  class ToolLoader
    # Initialize tool loader
    #
    # @param registry [LanguageOperator::Dsl::Registry] Tool registry
    # @param tools_dir [String] Directory containing tool definition files
    def initialize(registry, tools_dir = '/mcp')
      @registry = registry
      @tools_dir = tools_dir
    end

    # Load all tool files from the tools directory
    #
    # @return [void]
    def load_tools
      @registry.clear

      unless Dir.exist?(@tools_dir)
        puts "Tools directory #{@tools_dir} does not exist. Skipping tool loading."
        return
      end

      tool_files = Dir.glob(File.join(@tools_dir, '**', '*.rb'))

      if tool_files.empty?
        puts "No tool files found in #{@tools_dir}"
        return
      end

      tool_files.each do |file|
        load_tool_file(file)
      end

      puts "Loaded #{@registry.all.length} tools from #{tool_files.length} files"
    end

    # Load a single tool file
    #
    # @param file [String] Path to tool definition file
    # @return [void]
    def load_tool_file(file)
      puts "Loading tools from: #{file}"

      begin
        context = LanguageOperator::Dsl::Context.new(@registry)
        code = File.read(file)
        context.instance_eval(code, file)
      rescue StandardError => e
        warn "Error loading tool file #{file}: #{e.message}"
        warn e.backtrace.join("\n")
      end
    end

    # Reload all tools (hot reload)
    #
    # @return [void]
    def reload
      puts 'Reloading tools...'
      load_tools
    end

    # Start an MCP server with loaded tools
    #
    # This class method creates a registry, loads tools from /mcp directory,
    # wraps them as MCP::Tool classes, and starts an MCP server with stdio transport.
    #
    # @param tools_dir [String] Directory containing tool definition files (default: '/mcp')
    # @param server_name [String] Name of the MCP server (default: 'language-operator-tool')
    # @return [void]
    def self.start(tools_dir: '/mcp', server_name: 'language-operator-tool')
      # Create registry and load tools
      registry = LanguageOperator::Dsl::Registry.new
      loader = new(registry, tools_dir)
      loader.load_tools

      # Convert DSL tools to MCP::Tool classes
      mcp_tools = registry.all.map do |tool_name, tool_def|
        create_mcp_tool(tool_name, tool_def)
      end

      # Create and start MCP server
      server = MCP::Server.new(
        name: server_name,
        tools: mcp_tools
      )

      # Use stdio transport
      transport = MCP::Server::Transports::StdioTransport.new(server)
      puts "Starting MCP server '#{server_name}' with #{mcp_tools.length} tools"
      transport.open
    end

    # Convert a DSL tool definition to an MCP::Tool class
    #
    # @param tool_name [String] Name of the tool
    # @param tool_def [Hash] Tool definition from DSL
    # @return [Class] MCP::Tool subclass
    def self.create_mcp_tool(tool_name, tool_def)
      # Create a dynamic MCP::Tool class
      Class.new(MCP::Tool) do
        description tool_def[:description] || "Tool: #{tool_name}"

        # Build input schema from parameters
        properties = {}
        required_params = []

        tool_def[:parameters]&.each do |param_name, param_def|
          properties[param_name] = {
            type: param_def[:type]&.to_s || 'string',
            description: param_def[:description]
          }
          required_params << param_name if param_def[:required]
        end

        input_schema(
          properties: properties,
          required: required_params
        )

        # Store the execute block
        @execute_block = tool_def[:execute]

        # Define the call method
        define_singleton_method(:call) do |**params|
          # Execute the tool's block
          result = @execute_block.call(params)

          # Return MCP response
          MCP::Tool::Response.new([{
            type: 'text',
            text: result.to_s
          }])
        end
      end
    end
  end
end
