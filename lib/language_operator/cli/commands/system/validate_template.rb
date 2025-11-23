# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module System
        # Template validation command
        module ValidateTemplate
          def self.included(base)
            base.class_eval do
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
                handle_command_error('validate template') do
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
                end
              end
            end
          end
        end
      end
    end
  end
end
