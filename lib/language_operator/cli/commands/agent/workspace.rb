# frozen_string_literal: true

require 'open3'
require 'shellwords'
require_relative '../../helpers/label_utils'

module LanguageOperator
  module CLI
    module Commands
      module Agent
        # Workspace management for agents
        module Workspace
          def self.included(base)
            base.class_eval do
              desc 'workspace NAME', 'Browse agent workspace files'
              long_desc <<-DESC
                Browse and manage the workspace files for an agent.

                Workspaces provide persistent storage for agents to maintain state,
                cache data, and remember information across executions.

                Examples:
                  aictl agent workspace my-agent                           # List all files
                  aictl agent workspace my-agent --path /workspace/state.json  # View specific file
                  aictl agent workspace my-agent --clean                   # Clear workspace
              DESC
              option :cluster, type: :string, desc: 'Override current cluster context'
              option :path, type: :string, desc: 'View specific file contents'
              option :clean, type: :boolean, desc: 'Clear workspace (with confirmation)'
              def workspace(name)
                handle_command_error('access workspace') do
                  ctx = CLI::Helpers::ClusterContext.from_options(options)

                  # Get agent to verify it exists
                  agent = get_resource_or_exit(LanguageOperator::Constants::RESOURCE_AGENT, name)

                  # Check if workspace is enabled
                  workspace_enabled = agent.dig('spec', 'workspace', 'enabled')
                  unless workspace_enabled
                    Formatters::ProgressFormatter.warn("Workspace is not enabled for agent '#{name}'")
                    puts
                    puts 'Enable workspace in agent configuration:'
                    puts '  spec:'
                    puts '    workspace:'
                    puts '      enabled: true'
                    puts '      size: 10Gi'
                    exit 1
                  end

                  if options[:path]
                    view_workspace_file(ctx, name, options[:path])
                  elsif options[:clean]
                    clean_workspace(ctx, name)
                  else
                    list_workspace_files(ctx, name)
                  end
                end
              end

              private

              def get_agent_pod(ctx, agent_name)
                # Validate agent name for label compatibility
                unless CLI::Helpers::LabelUtils.valid_label_value?(agent_name)
                  Formatters::ProgressFormatter.error("Agent name '#{agent_name}' is not valid for Kubernetes labels")
                  puts
                  puts 'Agent names must:'
                  puts '  - Be 63 characters or less'
                  puts '  - Contain only lowercase letters, numbers, hyphens, and dots'
                  puts '  - Start and end with alphanumeric characters'
                  exit 1
                end

                # Find pod for this agent using normalized label selector
                label_selector = CLI::Helpers::LabelUtils.agent_pod_selector(agent_name)
                pods = ctx.client.list_resources('Pod', namespace: ctx.namespace, label_selector: label_selector)

                if pods.empty?
                  debug_info = CLI::Helpers::LabelUtils.debug_pod_search(ctx, agent_name)

                  Formatters::ProgressFormatter.error("No running pods found for agent '#{agent_name}'")
                  puts
                  puts 'Possible reasons:'
                  puts '  - Agent pod has not started yet'
                  puts '  - Agent is paused or stopped'
                  puts '  - Agent failed to deploy'
                  puts '  - Label mismatch (debugging info below)'
                  puts
                  puts 'Debug information:'
                  puts "  Agent name: #{debug_info[:agent_name]}"
                  puts "  Normalized: #{debug_info[:normalized_name]}"
                  puts "  Label selector: #{debug_info[:label_selector]}"
                  puts "  Namespace: #{debug_info[:namespace]}"
                  puts
                  puts 'Check agent status with:'
                  puts "  aictl agent inspect #{agent_name}"
                  puts
                  puts 'List all pods in namespace:'
                  puts "  kubectl get pods -n #{ctx.namespace} -l app.kubernetes.io/component=agent"
                  exit 1
                end

                # Find a running pod
                running_pod = pods.find do |pod|
                  pod.dig('status', 'phase') == 'Running'
                end

                unless running_pod
                  Formatters::ProgressFormatter.error('Agent pod exists but is not running')
                  puts
                  puts "Current pod status: #{pods.first.dig('status', 'phase')}"
                  puts
                  puts 'Check pod logs with:'
                  puts "  aictl agent logs #{agent_name}"
                  exit 1
                end

                running_pod.dig('metadata', 'name')
              end

              def exec_in_pod(ctx, pod_name, command)
                # Build command as array to prevent shell injection
                kubectl_prefix_array = Shellwords.shellsplit(ctx.kubectl_prefix)
                cmd_array = kubectl_prefix_array + ['exec', pod_name, '--']

                # Add command arguments
                cmd_array += if command.is_a?(Array)
                               command
                             else
                               [command]
                             end

                # Execute with array to avoid shell interpolation
                stdout, stderr, status = Open3.capture3(*cmd_array)

                raise "Command failed: #{stderr}" unless status.success?

                stdout
              end

              def list_workspace_files(ctx, agent_name)
                pod_name = get_agent_pod(ctx, agent_name)

                # Check if workspace directory exists
                begin
                  exec_in_pod(ctx, pod_name, 'test -d /workspace')
                rescue StandardError
                  Formatters::ProgressFormatter.error('Workspace directory not found in agent pod')
                  puts
                  puts 'The /workspace directory does not exist in the agent pod.'
                  puts 'This agent may not have workspace support enabled.'
                  exit 1
                end

                # Get workspace usage
                usage_output = exec_in_pod(
                  ctx,
                  pod_name,
                  'du -sh /workspace 2>/dev/null || echo "0\t/workspace"'
                )
                workspace_size = usage_output.split("\t").first.strip

                # List files with details
                file_list = exec_in_pod(
                  ctx,
                  pod_name,
                  'find /workspace -ls 2>/dev/null | tail -n +2'
                )

                puts
                puts pastel.cyan("Workspace for agent '#{agent_name}' (#{workspace_size})")
                puts '=' * 60
                puts

                if file_list.strip.empty?
                  puts pastel.dim('Workspace is empty')
                  puts
                  puts 'The agent will create files here as it runs.'
                  puts
                  return
                end

                # Parse and display file list
                file_list.each_line do |line|
                  parts = line.strip.split(/\s+/, 11)
                  next if parts.length < 11

                  # Extract relevant parts
                  # Format: inode blocks perms links user group size month day time path
                  perms = parts[2]
                  size = parts[6]
                  month = parts[7]
                  day = parts[8]
                  time_or_year = parts[9]
                  path = parts[10]

                  # Skip the /workspace directory itself
                  next if path == '/workspace'

                  # Determine file type and icon
                  icon = if perms.start_with?('d')
                           pastel.blue('📁')
                         else
                           pastel.white('📄')
                         end

                  # Format path relative to workspace
                  relative_path = path.sub('/workspace/', '')
                  indent = '  ' * relative_path.count('/')

                  # Format size
                  formatted_size = format_file_size(size.to_i).rjust(8)

                  # Format time
                  formatted_time = "#{month} #{day.rjust(2)} #{time_or_year}"

                  puts "#{indent}#{icon} #{File.basename(relative_path).ljust(30)} #{pastel.dim(formatted_size)}  #{pastel.dim(formatted_time)}"
                end

                puts
                puts pastel.dim('Commands:')
                puts pastel.dim("  aictl agent workspace #{agent_name} --path /workspace/<file>  # View file")
                puts pastel.dim("  aictl agent workspace #{agent_name} --clean                   # Clear workspace")
                puts
              end

              def view_workspace_file(ctx, agent_name, file_path)
                pod_name = get_agent_pod(ctx, agent_name)

                # Check if file exists
                begin
                  exec_in_pod(ctx, pod_name, "test -f #{file_path}")
                rescue StandardError
                  Formatters::ProgressFormatter.error("File not found: #{file_path}")
                  puts
                  puts 'List available files with:'
                  puts "  aictl agent workspace #{agent_name}"
                  exit 1
                end

                # Get file metadata
                stat_output = exec_in_pod(
                  ctx,
                  pod_name,
                  "stat -c '%s %Y' #{file_path}"
                )
                size, mtime = stat_output.strip.split

                # Get file contents
                contents = exec_in_pod(
                  ctx,
                  pod_name,
                  "cat #{file_path}"
                )

                # Display file
                puts
                puts pastel.cyan("File: #{file_path}")
                puts "Size: #{format_file_size(size.to_i)}"
                puts "Modified: #{format_timestamp(Time.at(mtime.to_i))}"
                puts '=' * 60
                puts
                puts contents
                puts
              end

              def clean_workspace(ctx, agent_name)
                pod_name = get_agent_pod(ctx, agent_name)

                # Get current workspace usage
                usage_output = exec_in_pod(
                  ctx,
                  pod_name,
                  'du -sh /workspace 2>/dev/null || echo "0\t/workspace"'
                )
                workspace_size = usage_output.split("\t").first.strip

                # Count files
                file_count = exec_in_pod(
                  ctx,
                  pod_name,
                  'find /workspace -type f | wc -l'
                ).strip.to_i

                puts
                puts pastel.yellow("This will delete ALL files in the workspace for '#{agent_name}'")
                puts
                puts 'The agent will lose:'
                puts '  • Execution history'
                puts '  • Cached data'
                puts '  • State information'
                puts
                puts "Current workspace: #{file_count} files, #{workspace_size}"
                puts

                # Use UserPrompts helper
                return unless CLI::Helpers::UserPrompts.confirm('Are you sure?')

                # Delete all files in workspace
                Formatters::ProgressFormatter.with_spinner('Cleaning workspace') do
                  exec_in_pod(
                    ctx,
                    pod_name,
                    'find /workspace -mindepth 1 -delete'
                  )
                end

                Formatters::ProgressFormatter.success("Workspace cleared (freed #{workspace_size})")
                puts
                puts 'The agent will start fresh on its next execution.'
              end

              def format_file_size(bytes)
                Formatters::ValueFormatter.file_size(bytes)
              end

              def format_timestamp(time)
                Formatters::ValueFormatter.timestamp(time)
              end
            end
          end
        end
      end
    end
  end
end
