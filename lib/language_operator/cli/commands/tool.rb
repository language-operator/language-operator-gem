# frozen_string_literal: true

require 'yaml'
require 'erb'
require 'net/http'
require 'json'
require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../formatters/table_formatter'
require_relative '../helpers/cluster_validator'
require_relative '../helpers/user_prompts'
require_relative '../helpers/resource_dependency_checker'
require_relative '../../config/cluster_config'
require_relative '../../config/tool_registry'
require_relative '../../kubernetes/client'

module LanguageOperator
  module CLI
    module Commands
      # Tool management commands
      class Tool < BaseCommand
        include Helpers::ClusterValidator

        desc 'list', 'List all tools in current cluster'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def list
          handle_command_error('list tools') do
            tools = list_resources_or_empty('LanguageTool') do
              puts
              puts 'Tools provide MCP server capabilities for agents.'
              puts
              puts 'Install a tool with:'
              puts '  aictl tool install <name>'
            end

            return if tools.empty?

            # Get agents to count usage
            agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)

            table_data = tools.map do |tool|
              name = tool.dig('metadata', 'name')
              type = tool.dig('spec', 'type') || 'unknown'
              status = tool.dig('status', 'phase') || 'Unknown'

              # Count agents using this tool
              agents_using = Helpers::ResourceDependencyChecker.tool_usage_count(agents, name)

              # Get health status
              health = tool.dig('status', 'health') || 'unknown'
              health_indicator = case health.downcase
                                 when 'healthy' then '✓'
                                 when 'unhealthy' then '✗'
                                 else '?'
                                 end

              {
                name: name,
                type: type,
                status: status,
                agents_using: agents_using,
                health: "#{health_indicator} #{health}"
              }
            end

            Formatters::TableFormatter.tools(table_data)
          end
        end

        desc 'inspect NAME', 'Show detailed tool information'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def inspect(name)
          handle_command_error('inspect tool') do
            tool = get_resource_or_exit('LanguageTool', name)

            puts "Tool: #{name}"
            puts "  Cluster:   #{ctx.name}"
            puts "  Namespace: #{ctx.namespace}"
            puts

            # Status
            status = tool.dig('status', 'phase') || 'Unknown'
            puts "Status: #{status}"
            puts

            # Spec details
            puts 'Configuration:'
            puts "  Type:            #{tool.dig('spec', 'type') || 'mcp'}"
            puts "  Image:           #{tool.dig('spec', 'image')}"
            puts "  Deployment Mode: #{tool.dig('spec', 'deploymentMode') || 'sidecar'}"
            puts "  Port:            #{tool.dig('spec', 'port') || 8080}"
            puts "  Replicas:        #{tool.dig('spec', 'replicas') || 1}"
            puts

            # Resources
            resources = tool.dig('spec', 'resources')
            if resources
              puts 'Resources:'
              if resources['requests']
                puts '  Requests:'
                puts "    CPU:    #{resources['requests']['cpu']}"
                puts "    Memory: #{resources['requests']['memory']}"
              end
              if resources['limits']
                puts '  Limits:'
                puts "    CPU:    #{resources['limits']['cpu']}"
                puts "    Memory: #{resources['limits']['memory']}"
              end
              puts
            end

            # RBAC
            rbac = tool.dig('spec', 'rbac')
            if rbac && rbac['clusterRole']
              rules = rbac.dig('clusterRole', 'rules') || []
              puts "RBAC Permissions (#{rules.length} rules):"
              rules.each_with_index do |rule, idx|
                puts "  Rule #{idx + 1}:"
                puts "    API Groups: #{rule['apiGroups'].join(', ')}"
                puts "    Resources:  #{rule['resources'].join(', ')}"
                puts "    Verbs:      #{rule['verbs'].join(', ')}"
              end
              puts
            end

            # Egress rules
            egress = tool.dig('spec', 'egress') || []
            if egress.any?
              puts "Network Egress (#{egress.length} rules):"
              egress.each_with_index do |rule, idx|
                puts "  Rule #{idx + 1}: #{rule['description']}"
                puts "    DNS:   #{rule['dns'].join(', ')}" if rule['dns']
                puts "    CIDR:  #{rule['cidr']}" if rule['cidr']
                if rule['ports']
                  ports_str = rule['ports'].map { |p| "#{p['port']}/#{p['protocol']}" }.join(', ')
                  puts "    Ports: #{ports_str}"
                end
              end
              puts
            end

            # Try to fetch MCP capabilities
            capabilities = fetch_mcp_capabilities(name, tool, ctx.namespace)
            if capabilities && capabilities['tools'] && capabilities['tools'].any?
              puts "MCP Tools (#{capabilities['tools'].length}):"
              capabilities['tools'].each_with_index do |mcp_tool, idx|
                tool_name = mcp_tool['name']

                # Generate a meaningful name if empty
                if tool_name.nil? || tool_name.empty?
                  # Try to derive from description (first few words)
                  if mcp_tool['description']
                    # Take first 3-4 words and convert to snake_case
                    words = mcp_tool['description'].split(/\s+/).first(4)
                    derived_name = words.join('_').downcase.gsub(/[^a-z0-9_]/, '')
                    tool_name = "#{name}_#{derived_name}".gsub(/__+/, '_').sub(/_$/, '')
                  else
                    tool_name = "#{name}_tool_#{idx + 1}"
                  end
                end

                puts "  #{tool_name}"
                puts "    Description: #{mcp_tool['description']}" if mcp_tool['description']
                next unless mcp_tool['inputSchema'] && mcp_tool['inputSchema']['properties']

                params = mcp_tool['inputSchema']['properties'].keys
                required = mcp_tool['inputSchema']['required'] || []
                param_list = params.map { |p| required.include?(p) ? "#{p}*" : p }
                puts "    Parameters:  #{param_list.join(', ')}"
              end
              puts '    (* = required)'
              puts
            end

            # Get agents using this tool
            agents = ctx.client.list_resources('LanguageAgent', namespace: ctx.namespace)
            agents_using = agents.select do |agent|
              tools = agent.dig('spec', 'tools') || []
              tools.include?(name)
            end

            if agents_using.any?
              puts "Agents using this tool (#{agents_using.count}):"
              agents_using.each do |agent|
                puts "  - #{agent.dig('metadata', 'name')}"
              end
            else
              puts 'No agents using this tool'
            end

            puts
            puts 'Labels:'
            labels = tool.dig('metadata', 'labels') || {}
            if labels.empty?
              puts '  (none)'
            else
              labels.each do |key, value|
                puts "  #{key}: #{value}"
              end
            end
          end
        end

        desc 'delete NAME', 'Delete a tool'
        option :cluster, type: :string, desc: 'Override current cluster context'
        option :force, type: :boolean, default: false, desc: 'Skip confirmation'
        def delete(name)
          handle_command_error('delete tool') do
            tool = get_resource_or_exit('LanguageTool', name)

            # Check dependencies and get confirmation
            return unless check_dependencies_and_confirm('tool', name, force: options[:force])

            # Confirm deletion unless --force
            if confirm_deletion(
              'tool', name, ctx.name,
              details: {
                'Type' => tool.dig('spec', 'type'),
                'Status' => tool.dig('status', 'phase')
              },
              force: options[:force]
            )
              # Delete tool
              Formatters::ProgressFormatter.with_spinner("Deleting tool '#{name}'") do
                ctx.client.delete_resource('LanguageTool', name, ctx.namespace)
              end

              Formatters::ProgressFormatter.success("Tool '#{name}' deleted successfully")
            end
          end
        end

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
              template_path = File.join(__dir__, '..', 'templates', 'tools', 'generic.yaml')
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
              ctx.client.get_resource('LanguageTool', tool_name, ctx.namespace)
              Formatters::ProgressFormatter.warn("Tool '#{tool_name}' already exists in cluster '#{ctx.name}'")
              puts
              return unless Helpers::UserPrompts.confirm('Do you want to update it?')
            rescue K8s::Error::NotFound
              # Tool doesn't exist, proceed with creation
            end

            # Install tool
            Formatters::ProgressFormatter.with_spinner("Installing tool '#{tool_name}'") do
              resource = YAML.safe_load(yaml_content, permitted_classes: [Symbol])
              ctx.client.apply_resource(resource)
            end

            Formatters::ProgressFormatter.success("Tool '#{tool_name}' installed successfully")
            puts
            puts "Tool '#{tool_name}' is now available in cluster '#{ctx.name}'"
            if tool_config['authRequired']
              puts
              puts 'This tool requires authentication. Configure it with:'
              puts "  aictl tool auth #{tool_name}"
            end
          end
        end

        desc 'auth NAME', 'Configure authentication for a tool'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def auth(tool_name)
          handle_command_error('configure auth') do
            tool = get_resource_or_exit('LanguageTool', tool_name,
                                        error_message: "Tool '#{tool_name}' not found. Install it first with: aictl tool install #{tool_name}")

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

        desc 'test NAME', 'Test tool connectivity and health'
        option :cluster, type: :string, desc: 'Override current cluster context'
        def test(tool_name)
          handle_command_error('test tool') do
            tool = get_resource_or_exit('LanguageTool', tool_name)

            puts "Testing tool '#{tool_name}' in cluster '#{ctx.name}'"
            puts

            # Check phase
            phase = tool.dig('status', 'phase') || 'Unknown'
            status_indicator = case phase
                               when 'Running' then '✓'
                               when 'Pending' then '⏳'
                               when 'Failed' then '✗'
                               else '?'
                               end

            puts "Status:   #{status_indicator} #{phase}"

            # Check replicas
            ready_replicas = tool.dig('status', 'readyReplicas') || 0
            desired_replicas = tool.dig('spec', 'replicas') || 1
            puts "Replicas: #{ready_replicas}/#{desired_replicas} ready"

            # Check endpoint
            endpoint = tool.dig('status', 'endpoint')
            if endpoint
              puts "Endpoint: #{endpoint}"
            else
              puts 'Endpoint: Not available yet'
            end

            # Get pod status
            puts
            puts 'Pod Status:'

            label_selector = "langop.io/tool=#{tool_name}"
            pods = ctx.client.list_resources('Pod', namespace: ctx.namespace, label_selector: label_selector)

            if pods.empty?
              puts '  No pods found'
            else
              pods.each do |pod|
                pod_name = pod.dig('metadata', 'name')
                pod_phase = pod.dig('status', 'phase') || 'Unknown'
                pod_indicator = case pod_phase
                                when 'Running' then '✓'
                                when 'Pending' then '⏳'
                                when 'Failed' then '✗'
                                else '?'
                                end

                puts "  #{pod_indicator} #{pod_name}: #{pod_phase}"

                # Check container status
                container_statuses = pod.dig('status', 'containerStatuses') || []
                container_statuses.each do |status|
                  ready = status['ready'] ? '✓' : '✗'
                  puts "    #{ready} #{status['name']}: #{status['state']&.keys&.first || 'unknown'}"
                end
              end
            end

            # Test connectivity if endpoint is available
            if endpoint && phase == 'Running'
              puts
              puts 'Testing connectivity...'
              begin
                uri = URI(endpoint)
                response = Net::HTTP.get_response(uri)
                if response.code.to_i < 400
                  Formatters::ProgressFormatter.success('Connectivity test passed')
                else
                  Formatters::ProgressFormatter.warn("HTTP #{response.code}: #{response.message}")
                end
              rescue StandardError => e
                Formatters::ProgressFormatter.error("Connectivity test failed: #{e.message}")
              end
            end

            # Overall health
            puts
            if phase == 'Running' && ready_replicas == desired_replicas
              Formatters::ProgressFormatter.success("Tool '#{tool_name}' is healthy and operational")
            elsif phase == 'Pending'
              Formatters::ProgressFormatter.info("Tool '#{tool_name}' is starting up, please wait")
            else
              Formatters::ProgressFormatter.warn("Tool '#{tool_name}' has issues, check logs for details")
              puts
              puts 'View logs with:'
              puts "  kubectl logs -n #{ctx.namespace} -l langop.io/tool=#{tool_name}"
            end
          end
        end

        desc 'search [PATTERN]', 'Search available tools in the registry'
        long_desc <<-DESC
          Search and list available tools from the registry.

          Without a pattern, lists all available tools.
          With a pattern, filters tools by name or description (case-insensitive).

          Examples:
            aictl tool search              # List all tools
            aictl tool search web          # Find tools matching "web"
            aictl tool search email        # Find tools matching "email"
        DESC
        def search(pattern = nil)
          handle_command_error('search tools') do
            # Load tool patterns registry
            registry = Config::ToolRegistry.new
            patterns = registry.fetch

            # Filter out aliases and match pattern
            tools = patterns.select do |key, config|
              next false if config['alias'] # Skip aliases

              if pattern
                # Case-insensitive match on name or description
                key.downcase.include?(pattern.downcase) ||
                  config['description']&.downcase&.include?(pattern.downcase)
              else
                true
              end
            end

            if tools.empty?
              if pattern
                Formatters::ProgressFormatter.info("No tools found matching '#{pattern}'")
              else
                Formatters::ProgressFormatter.info('No tools found in registry')
              end
              return
            end

            # Display tools in a nice format
            tools.each do |name, config|
              description = config['description'] || 'No description'

              # Bold the tool name (ANSI escape codes)
              bold_name = "\e[1m#{name}\e[0m"
              puts "#{bold_name} - #{description}"
            end
          end
        end

        private

        # Fetch MCP capabilities from a running tool server
        #
        # @param name [String] Tool name
        # @param tool [Hash] Tool resource
        # @param namespace [String] Kubernetes namespace
        # @return [Hash, nil] MCP capabilities or nil if unavailable
        def fetch_mcp_capabilities(name, tool, namespace)
          return nil unless tool.dig('status', 'phase') == 'Running'

          # Get the service endpoint
          port = tool.dig('spec', 'port') || 80

          # Try to query the MCP server using kubectl port-forward
          # This is a fallback approach since we can't directly connect from CLI
          begin
            # Try to find a pod for this tool
            label_selector = "app.kubernetes.io/name=#{name}"
            pods = ctx.client.list_resources('Pod', namespace: namespace, label_selector: label_selector)

            return nil if pods.empty?

            pod_name = pods.first.dig('metadata', 'name')

            # Query the MCP server using JSON-RPC protocol
            # MCP uses the tools/list method to list available tools
            json_rpc_request = {
              jsonrpc: '2.0',
              id: 1,
              method: 'tools/list',
              params: {}
            }.to_json

            result = `kubectl exec -n #{namespace} #{pod_name} -- curl -s -X POST \
http://localhost:#{port}/mcp/tools/list -H "Content-Type: application/json" \
-d '#{json_rpc_request}' 2>/dev/null`

            return nil if result.empty?

            response = JSON.parse(result)
            response['result']
          rescue StandardError
            # Silently fail - capabilities are optional information
            nil
          end
        end
      end
    end
  end
end
