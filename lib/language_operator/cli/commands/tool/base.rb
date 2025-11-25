# frozen_string_literal: true

require 'yaml'
require 'json'
require_relative '../../command_loader'

# Include all tool subcommand modules
require_relative 'install'
require_relative 'test'
require_relative 'search'

module LanguageOperator
  module CLI
    module Commands
      module Tool
        # Base tool command class
        class Base < BaseCommand
          include Constants
          include CLI::Helpers::ClusterValidator

          # Include all subcommand modules
          include Install
          include Test
          include Search

          desc 'list', 'List all tools in current cluster'
          option :cluster, type: :string, desc: 'Override current cluster context'
          def list
            handle_command_error('list tools') do
              tools = list_resources_or_empty(RESOURCE_TOOL) do
                puts
                puts 'Tools provide MCP server capabilities for agents.'
                puts
                puts 'Install a tool with:'
                puts '  aictl tool install <name>'
              end

              return if tools.empty?

              # Get agents to count usage
              agents = ctx.client.list_resources(RESOURCE_AGENT, namespace: ctx.namespace)

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
                  namespace: tool.dig('metadata', 'namespace') || ctx.namespace,
                  status: status
                }
              end

              Formatters::TableFormatter.tools(table_data)
            end
          end

          desc 'inspect NAME', 'Show detailed tool information'
          option :cluster, type: :string, desc: 'Override current cluster context'
          def inspect(name)
            handle_command_error('inspect tool') do
              tool = get_resource_or_exit(RESOURCE_TOOL, name)

              # Main tool information
              puts
              highlighted_box(
                title: RESOURCE_TOOL,
                rows: {
                  'Name' => pastel.white.bold(name),
                  'Namespace' => ctx.namespace,
                  'Cluster' => ctx.name,
                  'Status' => tool.dig('status', 'phase') || 'Unknown',
                  'Type' => tool.dig('spec', 'type') || 'mcp',
                  'Image' => tool.dig('spec', 'image'),
                  'Deployment Mode' => tool.dig('spec', 'deploymentMode') || 'sidecar',
                  'Port' => tool.dig('spec', 'port') || 8080,
                  'Replicas' => tool.dig('spec', 'replicas') || 1
                }
              )
              puts

              # Resources
              resources = tool.dig('spec', 'resources')
              if resources
                resource_rows = {}
                requests = resources['requests'] || {}
                limits = resources['limits'] || {}

                # CPU
                cpu_request = requests['cpu']
                cpu_limit = limits['cpu']
                resource_rows['CPU'] = [cpu_request, cpu_limit].compact.join(' / ') if cpu_request || cpu_limit

                # Memory
                memory_request = requests['memory']
                memory_limit = limits['memory']
                resource_rows['Memory'] = [memory_request, memory_limit].compact.join(' / ') if memory_request || memory_limit

                highlighted_box(title: 'Resources (Request/Limit)', rows: resource_rows, color: :cyan) unless resource_rows.empty?
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
              agents = ctx.client.list_resources(RESOURCE_AGENT, namespace: ctx.namespace)
              agents_using = agents.select do |agent|
                tools = agent.dig('spec', 'tools') || []
                tools.include?(name)
              end
              agent_names = agents_using.map { |agent| agent.dig('metadata', 'name') }

              list_box(
                title: 'Agents using this tool',
                items: agent_names
              )

              puts
              labels = tool.dig('metadata', 'labels') || {}
              list_box(
                title: 'Labels',
                items: labels,
                style: :key_value
              )
            end
          end

          desc 'delete NAME', 'Delete a tool'
          option :cluster, type: :string, desc: 'Override current cluster context'
          option :force, type: :boolean, default: false, desc: 'Skip confirmation'
          def delete(name)
            handle_command_error('delete tool') do
              get_resource_or_exit(RESOURCE_TOOL, name)

              # Check dependencies and get confirmation
              return unless check_dependencies_and_confirm('tool', name, force: options[:force])

              # Confirm deletion unless --force
              return unless confirm_deletion_with_force('tool', name, ctx.name, force: options[:force])

              # Delete tool
              Formatters::ProgressFormatter.with_spinner("Deleting tool '#{name}'") do
                ctx.client.delete_resource(RESOURCE_TOOL, name, ctx.namespace)
              end

              Formatters::ProgressFormatter.success("Tool '#{name}' deleted successfully")
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
end
