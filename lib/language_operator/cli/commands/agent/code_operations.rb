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
              option :version, type: :string, desc: 'Display specific version (e.g., --version=2)'
              option :original, type: :boolean, default: false, desc: 'Display original code before optimization'
              def code(name)
                handle_command_error('get code') do
                  require_relative '../../formatters/code_formatter'

                  ctx = CLI::Helpers::ClusterContext.from_options(options)

                  if options[:original]
                    # Get original code from the base ConfigMap
                    configmap_name = "#{name}-code"
                    begin
                      configmap = ctx.client.get_resource('ConfigMap', configmap_name, ctx.namespace)
                    rescue K8s::Error::NotFound
                      Formatters::ProgressFormatter.error("Original code not found for agent '#{name}'")
                      puts
                      puts 'Possible reasons:'
                      puts '  - Agent synthesis not yet complete'
                      puts '  - Agent synthesis failed'
                      puts
                      puts 'Check synthesis status with:'
                      puts "  aictl agent inspect #{name}"
                      exit 1
                    end

                    code_content = configmap.dig('data', 'agent.rb')
                    unless code_content
                      Formatters::ProgressFormatter.error('Code content not found in ConfigMap')
                      exit 1
                    end

                    title = "Original Code for Agent: #{name}"
                  else
                    # Get versioned code (current active or specific version)
                    configmap, version_info = get_versioned_configmap(ctx, name, options[:version])

                    code_content = configmap.dig('data', 'agent.rb')
                    unless code_content
                      Formatters::ProgressFormatter.error('Code content not found in ConfigMap')
                      exit 1
                    end

                    title = if options[:version]
                              "Code for Agent: #{name} (Version #{options[:version]})"
                            else
                              "Current Code for Agent: #{name} (Version #{version_info})"
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

              desc 'versions NAME', 'List available code versions'
              option :cluster, type: :string, desc: 'Override current cluster context'
              def versions(name)
                handle_command_error('list versions') do
                  ctx = CLI::Helpers::ClusterContext.from_options(options)

                  # Get agent to verify it exists
                  get_resource_or_exit(Constants::RESOURCE_AGENT, name)

                  # Find all versioned ConfigMaps for this agent
                  label_selector = "langop.io/agent=#{name}"
                  configmaps = ctx.client.list_resources('ConfigMap', namespace: ctx.namespace, label_selector: label_selector)

                  # Get current active version from agent deployment
                  active_version = get_active_version(ctx, name)

                  if configmaps.empty?
                    # Show table with just original version
                    table_data = [{
                      version: 'original',
                      status: 'current',
                      type: 'Original',
                      created: 'N/A'
                    }]

                    headers = %w[VERSION STATUS TYPE CREATED]
                    rows = table_data.map do |row|
                      status_indicator = pastel.green('●')
                      status_text = pastel.green('current')

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
                    puts pastel.yellow('No optimized versions created yet.')
                    puts
                    puts 'Optimized versions are created automatically after 10+ successful agent runs.'
                    puts "Check agent status: #{pastel.dim("aictl agent inspect #{name}")}"
                    return
                  end

                  # Build table data
                  table_data = []

                  # Add original version
                  original_status = active_version == 'original' ? 'current' : 'available'
                  table_data << {
                    version: 'original',
                    status: original_status,
                    type: 'Original',
                    created: 'N/A'
                  }

                  # Add optimized versions
                  configmaps.each do |cm|
                    version = cm.dig('metadata', 'labels', 'langop.io/version')
                    next unless version

                    status = version == active_version ? 'current' : 'available'
                    created = cm.dig('metadata', 'creationTimestamp')
                    created = created ? Time.parse(created).strftime('%Y-%m-%d %H:%M') : 'Unknown'

                    table_data << {
                      version: version,
                      status: status,
                      type: 'Optimized',
                      created: created
                    }
                  end

                  # Sort by version number (original first, then by version number)
                  table_data.sort! do |a, b|
                    if a[:version] == 'original'
                      -1
                    elsif b[:version] == 'original'
                      1
                    else
                      a[:version].to_i <=> b[:version].to_i
                    end
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
                  puts "  #{pastel.dim("aictl agent code #{name} --original")}"
                end
              end

              private

              def get_active_version(ctx, agent_name)
                # Try to get CronJob first (for scheduled agents), then Deployment (for autonomous agents)
                %w[CronJob Deployment].each do |resource_type|
                  resource = ctx.client.get_resource(resource_type, agent_name, ctx.namespace)

                  # Look for version annotation or label
                  version = resource.dig('spec', 'jobTemplate', 'metadata', 'labels', 'langop.io/version') ||
                            resource.dig('spec', 'template', 'metadata', 'labels', 'langop.io/version') ||
                            resource.dig('metadata', 'labels', 'langop.io/version') ||
                            resource.dig('spec', 'jobTemplate', 'metadata', 'annotations', 'langop.io/version') ||
                            resource.dig('spec', 'template', 'metadata', 'annotations', 'langop.io/version') ||
                            resource.dig('metadata', 'annotations', 'langop.io/version')

                  return version if version
                rescue K8s::Error::NotFound
                  # Try the next resource type
                  next
                end

                # Default to original if no version info found
                'original'
              end

              def get_versioned_configmap(ctx, agent_name, requested_version = nil)
                label_selector = "langop.io/agent=#{agent_name}"
                configmaps = ctx.client.list_resources('ConfigMap', namespace: ctx.namespace, label_selector: label_selector)

                if configmaps.empty?
                  # Fall back to original code if no optimized versions exist
                  configmap_name = "#{agent_name}-code"
                  begin
                    original_configmap = ctx.client.get_resource('ConfigMap', configmap_name, ctx.namespace)
                    return [original_configmap, 'original']
                  rescue K8s::Error::NotFound
                    Formatters::ProgressFormatter.error("No code found for agent '#{agent_name}'")
                    puts
                    puts 'Possible reasons:'
                    puts '  - Agent synthesis not yet complete'
                    puts '  - Agent synthesis failed'
                    puts
                    puts 'Check synthesis status with:'
                    puts "  aictl agent inspect #{agent_name}"
                    exit 1
                  end
                end

                if requested_version
                  # Find specific version
                  target_configmap = configmaps.find do |cm|
                    cm.dig('metadata', 'labels', 'langop.io/version') == requested_version
                  end

                  unless target_configmap
                    Formatters::ProgressFormatter.error("Version #{requested_version} not found for agent '#{agent_name}'")
                    puts
                    puts 'Available versions:'
                    configmaps.each do |cm|
                      version = cm.dig('metadata', 'labels', 'langop.io/version')
                      puts "  #{version}" if version
                    end
                    puts
                    puts "Use 'aictl agent versions #{agent_name}' to see all available versions"
                    exit 1
                  end

                  [target_configmap, requested_version]
                else
                  # Get the currently active version (not just the latest)
                  active_version = get_active_version(ctx, agent_name)

                  if active_version == 'original'
                    # Agent is using original code
                    configmap_name = "#{agent_name}-code"
                    begin
                      original_configmap = ctx.client.get_resource('ConfigMap', configmap_name, ctx.namespace)
                      [original_configmap, 'original']
                    rescue K8s::Error::NotFound
                      Formatters::ProgressFormatter.error("Original code not found for agent '#{agent_name}'")
                      exit 1
                    end
                  else
                    # Find the currently active version
                    active_configmap = configmaps.find do |cm|
                      cm.dig('metadata', 'labels', 'langop.io/version') == active_version
                    end

                    if active_configmap
                      [active_configmap, active_version]
                    else
                      # Fall back to latest if active version not found
                      latest_configmap = configmaps.max_by do |cm|
                        version = cm.dig('metadata', 'labels', 'langop.io/version')
                        version ? version.to_i : 0
                      end

                      latest_version = latest_configmap.dig('metadata', 'labels', 'langop.io/version')
                      [latest_configmap, latest_version]
                    end
                  end
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
