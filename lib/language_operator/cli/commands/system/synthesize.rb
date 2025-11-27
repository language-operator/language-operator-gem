# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module System
        # Agent code synthesis command
        module Synthesize
          def self.included(base)
            base.class_eval do
              desc 'synthesize [INSTRUCTIONS]', 'Synthesize agent code from natural language instructions'
              long_desc <<-DESC
                Synthesize agent code by converting natural language instructions
                into Ruby DSL code without creating an actual agent.

                This command uses a LanguageModel resource from your cluster to generate
                agent code. If --model is not specified, the first available model will
                be auto-selected.

                Instructions can be provided either as a command argument or via STDIN.
                If no argument is provided, the command will read from STDIN.

                This command helps you validate your instructions and understand how the
                synthesis engine interprets them. Use --dry-run to see the prompt that
                would be sent to the LLM, or run without it to generate actual code.

                Examples:
                  # Test with dry-run (show prompt only)
                  aictl system synthesize "Monitor GitHub issues daily" --dry-run

                  # Generate code from instructions (auto-selects first available model)
                  aictl system synthesize "Send daily reports to Slack"

                  # Use a specific cluster model
                  aictl system synthesize "Process webhooks from GitHub" --model my-claude

                  # Output raw code without formatting (useful for piping to files)
                  aictl system synthesize "Monitor logs" --raw > agent.rb

                  # Read instructions from STDIN
                  cat instructions.txt | aictl system synthesize > agent.rb

                  # Read from STDIN with pipe
                  echo "Monitor GitHub issues" | aictl system synthesize --raw

                  # Specify custom agent name and tools
                  aictl system synthesize "Process webhooks from GitHub" \\
                    --agent-name github-processor \\
                    --tools github,slack \\
                    --model my-gpt4
              DESC
              option :agent_name, type: :string, default: 'test-agent', desc: 'Name for the test agent'
              option :tools, type: :string, desc: 'Comma-separated list of available tools'
              option :models, type: :string, desc: 'Comma-separated list of available models (from cluster)'
              option :model, type: :string, desc: 'Model to use for synthesis (defaults to first available in cluster)'
              option :dry_run, type: :boolean, default: false, desc: 'Show prompt without calling LLM'
              option :raw, type: :boolean, default: false, desc: 'Output only the raw code without formatting'
              
              def synthesize(instructions = nil)
                handle_command_error('synthesize agent') do
                  # Read instructions from STDIN if not provided as argument
                  if instructions.nil? || instructions.strip.empty?
                    if $stdin.tty?
                      Formatters::ProgressFormatter.error('No instructions provided')
                      puts
                      puts 'Provide instructions either as an argument or via STDIN:'
                      puts '  aictl system synthesize "Your instructions here"'
                      puts '  cat instructions.txt | aictl system synthesize'
                      exit 1
                    else
                      instructions = $stdin.read.strip
                      if instructions.empty?
                        Formatters::ProgressFormatter.error('No instructions provided')
                        puts
                        puts 'Provide instructions either as an argument or via STDIN:'
                        puts '  aictl system synthesize "Your instructions here"'
                        puts '  cat instructions.txt | aictl system synthesize'
                        exit 1
                      end
                    end
                  end
                  # Select model to use for synthesis
                  selected_model = select_synthesis_model

                  # Load synthesis template
                  template_content = load_bundled_template('agent')

                  # Detect temporal intent from instructions
                  temporal_intent = detect_temporal_intent(instructions)

                  # Prepare template data
                  template_data = {
                    'Instructions' => instructions,
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

                  # Call LLM to generate code (no output - just do it)
                  llm_response = call_llm_for_synthesis(rendered_prompt, selected_model)

                  # Extract Ruby code from response
                  generated_code = extract_ruby_code(llm_response)

                  if generated_code.nil?
                    Formatters::ProgressFormatter.error('Failed to extract Ruby code from LLM response')
                    puts
                    puts 'LLM Response:'
                    puts llm_response
                    exit 1
                  end

                  # Handle raw output
                  if options[:raw]
                    puts generated_code
                    return
                  end

                  # Display formatted code
                  highlighted_code = highlight_ruby_code(generated_code)

                  puts highlighted_code
                end
              end

              private

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
                # If not specified, try to detect from cluster
                if models_str.nil? || models_str.strip.empty?
                  models = detect_available_models
                  return models.map { |model| "- #{model}" }.join("\n") unless models.empty?

                  return 'No models available (run: aictl model list)'
                end

                models = models_str.split(',').map(&:strip)
                models.map { |model| "- #{model}" }.join("\n")
              end

              # Detect available models from cluster
              def detect_available_models
                models = ctx.client.list_resources('LanguageModel', namespace: ctx.namespace)
                models.map { |m| m.dig('metadata', 'name') }
              rescue StandardError => e
                Formatters::ProgressFormatter.error("Failed to list models from cluster: #{e.message}")
                []
              end

              # Select model to use for synthesis
              def select_synthesis_model
                # If --model option specified, use it
                return options[:model] if options[:model]

                # Otherwise, auto-select from available cluster models
                available_models = detect_available_models

                if available_models.empty?
                  Formatters::ProgressFormatter.error('No models available in cluster')
                  puts
                  puts 'Please create a model first:'
                  puts '  aictl model create'
                  puts
                  puts 'Or list existing models:'
                  puts '  aictl model list'
                  exit 1
                end

                # Auto-select first available model (silently)
                available_models.first
              end
            end
          end
        end
      end
    end
  end
end
