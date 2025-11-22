# frozen_string_literal: true

require 'parser/current'
require 'set'

module LanguageOperator
  module Learning
    # Semantic validator for generated task code
    #
    # Validates that generated code:
    # - Uses only methods available in TaskExecutor context
    # - References tools that exist in the agent's MCP servers
    # - Follows DSL conventions
    class SemanticValidator
      # Methods available in TaskExecutor execution context
      AVAILABLE_METHODS = %w[
        execute_tool
        execute_task
        execute_llm
        execute_parallel
        logger
      ].freeze

      # Initialize validator
      #
      # @param agent_definition [Dsl::AgentDefinition, nil] Agent definition for tool validation
      # @param logger [Logger, nil] Logger instance
      def initialize(agent_definition: nil, logger: nil)
        @agent_definition = agent_definition
        @logger = logger || ::Logger.new($stdout, level: ::Logger::WARN)
      end

      # Validate generated task code
      #
      # @param code [String] Ruby code to validate
      # @param task_definition [Dsl::TaskDefinition, nil] Task definition for schema validation
      # @return [Hash] Validation result
      def validate(code:, task_definition: nil)
        violations = []

        # Parse the code into AST
        begin
          ast = Parser::CurrentRuby.parse(code)
        rescue Parser::SyntaxError => e
          return {
            valid: false,
            violations: [{ type: :syntax_error, message: "Syntax error: #{e.message}" }]
          }
        end

        # Check method calls
        violations.concat(check_method_calls(ast))

        # Check tool references if agent definition available
        violations.concat(check_tool_references(ast)) if @agent_definition

        # Check output schema compliance if task definition available
        violations.concat(check_output_schema(ast, task_definition)) if task_definition

        {
          valid: violations.empty?,
          violations: violations
        }
      end

      private

      # Check that all method calls use available methods
      def check_method_calls(node, local_vars = Set.new([:inputs]))
        violations = []
        return violations unless node.is_a?(Parser::AST::Node)

        # Track local variables introduced by this node
        new_locals = local_vars.dup

        # Add block parameters and local variable assignments to tracking
        case node.type
        when :lvasgn
          # Local variable assignment: var_name = value
          var_name = node.children[0]
          new_locals.add(var_name)
        when :block
          # Block with parameters: do |param1, param2|
          # The second child is the args node
          args_node = node.children[1]
          if args_node && args_node.type == :args
            args_node.children.each do |arg|
              new_locals.add(arg.children[0]) if arg.type == :arg
            end
          end
        end

        # Check if this node is a method send
        if node.type == :send
          receiver, method_name, * = node.children

          # Only check methods called without explicit receiver (i.e., context methods)
          # Exclude local variables and block parameters (including 'inputs' which is always available)
          # Allow Ruby built-in methods and common operations
          if receiver.nil? &&
             !new_locals.include?(method_name) &&
             !AVAILABLE_METHODS.include?(method_name.to_s) &&
             !ruby_builtin_method?(method_name)
            violations << {
              type: :unknown_method,
              message: "Unknown method '#{method_name}' - not available in TaskExecutor context",
              method: method_name.to_s
            }
          end
        end

        # Recursively check children with updated local vars
        node.children.each do |child|
          violations.concat(check_method_calls(child, new_locals)) if child.is_a?(Parser::AST::Node)
        end

        violations
      end

      # Check that tool references exist in agent's MCP servers
      def check_tool_references(node)
        violations = []
        return violations unless node.is_a?(Parser::AST::Node)

        # Check for execute_tool calls
        if node.type == :send && node.children[1] == :execute_tool
          tool_name_node = node.children[2]

          # Extract tool name (should be a string literal)
          tool_name = if tool_name_node&.type == :str
                        tool_name_node.children[0]
                      elsif tool_name_node&.type == :sym
                        tool_name_node.children[0].to_s
                      end

          if tool_name
            # Check if tool exists (simplified - would need actual tool list from agent)
            @logger.debug("Found execute_tool call for '#{tool_name}'")
            # TODO: Validate against actual tool list from @agent_definition
          end
        end

        # Recursively check children
        node.children.each do |child|
          violations.concat(check_tool_references(child)) if child.is_a?(Parser::AST::Node)
        end

        violations
      end

      # Check that code returns hash matching output schema
      def check_output_schema(node, task_definition)
        violations = []
        return violations unless node.is_a?(Parser::AST::Node)

        # Find return statements or last expression
        # This is a simplified check - full implementation would be more complex
        expected_keys = task_definition.outputs&.keys || []

        if expected_keys.any?
          @logger.debug("Expected output keys: #{expected_keys.inspect}")
          # TODO: Validate that code returns hash with these keys
        end

        violations
      end

      # Check if method is a Ruby built-in
      def ruby_builtin_method?(method_name)
        # Common Ruby methods that are safe
        ruby_builtins = %w[
          puts print p raise throw catch
          map select reject each each_with_index
          first last size length empty? nil? any? all?
          keys values merge merge! dig fetch
          to_s to_i to_f to_a to_h to_sym
          strip gsub sub split join
          upcase downcase capitalize
          include? start_with? end_with? match?
          + - * / % ** == != < > <= >= <=>
        ]

        ruby_builtins.include?(method_name.to_s)
      end
    end
  end
end
