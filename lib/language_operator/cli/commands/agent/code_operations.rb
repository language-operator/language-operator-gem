# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Code viewing and editing for agents
        module CodeOperations
          def self.included(base)
            base.class_eval do
              desc 'code NAME', 'Display synthesized agent code'
              option :cluster, type: :string, desc: 'Override current cluster context'
              option :raw, type: :boolean, default: false, desc: 'Output raw code without formatting'
              def code(name)
                handle_command_error('get code') do
                  require_relative '../../formatters/code_formatter'

                  ctx = Helpers::ClusterContext.from_options(options)

                  # Get the code ConfigMap for this agent
                  configmap_name = "#{name}-code"
                  begin
                    configmap = ctx.client.get_resource('ConfigMap', configmap_name, ctx.namespace)
                  rescue K8s::Error::NotFound
                    Formatters::ProgressFormatter.error("Synthesized code not found for agent '#{name}'")
                    puts
                    puts 'Possible reasons:'
                    puts '  - Agent synthesis not yet complete'
                    puts '  - Agent synthesis failed'
                    puts
                    puts 'Check synthesis status with:'
                    puts "  aictl agent inspect #{name}"
                    exit 1
                  end

                  # Get the agent.rb code from the ConfigMap
                  code_content = configmap.dig('data', 'agent.rb')
                  unless code_content
                    Formatters::ProgressFormatter.error('Code content not found in ConfigMap')
                    exit 1
                  end

                  # Raw output mode - just print the code
                  if options[:raw]
                    puts code_content
                    return
                  end

                  # Display with syntax highlighting
                  Formatters::CodeFormatter.display_ruby_code(
                    code_content,
                    title: "Synthesized Code for Agent: #{name}"
                  )
                end
              end

              desc 'edit NAME', 'Edit agent instructions'
              option :cluster, type: :string, desc: 'Override current cluster context'
              def edit(name)
                handle_command_error('edit agent') do
                  ctx = Helpers::ClusterContext.from_options(options)

                  # Get current agent
                  agent = get_resource_or_exit('LanguageAgent', name)

                  current_instructions = agent.dig('spec', 'instructions')

                  # Edit instructions in user's editor
                  new_instructions = Helpers::EditorHelper.edit_content(
                    current_instructions,
                    'agent-instructions-',
                    '.txt'
                  ).strip

                  # Check if changed
                  if new_instructions == current_instructions
                    Formatters::ProgressFormatter.info('No changes made')
                    return
                  end

                  # Update agent resource
                  agent['spec']['instructions'] = new_instructions

                  Formatters::ProgressFormatter.with_spinner('Updating agent instructions') do
                    ctx.client.apply_resource(agent)
                  end

                  Formatters::ProgressFormatter.success('Agent instructions updated')
                  puts
                  puts 'The operator will automatically re-synthesize the agent code.'
                  puts
                  puts 'Watch synthesis progress with:'
                  puts "  aictl agent inspect #{name}"
                end
              end
            end
          end
        end
      end
    end
  end
end
