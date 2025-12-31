# frozen_string_literal: true

require 'yaml'
require 'erb'

module LanguageOperator
  module CLI
    module Commands
      module Tool
        # Tool installation and authentication commands
        module Install
          def self.included(base)
            base.class_eval do
              desc 'install NAME', 'Install a tool from the registry'
              option :cluster, type: :string, desc: 'Override current cluster context'
              option :deployment_mode, type: :string, enum: %w[service sidecar], desc: 'Deployment mode (service or sidecar)'
              option :replicas, type: :numeric, desc: 'Number of replicas'
              option :dry_run, type: :boolean, default: false, desc: 'Preview without installing'
              def install(tool_name)
                handle_command_error('install tool') do
                  # For dry-run mode, allow operation without a real cluster
                  if options[:dry_run]
                    cluster_name = options[:cluster] || 'preview'
                    namespace = 'default'
                  else
                    cluster_name = ctx.name
                    namespace = ctx.namespace
                  end

                  # Load tool patterns registry
                  registry = Config::ToolRegistry.new
                  patterns = registry.fetch

                  # Resolve aliases
                  tool_key = tool_name
                  tool_key = patterns[tool_key]['alias'] while patterns[tool_key]&.key?('alias')

                  # Look up tool in registry
                  tool_config = patterns[tool_key]
                  unless tool_config
                    Formatters::ProgressFormatter.error("Tool '#{tool_name}' not found in registry")
                    puts
                    puts 'Available tools:'
                    patterns.each do |key, config|
                      next if config['alias']

                      puts "  #{key.ljust(15)} - #{config['description']}"
                    end
                    exit 1
                  end

                  # Build template variables
                  vars = {
                    name: tool_name,
                    namespace: namespace,
                    cluster_ref: cluster_name,
                    deployment_mode: options[:deployment_mode] || tool_config['deploymentMode'],
                    replicas: options[:replicas] || 1,
                    auth_secret: nil, # Will be set by auth command
                    image: tool_config['image'],
                    port: tool_config['port'],
                    type: tool_config['type'],
                    egress: tool_config['egress'],
                    rbac: tool_config['rbac']
                  }

                  # Get template content - prefer registry manifest, fall back to generic template
                  if tool_config['manifest']
                    # Use manifest from registry (if provided in the future)
                    template_content = tool_config['manifest']
                  else
                    # Use generic template for all tools
                    template_path = File.join(__dir__, '..', '..', 'templates', 'tools', 'generic.yaml')
                    template_content = File.read(template_path)
                  end

                  # Render template
                  template = ERB.new(template_content, trim_mode: '-')
                  yaml_content = template.result_with_hash(vars)

                  # Dry run mode
                  if options[:dry_run]
                    puts "Would install tool '#{tool_name}' to cluster '#{cluster_name}':"
                    puts
                    puts "Display Name:    #{tool_config['displayName']}"
                    puts "Description:     #{tool_config['description']}"
                    puts "Deployment Mode: #{vars[:deployment_mode]}"
                    puts "Replicas:        #{vars[:replicas]}"
                    puts "Auth Required:   #{tool_config['authRequired'] ? 'Yes' : 'No'}"
                    puts
                    puts 'Generated YAML:'
                    puts '---'
                    puts yaml_content
                    puts
                    puts 'To install for real, run without --dry-run'
                    return
                  end

                  # Check if already exists
                  begin
                    ctx.client.get_resource(LanguageOperator::Constants::RESOURCE_TOOL, tool_name, ctx.namespace)
                    Formatters::ProgressFormatter.warn("Tool '#{tool_name}' already exists in cluster '#{ctx.name}'")
                    puts
                    return unless CLI::Helpers::UserPrompts.confirm('Do you want to update it?')
                  rescue K8s::Error::NotFound
                    # Tool doesn't exist, proceed with creation
                  end

                  # Install tool
                  Formatters::ProgressFormatter.with_spinner("Installing tool '#{tool_name}'") do
                    resource = YAML.safe_load(yaml_content, permitted_classes: [Symbol])
                    ctx.client.apply_resource(resource)
                  end

                  puts

                  # Show tool details
                  format_tool_details(
                    name: tool_name,
                    namespace: ctx.namespace,
                    cluster: ctx.name,
                    status: 'Ready',
                    image: tool_config['image'],
                    created: Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')
                  )

                  puts
                  if tool_config['authRequired']
                    puts 'This tool requires authentication. Configure it with:'
                    puts pastel.dim("  langop tool auth #{tool_name}")
                  else
                    puts "Tool '#{tool_name}' is now available for agents to use"
                  end
                end
              end

              desc 'auth NAME', 'Configure authentication for a tool'
              option :cluster, type: :string, desc: 'Override current cluster context'
              def auth(tool_name)
                handle_command_error('configure auth') do
                  tool = get_resource_or_exit(LanguageOperator::Constants::RESOURCE_TOOL, tool_name,
                                              error_message: "Tool '#{tool_name}' not found. Install it first with: langop tool install #{tool_name}")

                  puts "Configure authentication for tool '#{tool_name}'"
                  puts

                  # Determine auth type based on tool
                  case tool_name
                  when 'email', 'gmail'
                    puts 'Email/Gmail Configuration'
                    puts '-' * 40
                    print 'SMTP Server: '
                    smtp_server = $stdin.gets.chomp
                    print 'SMTP Port (587): '
                    smtp_port = $stdin.gets.chomp
                    smtp_port = '587' if smtp_port.empty?
                    print 'Email Address: '
                    email = $stdin.gets.chomp
                    print 'Password: '
                    password = $stdin.noecho(&:gets).chomp
                    puts

                    secret_data = {
                      'SMTP_SERVER' => smtp_server,
                      'SMTP_PORT' => smtp_port,
                      'EMAIL_ADDRESS' => email,
                      'EMAIL_PASSWORD' => password
                    }

                  when 'github'
                    puts 'GitHub Configuration'
                    puts '-' * 40
                    print 'GitHub Token: '
                    token = $stdin.noecho(&:gets).chomp
                    puts

                    secret_data = {
                      'GITHUB_TOKEN' => token
                    }

                  when 'slack'
                    puts 'Slack Configuration'
                    puts '-' * 40
                    print 'Slack Bot Token: '
                    token = $stdin.noecho(&:gets).chomp
                    puts

                    secret_data = {
                      'SLACK_BOT_TOKEN' => token
                    }

                  when 'gdrive'
                    puts 'Google Drive Configuration'
                    puts '-' * 40
                    puts 'Note: You need OAuth credentials from Google Cloud Console'
                    print 'Client ID: '
                    client_id = $stdin.gets.chomp
                    print 'Client Secret: '
                    client_secret = $stdin.noecho(&:gets).chomp
                    puts

                    secret_data = {
                      'GDRIVE_CLIENT_ID' => client_id,
                      'GDRIVE_CLIENT_SECRET' => client_secret
                    }

                  else
                    puts 'Generic API Key Configuration'
                    puts '-' * 40
                    print 'API Key: '
                    api_key = $stdin.noecho(&:gets).chomp
                    puts

                    secret_data = {
                      'API_KEY' => api_key
                    }
                  end

                  # Create secret
                  secret_name = "#{tool_name}-auth"
                  secret_resource = {
                    'apiVersion' => 'v1',
                    'kind' => 'Secret',
                    'metadata' => {
                      'name' => secret_name,
                      'namespace' => ctx.namespace
                    },
                    'type' => 'Opaque',
                    'stringData' => secret_data
                  }

                  Formatters::ProgressFormatter.with_spinner('Creating authentication secret') do
                    ctx.client.apply_resource(secret_resource)
                  end

                  # Update tool to use secret
                  tool['spec']['envFrom'] ||= []
                  tool['spec']['envFrom'] << { 'secretRef' => { 'name' => secret_name } }

                  Formatters::ProgressFormatter.with_spinner('Updating tool configuration') do
                    ctx.client.apply_resource(tool)
                  end

                  Formatters::ProgressFormatter.success('Authentication configured successfully')
                  puts
                  puts "Tool '#{tool_name}' is now authenticated and ready to use"
                end
              end
            end
          end
        end
      end
    end
  end
end
