# frozen_string_literal: true

require 'thor'
require 'json'
require 'yaml'
require_relative '../formatters/progress_formatter'
require_relative '../../dsl/schema'

module LanguageOperator
  module CLI
    module Commands
      # System commands for schema introspection and metadata
      class System < Thor
        desc 'schema', 'Export the DSL schema in various formats'
        long_desc <<-DESC
          Export the Language Operator Agent DSL schema in various formats.

          The schema documents all available DSL methods, parameters, validation
          patterns, and structure. Useful for template validation, documentation
          generation, and IDE autocomplete.

          Examples:
            # Export JSON schema (default)
            aictl system schema

            # Export as YAML
            aictl system schema --format yaml

            # Export OpenAPI 3.0 specification
            aictl system schema --format openapi

            # Show schema version only
            aictl system schema --version

            # Save to file
            aictl system schema > schema.json
            aictl system schema --format openapi > openapi.json
        DESC
        option :format, type: :string, default: 'json', desc: 'Output format (json, yaml, openapi)'
        option :version, type: :boolean, default: false, desc: 'Show schema version only'
        def schema
          # Handle version flag
          if options[:version]
            puts Dsl::Schema.version
            return
          end

          # Generate schema based on format
          format = options[:format].downcase
          case format
          when 'json'
            output_json_schema
          when 'yaml'
            output_yaml_schema
          when 'openapi'
            output_openapi_schema
          else
            Formatters::ProgressFormatter.error("Invalid format: #{format}")
            puts
            puts 'Supported formats: json, yaml, openapi'
            exit 1
          end
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to generate schema: #{e.message}")
          exit 1
        end

        no_commands do
          # Output JSON Schema v7
          def output_json_schema
            schema = Dsl::Schema.to_json_schema
            puts JSON.pretty_generate(schema)
          end

          # Output YAML Schema
          def output_yaml_schema
            schema = Dsl::Schema.to_json_schema
            puts YAML.dump(schema.transform_keys(&:to_s))
          end

          # Output OpenAPI 3.0 specification
          def output_openapi_schema
            spec = Dsl::Schema.to_openapi
            puts JSON.pretty_generate(spec)
          end
        end

        desc 'validate_template', 'Validate synthesis template against DSL schema'
        long_desc <<-DESC
          Validate a synthesis template file against the DSL schema.

          Extracts Ruby code examples from the template and validates each example
          against the Language Operator Agent DSL schema. Checks for dangerous
          methods, syntax errors, and compliance with safe coding practices.

          Examples:
            # Validate a custom template file
            aictl system validate_template --template /path/to/template.tmpl

            # Validate the bundled agent template (default)
            aictl system validate_template

            # Validate the bundled persona template
            aictl system validate_template --type persona

            # Verbose output with all violations
            aictl system validate_template --template mytemplate.tmpl --verbose
        DESC
        option :template, type: :string, desc: 'Path to template file (defaults to bundled template)'
        option :type, type: :string, default: 'agent', desc: 'Template type if using bundled template (agent, persona)'
        option :verbose, type: :boolean, default: false, desc: 'Show detailed violation information'
        def validate_template
          # Determine template source
          if options[:template]
            # Load custom template from file
            unless File.exist?(options[:template])
              Formatters::ProgressFormatter.error("Template file not found: #{options[:template]}")
              exit 1
            end
            template_content = File.read(options[:template])
            template_name = File.basename(options[:template])
          else
            # Load bundled template
            template_type = options[:type].downcase
            unless %w[agent persona].include?(template_type)
              Formatters::ProgressFormatter.error("Invalid template type: #{template_type}")
              puts
              puts 'Supported types: agent, persona'
              exit 1
            end
            template_content = load_bundled_template(template_type)
            template_name = "bundled #{template_type} template"
          end

          # Display header
          puts "Validating template: #{template_name}"
          puts '=' * 60
          puts

          # Extract code examples
          code_examples = extract_code_examples(template_content)

          if code_examples.empty?
            Formatters::ProgressFormatter.warn('No Ruby code examples found in template')
            puts
            puts 'Templates should contain Ruby code blocks like:'
            puts '```ruby'
            puts 'agent "my-agent" do'
            puts '  # ...'
            puts 'end'
            puts '```'
            exit 1
          end

          puts "Found #{code_examples.size} code example(s)"
          puts

          # Validate each example
          all_valid = true
          code_examples.each_with_index do |example, idx|
            puts "Example #{idx + 1} (starting at line #{example[:start_line]}):"
            puts '-' * 40

            result = validate_code_against_schema(example[:code])

            if result[:valid] && result[:warnings].empty?
              Formatters::ProgressFormatter.success('Valid - No issues found')
            elsif result[:valid]
              Formatters::ProgressFormatter.success('Valid - With warnings')
              result[:warnings].each do |warn|
                line = example[:start_line] + (warn[:location] || 0)
                puts "  ⚠  Line #{line}: #{warn[:message]}"
              end
            else
              Formatters::ProgressFormatter.error('Invalid - Violations detected')
              result[:errors].each do |err|
                line = example[:start_line] + (err[:location] || 0)
                puts "  ✗ Line #{line}: #{err[:message]}"
                puts "    Type: #{err[:type]}" if options[:verbose]
              end
              all_valid = false
            end

            puts
          end

          # Final summary
          puts '=' * 60
          if all_valid
            Formatters::ProgressFormatter.success('All examples are valid')
            exit 0
          else
            Formatters::ProgressFormatter.error('Validation failed')
            puts
            puts 'Fix the violations above and run validation again.'
            exit 1
          end
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Validation error: #{e.message}")
          puts e.backtrace.first(5).join("\n") if options[:verbose]
          exit 1
        end

        desc 'test-synthesis', 'Test agent synthesis from natural language instructions'
        long_desc <<-DESC
          Test the agent synthesis process by converting natural language instructions
          into Ruby DSL code without creating an actual agent.

          This command helps you validate your instructions and understand how the
          synthesis engine interprets them. Use --dry-run to see the prompt that
          would be sent to the LLM, or run without it to generate actual code.

          Examples:
            # Test with dry-run (show prompt only)
            aictl system test-synthesis --instructions "Monitor GitHub issues daily" --dry-run

            # Generate code from instructions
            aictl system test-synthesis --instructions "Send daily reports to Slack"

            # Specify custom agent name and tools
            aictl system test-synthesis \\
              --instructions "Process webhooks from GitHub" \\
              --agent-name github-processor \\
              --tools github,slack

            # Specify available models
            aictl system test-synthesis \\
              --instructions "Analyze logs every hour" \\
              --models gpt-4,claude-3-5-sonnet
        DESC
        option :instructions, type: :string, required: true, desc: 'Natural language instructions for the agent'
        option :agent_name, type: :string, default: 'test-agent', desc: 'Name for the test agent'
        option :tools, type: :string, desc: 'Comma-separated list of available tools'
        option :models, type: :string, desc: 'Comma-separated list of available models'
        option :dry_run, type: :boolean, default: false, desc: 'Show prompt without calling LLM'
        def test_synthesis
          # Load synthesis template
          template_content = load_bundled_template('agent')

          # Detect temporal intent from instructions
          temporal_intent = detect_temporal_intent(options[:instructions])

          # Prepare template data
          template_data = {
            'Instructions' => options[:instructions],
            'AgentName' => options[:agent_name],
            'ToolsList' => format_tools_list(options[:tools]),
            'ModelsList' => format_models_list(options[:models]),
            'TemporalIntent' => temporal_intent,
            'PersonaSection' => '',
            'ScheduleSection' => temporal_intent == 'scheduled' ? '  schedule "0 */1 * * *"  # Example hourly schedule' : '',
            'ScheduleRules' => temporal_intent == 'scheduled' ? "\n2. Include schedule with cron expression\n3. Set mode to :scheduled\n4. " : "\n2. ",
            'ConstraintsSection' => '',
            'ErrorContext' => nil
          }

          # Render template (Go-style template syntax)
          rendered_prompt = render_go_template(template_content, template_data)

          if options[:dry_run]
            # Show the prompt that would be sent
            puts 'Synthesis Prompt Preview'
            puts '=' * 80
            puts
            puts rendered_prompt
            puts
            puts '=' * 80
            Formatters::ProgressFormatter.success('Dry-run complete - prompt displayed above')
            return
          end

          # Call LLM to generate code
          puts 'Generating agent code from instructions...'
          puts

          llm_response = call_llm_for_synthesis(rendered_prompt)

          # Extract Ruby code from response
          generated_code = extract_ruby_code(llm_response)

          if generated_code.nil?
            Formatters::ProgressFormatter.error('Failed to extract Ruby code from LLM response')
            puts
            puts 'LLM Response:'
            puts llm_response
            exit 1
          end

          # Display generated code
          puts 'Generated Code:'
          puts '=' * 80
          puts generated_code
          puts '=' * 80
          puts

          # Validate generated code
          puts 'Validating generated code...'
          validation_result = validate_code_against_schema(generated_code)

          if validation_result[:valid] && validation_result[:warnings].empty?
            Formatters::ProgressFormatter.success('✅ Code is valid - No issues found')
          elsif validation_result[:valid]
            Formatters::ProgressFormatter.success('✅ Code is valid - With warnings')
            puts
            validation_result[:warnings].each do |warn|
              puts "  ⚠  #{warn[:message]}"
            end
          else
            Formatters::ProgressFormatter.error('❌ Code validation failed')
            puts
            validation_result[:errors].each do |err|
              puts "  ✗ #{err[:message]}"
            end
          end

          puts
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Test synthesis failed: #{e.message}")
          puts e.backtrace.first(5).join("\n") if options[:verbose]
          exit 1
        end

        desc 'synthesis-template', 'Export synthesis templates for agent code generation'
        long_desc <<-DESC
          Export the synthesis templates used by the Language Operator to generate
          agent code from natural language instructions.

          These templates are used by the operator's synthesis engine to convert
          user instructions into executable Ruby DSL code.

          Examples:
            # Export agent synthesis template (default)
            aictl system synthesis-template

            # Export persona distillation template
            aictl system synthesis-template --type persona

            # Export as JSON with schema included
            aictl system synthesis-template --format json --with-schema

            # Export as YAML
            aictl system synthesis-template --format yaml

            # Validate template syntax
            aictl system synthesis-template --validate

            # Save to file
            aictl system synthesis-template > agent_synthesis.tmpl
        DESC
        option :format, type: :string, default: 'template', desc: 'Output format (template, json, yaml)'
        option :type, type: :string, default: 'agent', desc: 'Template type (agent, persona)'
        option :with_schema, type: :boolean, default: false, desc: 'Include DSL schema in output'
        option :validate, type: :boolean, default: false, desc: 'Validate template syntax'
        def synthesis_template
          # Validate type
          template_type = options[:type].downcase
          unless %w[agent persona].include?(template_type)
            Formatters::ProgressFormatter.error("Invalid template type: #{template_type}")
            puts
            puts 'Supported types: agent, persona'
            exit 1
          end

          # Load template
          template_content = load_template(template_type)

          # Validate if requested
          if options[:validate]
            validation_result = validate_template_content(template_content, template_type)

            # Display warnings if any
            unless validation_result[:warnings].empty?
              Formatters::ProgressFormatter.warn('Template validation warnings:')
              validation_result[:warnings].each do |warning|
                puts "  ⚠  #{warning}"
              end
              puts
            end

            # Display errors and exit if validation failed
            if validation_result[:valid]
              Formatters::ProgressFormatter.success('Template validation passed')
              return
            else
              Formatters::ProgressFormatter.error('Template validation failed:')
              validation_result[:errors].each do |error|
                puts "  ✗ #{error}"
              end
              exit 1
            end
          end

          # Generate output based on format
          format = options[:format].downcase
          case format
          when 'template'
            output_template_format(template_content)
          when 'json'
            output_json_format(template_content, template_type)
          when 'yaml'
            output_yaml_format(template_content, template_type)
          else
            Formatters::ProgressFormatter.error("Invalid format: #{format}")
            puts
            puts 'Supported formats: template, json, yaml'
            exit 1
          end
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to load template: #{e.message}")
          exit 1
        end

        private

        # Render Go-style template ({{.Variable}})
        # Simplified implementation for basic variable substitution
        def render_go_template(template, data)
          result = template.dup

          # Handle {{if .ErrorContext}} - remove this section for test-synthesis
          result.gsub!(/{{if \.ErrorContext}}.*?{{else}}/m, '')
          result.gsub!(/{{end}}/, '')

          # Replace simple variables {{.Variable}}
          data.each do |key, value|
            result.gsub!("{{.#{key}}}", value.to_s)
          end

          result
        end

        # Detect temporal intent from instructions (scheduled vs autonomous)
        def detect_temporal_intent(instructions)
          temporal_keywords = {
            scheduled: %w[daily weekly hourly monthly schedule cron every day week hour minute],
            autonomous: %w[monitor watch continuously constantly always loop]
          }

          instructions_lower = instructions.downcase

          # Check for scheduled keywords
          scheduled_matches = temporal_keywords[:scheduled].count { |keyword| instructions_lower.include?(keyword) }
          autonomous_matches = temporal_keywords[:autonomous].count { |keyword| instructions_lower.include?(keyword) }

          scheduled_matches > autonomous_matches ? 'scheduled' : 'autonomous'
        end

        # Format tools list for template
        def format_tools_list(tools_str)
          return 'No tools specified' if tools_str.nil? || tools_str.strip.empty?

          tools = tools_str.split(',').map(&:strip)
          tools.map { |tool| "- #{tool}" }.join("\n")
        end

        # Format models list for template
        def format_models_list(models_str)
          # If not specified, try to detect from environment
          if models_str.nil? || models_str.strip.empty?
            models = detect_available_models
            return models.map { |model| "- #{model}" }.join("\n") unless models.empty?

            return 'No models specified (configure ANTHROPIC_API_KEY or OPENAI_API_KEY)'
          end

          models = models_str.split(',').map(&:strip)
          models.map { |model| "- #{model}" }.join("\n")
        end

        # Detect available models from environment
        def detect_available_models
          models = []
          models << 'claude-3-5-sonnet-20241022' if ENV['ANTHROPIC_API_KEY']
          models << 'gpt-4-turbo' if ENV['OPENAI_API_KEY']
          models
        end

        # Call LLM to generate code from synthesis prompt
        def call_llm_for_synthesis(prompt)
          require 'ruby_llm'

          # Check for API keys
          unless ENV['ANTHROPIC_API_KEY'] || ENV['OPENAI_API_KEY']
            Formatters::ProgressFormatter.error('No LLM credentials found')
            puts
            puts 'Please set one of the following environment variables:'
            puts '  - ANTHROPIC_API_KEY (for Claude models)'
            puts '  - OPENAI_API_KEY (for GPT models)'
            exit 1
          end

          # Prefer Anthropic if available
          if ENV['ANTHROPIC_API_KEY']
            provider = :anthropic
            api_key = ENV['ANTHROPIC_API_KEY']
            model = 'claude-3-5-sonnet-20241022'
          else
            provider = :openai
            api_key = ENV.fetch('OPENAI_API_KEY', nil)
            model = 'gpt-4-turbo'
          end

          # Create client and call LLM
          client = RubyLLM.new(provider: provider, api_key: api_key)
          messages = [{ role: 'user', content: prompt }]

          response = client.chat(messages, model: model, max_tokens: 4000, temperature: 0.3)

          # Extract content from response
          if response.is_a?(Hash) && response.key?('content')
            response['content']
          elsif response.is_a?(String)
            response
          else
            response.to_s
          end
        rescue StandardError => e
          Formatters::ProgressFormatter.error("LLM call failed: #{e.message}")
          exit 1
        end

        # Extract Ruby code from LLM response
        # Looks for ```ruby ... ``` blocks
        def extract_ruby_code(response)
          # Match ```ruby ... ``` blocks
          match = response.match(/```ruby\n(.*?)```/m)
          return match[1].strip if match

          # Try without language specifier
          match = response.match(/```\n(.*?)```/m)
          return match[1].strip if match

          # If no code blocks, return nil
          nil
        end

        # Load template from bundled gem or operator ConfigMap
        def load_template(type)
          # Try to fetch from operator ConfigMap first (if kubectl available)
          template = fetch_from_operator(type)
          return template if template

          # Fall back to bundled template
          load_bundled_template(type)
        end

        # Fetch template from operator ConfigMap via kubectl
        def fetch_from_operator(type)
          configmap_name = type == 'agent' ? 'agent-synthesis-template' : 'persona-distillation-template'
          result = `kubectl get configmap #{configmap_name} -n language-operator-system -o jsonpath='{.data.template}' 2>/dev/null`
          result.empty? ? nil : result
        rescue StandardError
          nil
        end

        # Load bundled template from gem
        def load_bundled_template(type)
          filename = type == 'agent' ? 'agent_synthesis.tmpl' : 'persona_distillation.tmpl'
          template_path = File.join(__dir__, '..', '..', 'templates', filename)
          File.read(template_path)
        end

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
          require 'parser/current'

          method_calls = []
          code_examples = extract_code_examples(template)

          code_examples.each do |example|
            # Parse the code to find method calls
            buffer = Parser::Source::Buffer.new('(template)')
            buffer.source = example[:code]
            parser = Parser::CurrentRuby.new
            ast = parser.parse(buffer)

            # Walk the AST to find method calls
            extract_methods_from_ast(ast, method_calls)
          rescue Parser::SyntaxError
            # Skip code with syntax errors - they'll be caught by validate_code_against_schema
            next
          end

          method_calls.uniq
        end

        # Recursively extract method names from AST
        def extract_methods_from_ast(node, methods)
          return unless node.is_a?(Parser::AST::Node)

          if node.type == :send
            _, method_name, * = node.children
            methods << method_name.to_s if method_name
          end

          node.children.each do |child|
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

        # Output raw template format
        def output_template_format(content)
          puts content
        end

        # Output JSON format with metadata
        def output_json_format(content, type)
          data = {
            version: Dsl::Schema.version,
            template_type: type,
            template: content
          }

          if options[:with_schema]
            data[:schema] = Dsl::Schema.to_json_schema
            data[:safe_agent_methods] = Dsl::Schema.safe_agent_methods
            data[:safe_tool_methods] = Dsl::Schema.safe_tool_methods
            data[:safe_helper_methods] = Dsl::Schema.safe_helper_methods
          end

          puts JSON.pretty_generate(data)
        end

        # Output YAML format with metadata
        def output_yaml_format(content, type)
          data = {
            'version' => Dsl::Schema.version,
            'template_type' => type,
            'template' => content
          }

          if options[:with_schema]
            data['schema'] = Dsl::Schema.to_json_schema.transform_keys(&:to_s)
            data['safe_agent_methods'] = Dsl::Schema.safe_agent_methods
            data['safe_tool_methods'] = Dsl::Schema.safe_tool_methods
            data['safe_helper_methods'] = Dsl::Schema.safe_helper_methods
          end

          puts YAML.dump(data)
        end
      end
    end
  end
end
