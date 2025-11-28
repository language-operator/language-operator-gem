# frozen_string_literal: true

require 'prism'

module LanguageOperator
  module Agent
    module Safety
      # Validates synthesized Ruby code for security before execution
      # Performs static analysis to detect dangerous method calls
      #
      # Supports DSL v1 (task/main model) and validates both neural and symbolic
      # task implementations to ensure they use only safe Ruby subset.
      class ASTValidator
        # Gems that are safe to require (allowlist)
        # These are required for agent execution and are safe
        ALLOWED_REQUIRES = %w[
          language_operator
        ].freeze

        # Dangerous methods that should never be called in synthesized code
        DANGEROUS_METHODS = %w[
          system exec spawn fork ` eval instance_eval class_eval module_eval
          require load autoload require_relative
          send __send__ public_send method __method__
          const_set const_get remove_const
          define_method define_singleton_method
          undef_method remove_method alias_method
          exit exit! abort throw
          trap at_exit
          open
        ].freeze

        # Dangerous constants that should not be accessed
        DANGEROUS_CONSTANTS = %w[
          File Dir IO FileUtils Pathname
          Process Kernel ObjectSpace GC
          Thread Fiber Mutex ConditionVariable
          Socket TCPSocket UDPSocket TCPServer UDPServer
          STDIN STDOUT STDERR
        ].freeze

        # Safe DSL methods that are allowed in agent definitions (DSL v1)
        SAFE_AGENT_METHODS = %w[
          agent description persona schedule objectives objective
          task main execute_task inputs outputs instructions
          constraints budget max_requests rate_limit content_filter
          output mode webhook as_mcp_server as_chat_endpoint
        ].freeze

        # Safe DSL methods for tool definitions
        SAFE_TOOL_METHODS = %w[
          tool description parameter type required default
          execute
        ].freeze

        # Safe helper methods available in execute blocks
        SAFE_HELPER_METHODS = %w[
          HTTP Shell
          validate_url validate_phone validate_email
          env_required env_get
          truncate parse_csv
          error success
          TypeCoercion
        ].freeze

        # Safe Ruby built-in methods and classes
        SAFE_BUILTINS = %w[
          String Array Hash Integer Float Symbol
          puts print p pp warn
          true false nil
          if unless case when then else elsif end
          while until for break next redo retry return
          begin rescue ensure
          lambda proc block_given? yield
          attr_reader attr_writer attr_accessor
          private protected public
          initialize new
        ].freeze

        class SecurityError < StandardError; end

        def initialize
          # Prism doesn't require initialization
        end

        # Validate code and raise SecurityError if dangerous methods found
        # @param code [String] Ruby code to validate
        # @param file_path [String] Path to file (for error messages)
        # @raise [SecurityError] if code contains dangerous methods
        def validate!(code, file_path = '(eval)')
          ast = parse_code(code, file_path)
          return if ast.nil? # Empty code is safe

          violations = scan_ast(ast)

          return if violations.empty?

          raise SecurityError, format_violations(violations, file_path)
        end

        # Validate code and return array of violations (non-raising version)
        # @param code [String] Ruby code to validate
        # @param file_path [String] Path to file (for error messages)
        # @return [Array<Hash>] Array of violation hashes
        def validate(code, file_path = '(eval)')
          begin
            ast = parse_code(code, file_path)
          rescue SecurityError => e
            # Convert SecurityError (which wraps syntax error) to violation
            return [{ type: :syntax_error, message: e.message }]
          end

          return [] if ast.nil?

          scan_ast(ast)
        rescue Prism::ParseError => e
          [{ type: :syntax_error, message: e.message }]
        end

        private

        def parse_code(code, file_path)
          result = Prism.parse(code, filepath: file_path)

          # Prism is forgiving and creates an AST even with some syntax errors
          # We'll allow parsing to proceed and only raise if there are FATAL errors
          # that prevent AST creation entirely
          if result.value.nil?
            errors = result.errors.map(&:message).join('; ')
            raise SecurityError, "Syntax error in #{file_path}: #{errors}"
          end

          result.value
        rescue Prism::ParseError => e
          raise SecurityError, "Syntax error in #{file_path}: #{e.message}"
        end

        def scan_ast(node, violations = [])
          return violations if node.nil?

          # Prism uses different node types
          case node
          when Prism::CallNode
            check_method_call(node, violations)
          when Prism::ConstantReadNode, Prism::ConstantPathNode
            check_constant(node, violations)
          when Prism::GlobalVariableReadNode, Prism::GlobalVariableWriteNode
            check_global_variable(node, violations)
          when Prism::XStringNode
            # Backtick string execution (e.g., `command`)
            violations << {
              type: :backtick_execution,
              location: node.location.start_line,
              message: 'Backtick command execution is not allowed'
            }
          end

          # Recursively scan all child nodes
          node.compact_child_nodes.each do |child|
            scan_ast(child, violations)
          end

          violations
        end

        def check_method_call(node, violations)
          method_str = node.name.to_s

          # Special handling for require - check if it's in the allowlist
          if %w[require require_relative].include?(method_str)
            required_gem = extract_require_argument(node)

            # Allow if in the allowlist
            return if required_gem && ALLOWED_REQUIRES.include?(required_gem)

            # Otherwise, add violation
            violations << {
              type: :dangerous_method,
              method: method_str,
              location: node.location.start_line,
              message: "Dangerous method '#{method_str}' is not allowed"
            }
            return
          end

          # Check for other dangerous methods
          if DANGEROUS_METHODS.include?(method_str)
            violations << {
              type: :dangerous_method,
              method: method_str,
              location: node.location.start_line,
              message: "Dangerous method '#{method_str}' is not allowed"
            }
          end

          # Check for File/Dir/IO operations
          receiver = node.receiver
          if receiver && (receiver.is_a?(Prism::ConstantReadNode) || receiver.is_a?(Prism::ConstantPathNode))
            const_name = receiver.is_a?(Prism::ConstantReadNode) ? receiver.name.to_s : receiver.name
            if DANGEROUS_CONSTANTS.include?(const_name.to_s)
              violations << {
                type: :dangerous_constant,
                constant: const_name.to_s,
                method: method_str,
                location: node.location.start_line,
                message: "Access to #{const_name}.#{method_str} is not allowed"
              }
            end
          end

          # Check for backtick execution (e.g., `command`)
          # Note: backticks are represented as send with method name :`
          return unless method_str == '`'

          violations << {
            type: :backtick_execution,
            location: node.location.start_line,
            message: 'Backtick command execution is not allowed'
          }
        end

        def check_constant(node, violations)
          const_str = if node.is_a?(Prism::ConstantReadNode)
                        node.name.to_s
                      elsif node.is_a?(Prism::ConstantPathNode)
                        # For paths like Foo::Bar, get the last part
                        node.name.to_s
                      else
                        return
                      end

          # Check for dangerous constants being accessed directly
          return unless DANGEROUS_CONSTANTS.include?(const_str)

          violations << {
            type: :dangerous_constant_access,
            constant: const_str,
            location: node.location.start_line,
            message: "Direct access to #{const_str} constant is not allowed"
          }
        end

        def check_global_variable(node, violations)
          var_name = node.name.to_s

          # Block access to dangerous global variables
          dangerous_globals = %w[$0 $PROGRAM_NAME $LOAD_PATH $: $LOADED_FEATURES $"]

          return unless dangerous_globals.include?(var_name)

          violations << {
            type: :dangerous_global,
            variable: var_name,
            location: node.location.start_line,
            message: "Access to global variable #{var_name} is not allowed"
          }
        end

        def extract_require_argument(node)
          # node is a CallNode for require/require_relative
          # We're looking for a string literal argument like 'language_operator' or "language_operator"
          args = node.arguments
          return nil unless args&.arguments&.any?

          arg_node = args.arguments.first
          return nil unless arg_node

          # Check if it's a string literal (StringNode)
          return arg_node.unescaped if arg_node.is_a?(Prism::StringNode)

          # If it's not a string literal (e.g., dynamic require), we can't verify it
          nil
        end

        def format_violations(violations, file_path)
          header = "Security violations detected in #{file_path}:\n\n"

          violation_messages = violations.map do |v|
            "  Line #{v[:location]}: #{v[:message]}"
          end

          footer = "\n\nSynthesized code must only use safe DSL methods and approved helpers."
          footer += "\nSafe methods include: #{SAFE_AGENT_METHODS.join(', ')}, #{SAFE_TOOL_METHODS.join(', ')}"
          footer += "\nSafe helpers include: HTTP.*, Shell.run, validate_*, env_*, TypeCoercion.coerce"

          header + violation_messages.join("\n") + footer
        end
      end
    end
  end
end
