# frozen_string_literal: true

require 'yaml'
require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../formatters/table_formatter'
require_relative '../helpers/cluster_validator'
require_relative '../helpers/user_prompts'
require_relative '../helpers/resource_dependency_checker'
require_relative '../helpers/editor_helper'
require_relative '../helpers/pastel_helper'
require_relative '../../config/cluster_config'
require_relative '../../kubernetes/client'
require_relative '../../kubernetes/resource_builder'

module LanguageOperator
  module CLI
    module Commands
      # Persona management commands
      class Persona < BaseCommand
        include Helpers::ClusterValidator
        include Helpers::UxHelper

        desc 'list', 'List all personas in current cluster'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def list
          handle_command_error('list personas') do
            personas = list_resources_or_empty('LanguagePersona') do
              puts
              puts 'Personas define the personality and capabilities of agents.'
              puts
              puts 'Create a persona with:'
              puts '  aictl persona create <name>'
            end

            return if personas.empty?

            # Get agents to count usage
            agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)

            table_data = personas.map do |persona|
              name = persona.dig('metadata', 'name')
              used_by = agents.count { |a| a.dig('spec', 'persona') == name }

              {
                name: name,
                tone: persona.dig('spec', 'tone') || 'neutral',
                used_by: used_by,
                description: persona.dig('spec', 'description') || ''
              }
            end

            Formatters::TableFormatter.personas(table_data)
          end
        end

        desc 'show NAME', 'Display full persona details'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def show(name)
          handle_command_error('show persona') do
            persona = get_resource_or_exit('LanguagePersona', name)

            puts
            puts "Persona: #{pastel.cyan.bold(name)}"
            puts '═' * 80
            puts

            # Format and display key persona details
            spec = persona['spec'] || {}
            puts "#{pastel.bold('Display Name:')} #{spec['displayName']}"
            puts "#{pastel.bold('Tone:')} #{pastel.yellow(spec['tone'])}" if spec['tone']
            puts
            puts pastel.bold('Description:')
            puts "  #{spec['description']}"
            puts

            if spec['systemPrompt']
              puts pastel.bold('System Prompt:')
              puts "  #{spec['systemPrompt']}"
              puts
            end

            if spec['capabilities']&.any?
              puts pastel.bold('Capabilities:')
              spec['capabilities'].each do |cap|
                puts "  #{pastel.green('•')} #{cap}"
              end
              puts
            end

            if spec['toolPreferences']&.any?
              puts pastel.bold('Tool Preferences:')
              spec['toolPreferences'].each do |pref|
                puts "  #{pastel.green('•')} #{pref}"
              end
              puts
            end

            if spec['responseFormat']
              puts "#{pastel.bold('Response Format:')} #{spec['responseFormat']}"
              puts
            end

            puts '═' * 80
            puts
            Formatters::ProgressFormatter.info('Use this persona when creating agents:')
            puts "  aictl agent create \"description\" --persona #{name}"
            puts
          end
        end

        desc 'create NAME', 'Create a new persona'
        long_desc <<-DESC
          Create a new persona with the specified name using an interactive wizard.

          Examples:
            aictl persona create helpful-assistant
            aictl persona create code-reviewer --from helpful-assistant
        DESC
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :from, type: :string, desc: 'Copy from existing persona as starting point'
        def create(name)
          handle_command_error('create persona') do
            # Check if persona already exists
            begin
              ctx.client.get_resource('LanguagePersona', name, ctx.namespace)
              Formatters::ProgressFormatter.error("Persona '#{name}' already exists in cluster '#{ctx.name}'")
              puts
              puts 'Use a different name or delete the existing persona first:'
              puts "  aictl persona delete #{name}"
              exit 1
            rescue K8s::Error::NotFound
              # Good - persona doesn't exist yet
            end

            # If --from flag provided, copy from existing persona
            base_persona = nil
            if options[:from]
              base_persona = get_resource_or_exit('LanguagePersona', options[:from],
                                                  error_message: "Source persona '#{options[:from]}' not found")
              Formatters::ProgressFormatter.info("Copying from persona '#{options[:from]}'")
              puts
            end

            # Interactive prompts
            require 'tty-prompt'
            # prompt available via UxHelper

            puts
            puts '=' * 80
            puts '  Create New Persona'
            puts '=' * 80
            puts

            # Get display name
            default_display_name = base_persona&.dig('spec', 'displayName') || name.split('-').map(&:capitalize).join(' ')
            display_name = prompt.ask('Display Name:', default: default_display_name)

            # Get description
            default_description = base_persona&.dig('spec', 'description') || ''
            description = prompt.ask('Description:', default: default_description) do |q|
              q.required true
            end

            # Get tone
            default_tone = base_persona&.dig('spec', 'tone') || 'neutral'
            tone = prompt.select('Tone:', %w[neutral friendly professional technical creative], default: default_tone)

            # Get system prompt
            puts
            puts 'System Prompt (press Enter to open editor):'
            prompt.keypress('Press any key to continue...')

            default_system_prompt = base_persona&.dig('spec', 'systemPrompt') || ''
            system_prompt = Helpers::EditorHelper.edit_content(default_system_prompt, 'persona-system-prompt', '.txt')

            if system_prompt.strip.empty?
              Formatters::ProgressFormatter.error('System prompt cannot be empty')
              exit 1
            end

            # Get capabilities
            puts
            puts 'Capabilities (optional, press Enter to open editor, or leave empty to skip):'
            puts 'Describe what this persona can do, one per line.'
            prompt.keypress('Press any key to continue...')

            default_capabilities = base_persona&.dig('spec', 'capabilities')&.join("\n") || ''
            capabilities_text = Helpers::EditorHelper.edit_content(default_capabilities, 'persona-capabilities', '.txt')
            capabilities = capabilities_text.strip.empty? ? [] : capabilities_text.strip.split("\n").map(&:strip).reject(&:empty?)

            # Build persona resource
            persona_spec = {
              'displayName' => display_name,
              'description' => description,
              'tone' => tone,
              'systemPrompt' => system_prompt.strip
            }
            persona_spec['capabilities'] = capabilities unless capabilities.empty?

            persona_resource = Kubernetes::ResourceBuilder.build_persona(
              name: name,
              spec: persona_spec,
              namespace: ctx.namespace
            )

            # Show preview
            puts
            puts '=' * 80
            puts 'Preview:'
            puts '=' * 80
            puts YAML.dump(persona_resource)
            puts '=' * 80
            puts

            # Confirm creation
            unless prompt.yes?('Create this persona?')
              puts 'Creation cancelled'
              return
            end

            # Create persona
            Formatters::ProgressFormatter.with_spinner("Creating persona '#{name}'") do
              ctx.client.create_resource(persona_resource)
            end

            Formatters::ProgressFormatter.success("Persona '#{name}' created successfully")
            puts
            puts 'Use this persona when creating agents:'
            puts "  aictl agent create \"description\" --persona #{name}"
          end
        end

        desc 'edit NAME', 'Edit an existing persona'
        long_desc <<-DESC
          Edit an existing persona by opening the YAML definition in your editor.

          When you save and close the editor, the persona will be updated.
          Any agents using this persona will be automatically re-synthesized.

          Example:
            aictl persona edit helpful-assistant
        DESC
        option :cluster, type: :string, desc: 'Override current cluster context'
        def edit(name)
          handle_command_error('edit persona') do
            # Get current persona
            persona = get_resource_or_exit('LanguagePersona', name)

            # Open in editor
            original_yaml = YAML.dump(persona)
            edited_yaml = Helpers::EditorHelper.edit_content(original_yaml, "persona-#{name}", '.txt')

            # Check if changed
            if edited_yaml.strip == original_yaml.strip
              Formatters::ProgressFormatter.info('No changes made')
              return
            end

            # Parse edited YAML
            begin
              edited_persona = YAML.safe_load(edited_yaml)
            rescue Psych::SyntaxError => e
              Formatters::ProgressFormatter.error("Invalid YAML: #{e.message}")
              exit 1
            end

            # Validate structure
            unless edited_persona.is_a?(Hash) && edited_persona['spec']
              Formatters::ProgressFormatter.error('Invalid persona structure: missing spec')
              exit 1
            end

            # Update persona
            Formatters::ProgressFormatter.with_spinner("Updating persona '#{name}'") do
              ctx.client.update_resource(edited_persona)
            end

            Formatters::ProgressFormatter.success("Persona '#{name}' updated successfully")

            # Check for agents using this persona
            agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)
            agents_using = Helpers::ResourceDependencyChecker.agents_using_persona(agents, name)

            if agents_using.any?
              puts
              Formatters::ProgressFormatter.info("#{agents_using.count} agent(s) will be re-synthesized automatically:")
              agents_using.each do |agent|
                puts "  - #{agent.dig('metadata', 'name')}"
              end
            end
          end
        end

        desc 'delete NAME', 'Delete a persona'
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :force, type: :boolean, default: false, desc: 'Skip confirmation'
        def delete(name)
          handle_command_error('delete persona') do
            # Get persona
            persona = get_resource_or_exit('LanguagePersona', name)

            # Check dependencies and get confirmation
            return unless check_dependencies_and_confirm('persona', name, force: options[:force])

            # Confirm deletion unless --force
            return unless confirm_deletion_with_force('persona', name, ctx.name, force: options[:force])

            # Delete persona
            Formatters::ProgressFormatter.with_spinner("Deleting persona '#{name}'") do
              ctx.client.delete_resource('LanguagePersona', name, ctx.namespace)
            end

            Formatters::ProgressFormatter.success("Persona '#{name}' deleted successfully")
          end
        end
      end
    end
  end
end
