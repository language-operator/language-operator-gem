# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module System
        module Helpers
          # Template validation utilities
          module TemplateValidator
            # Validate template syntax and structure
            def validate_template_content(content, type)
              errors = []
              warnings = []

              # Check for required placeholders based on type
              required_placeholders = if type == 'agent'
                                        %w[
                                          Instructions ToolsList ModelsList AgentName TemporalIntent
                                        ]
                                      else
                                        %w[
                                          PersonaName PersonaDescription PersonaSystemPrompt
                                          AgentInstructions AgentTools
                                        ]
                                      end

              required_placeholders.each do |placeholder|
                errors << "Missing required placeholder: {{.#{placeholder}}}" unless content.include?("{{.#{placeholder}}}")
              end

              # Check for balanced braces
              open_braces = content.scan(/{{/).count
              close_braces = content.scan(/}}/).count
              errors << "Unbalanced template braces ({{ vs }}): #{open_braces} open, #{close_braces} close" if open_braces != close_braces

              # Extract and validate Ruby code blocks
              code_examples = extract_code_examples(content)
              code_examples.each do |example|
                code_result = validate_code_against_schema(example[:code])
                unless code_result[:valid]
                  code_result[:errors].each do |err|
                    # Adjust line numbers to be relative to template
                    line = example[:start_line] + (err[:location] || 0)
                    errors << "Line #{line}: #{err[:message]}"
                  end
                end
                code_result[:warnings].each do |warn|
                  line = example[:start_line] + (warn[:location] || 0)
                  warnings << "Line #{line}: #{warn[:message]}"
                end
              end

              # Extract method calls and check if they're in the safe list
              method_calls = extract_method_calls(content)
              safe_methods = Dsl::Schema.safe_agent_methods +
                             Dsl::Schema.safe_tool_methods +
                             Dsl::Schema.safe_helper_methods
              method_calls.each do |method|
                next if safe_methods.include?(method)

                warnings << "Method '#{method}' not in safe methods list (may be valid Ruby builtin)"
              end

              {
                valid: errors.empty?,
                errors: errors,
                warnings: warnings
              }
            end

            # Extract Ruby code examples from template
            # Returns array of {code: String, start_line: Integer}
            def extract_code_examples(template)
              examples = []
              lines = template.split("\n")
              in_code_block = false
              current_code = []
              start_line = 0

              lines.each_with_index do |line, idx|
                if line.strip.start_with?('```ruby')
                  in_code_block = true
                  start_line = idx + 2 # idx is 0-based, we want line number (1-based) of first code line
                  current_code = []
                elsif line.strip == '```' && in_code_block
                  in_code_block = false
                  examples << { code: current_code.join("\n"), start_line: start_line } unless current_code.empty?
                elsif in_code_block
                  current_code << line
                end
              end

              examples
            end

            # Extract method calls from template code
            # Returns array of method name strings
            def extract_method_calls(template)
              require 'prism'

              method_calls = []
              code_examples = extract_code_examples(template)

              code_examples.each do |example|
                # Parse the code to find method calls
                result = Prism.parse(example[:code])

                # Walk the AST to find method calls
                extract_methods_from_ast(result.value, method_calls) if result.success?
              rescue Prism::ParseError
                # Skip code with syntax errors - they'll be caught by validate_code_against_schema
                next
              end

              method_calls.uniq
            end

            # Recursively extract method names from AST
            def extract_methods_from_ast(node, methods)
              return unless node

              methods << node.name.to_s if node.is_a?(Prism::CallNode)

              node.compact_child_nodes.each do |child|
                extract_methods_from_ast(child, methods)
              end
            end

            # Validate Ruby code against DSL schema
            # Returns {valid: Boolean, errors: Array<Hash>, warnings: Array<Hash>}
            def validate_code_against_schema(code)
              require 'language_operator/agent/safety/ast_validator'

              validator = LanguageOperator::Agent::Safety::ASTValidator.new
              violations = validator.validate(code, '(template)')

              errors = []
              warnings = []

              violations.each do |violation|
                case violation[:type]
                when :syntax_error
                  errors << {
                    type: :syntax_error,
                    location: 0,
                    message: violation[:message]
                  }
                when :dangerous_method, :dangerous_constant, :dangerous_constant_access, :dangerous_global, :backtick_execution
                  errors << {
                    type: violation[:type],
                    location: violation[:location],
                    message: violation[:message]
                  }
                else
                  warnings << {
                    type: violation[:type],
                    location: violation[:location] || 0,
                    message: violation[:message]
                  }
                end
              end

              {
                valid: errors.empty?,
                errors: errors,
                warnings: warnings
              }
            end
          end
        end
      end
    end
  end
end
