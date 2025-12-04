# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Code viewing and editing for agents using LanguageAgentVersion CRD
        module CodeOperations
          def self.included(base)
            base.class_eval do
              desc 'code NAME', 'Display agent code from LanguageAgentVersion'
              option :cluster, type: :string, desc: 'Override current cluster context'
              option :raw, type: :boolean, default: false, desc: 'Output raw code without formatting'
              option :version, type: :string, desc: 'Display specific version (e.g., --version=2)'
              def code(name)
                handle_command_error('get code') do
                  require_relative '../../formatters/code_formatter'

                  ctx = CLI::Helpers::ClusterContext.from_options(options)

                  # Get the LanguageAgentVersion resource
                  version_resource = get_agent_version_resource(ctx, name, options[:version])

                  unless version_resource
                    Formatters::ProgressFormatter.error("No code versions found for agent '#{name}'")
                    puts
                    puts 'This may indicate:'
                    puts '  - Agent has not been synthesized yet'
                    puts '  - Agent synthesis failed'
                    puts
                    puts 'Check agent status with:'
                    puts "  aictl agent inspect #{name}"
                    exit 1
                  end

                  # Get code from LanguageAgentVersion spec
                  code_content = version_resource.dig('spec', 'code')
                  unless code_content
                    Formatters::ProgressFormatter.error('Code content not found in LanguageAgentVersion')
                    exit 1
                  end

                  # Determine version info for title
                  version_num = version_resource.dig('spec', 'version')
                  source_type = version_resource.dig('spec', 'sourceType') || 'manual'
                  
                  title = if options[:version]
                            "Code for Agent: #{name} (Version #{version_num})"
                          else
                            active_version = get_active_version(ctx, name)
                            if version_num.to_s == active_version
                              "Current Code for Agent: #{name} (Version #{version_num} - #{source_type})"
                            else
                              "Code for Agent: #{name} (Version #{version_num} - #{source_type})"
                            end
                          end

                  # Raw output mode - just print the code
                  if options[:raw]
                    puts code_content
                    return
                  end

                  # Display with syntax highlighting
                  Formatters::CodeFormatter.display_ruby_code(
                    code_content,
                    title: title
                  )
                end
              end

              desc 'versions NAME', 'List available LanguageAgentVersion resources'
              option :cluster, type: :string, desc: 'Override current cluster context'
              def versions(name)
                handle_command_error('list versions') do
                  ctx = CLI::Helpers::ClusterContext.from_options(options)

                  # Get agent to verify it exists
                  get_resource_or_exit(Constants::RESOURCE_AGENT, name)

                  # Find all LanguageAgentVersion resources for this agent
                  versions = ctx.client.list_resources(Constants::RESOURCE_AGENT_VERSION, namespace: ctx.namespace)
                                      .select { |v| v.dig('spec', 'agentRef', 'name') == name }
                                      .sort_by { |v| v.dig('spec', 'version').to_i }

                  if versions.empty?
                    puts
                    puts "No LanguageAgentVersion resources found for agent: #{pastel.bold(name)}"
                    puts
                    puts pastel.yellow('No versions have been created yet.')
                    puts
                    puts 'Versions are created automatically during agent synthesis.'
                    puts "Check agent status: #{pastel.dim("aictl agent inspect #{name}")}"
                    return
                  end

                  # Get current active version
                  active_version = get_active_version(ctx, name)

                  # Build table data
                  table_data = versions.map do |version_resource|
                    version_num = version_resource.dig('spec', 'version').to_s
                    status = version_num == active_version ? 'current' : 'available'
                    source_type = version_resource.dig('spec', 'sourceType') || 'manual'
                    created = version_resource.dig('metadata', 'creationTimestamp')
                    created = created ? Time.parse(created).strftime('%Y-%m-%d %H:%M') : 'Unknown'

                    {
                      version: "v#{version_num}",
                      status: status,
                      type: source_type.capitalize,
                      created: created
                    }
                  end

                  # Display table
                  headers = %w[VERSION STATUS TYPE CREATED]
                  rows = table_data.map do |row|
                    status_indicator = row[:status] == 'current' ? pastel.green('●') : pastel.dim('○')
                    status_text = row[:status] == 'current' ? pastel.green('current') : 'available'

                    [
                      row[:version],
                      "#{status_indicator} #{status_text}",
                      row[:type],
                      row[:created]
                    ]
                  end

                  puts
                  puts "Code versions for agent: #{pastel.bold(name)}"
                  puts
                  puts table(headers, rows)
                  puts
                  puts 'Usage:'
                  puts "  #{pastel.dim("aictl agent code #{name}")}"
                  puts "  #{pastel.dim("aictl agent code #{name} --version=X")}"
                end
              end

              private

              def get_active_version(ctx, agent_name)
                begin
                  agent = ctx.client.get_resource(Constants::RESOURCE_AGENT, agent_name, ctx.namespace)
                  version_ref = agent.dig('spec', 'agentVersionRef', 'name')
                  return nil unless version_ref

                  # Extract version number from "agent-name-vX" format
                  version_ref.split('-v').last
                rescue K8s::Error::NotFound
                  nil
                end
              end

              def get_agent_version_resource(ctx, agent_name, requested_version = nil)
                # Query LanguageAgentVersion resources for this agent
                versions = ctx.client.list_resources(Constants::RESOURCE_AGENT_VERSION, namespace: ctx.namespace)
                                    .select { |v| v.dig('spec', 'agentRef', 'name') == agent_name }

                if versions.empty?
                  return nil
                end

                if requested_version
                  # Find specific version
                  target_version = versions.find { |v| v.dig('spec', 'version').to_s == requested_version }
                  
                  unless target_version
                    Formatters::ProgressFormatter.error("Version #{requested_version} not found for agent '#{agent_name}'")
                    puts
                    puts 'Available versions:'
                    versions.each do |v|
                      version_num = v.dig('spec', 'version')
                      puts "  v#{version_num}"
                    end
                    puts
                    puts "Use 'aictl agent versions #{agent_name}' to see all available versions"
                    exit 1
                  end

                  return target_version
                else
                  # Get currently active version
                  active_version = get_active_version(ctx, agent_name)
                  
                  if active_version
                    # Find the currently active version resource
                    active_version_resource = versions.find { |v| v.dig('spec', 'version').to_s == active_version }
                    return active_version_resource if active_version_resource
                  end

                  # Fall back to latest version if no active version or active version not found
                  return versions.max_by { |v| v.dig('spec', 'version').to_i }
                end
              end

              desc 'edit NAME', 'Edit agent instructions'
              option :cluster, type: :string, desc: 'Override current cluster context'
              def edit(name)
                handle_command_error('edit agent') do
                  ctx = CLI::Helpers::ClusterContext.from_options(options)

                  # Get current agent
                  agent = get_resource_or_exit(LanguageOperator::Constants::RESOURCE_AGENT, name)

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