# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module Agent
        module Helpers
          # Helper methods for agent optimization (neural → symbolic)
          module OptimizationHelper
            # Apply optimization by creating versioned ConfigMap and updating Deployment
            #
            # @param ctx [ClusterContext] Cluster context
            # @param agent_name [String] Agent name
            # @param proposal [Hash] Optimization proposal
            # @return [Hash] Result with success status and metadata
            def apply_optimization(ctx, agent_name, proposal)
              base_configmap_name = "#{agent_name}-code"
              task_name = proposal[:task_name]

              # Get current ConfigMap and determine next version
              current_configmap = ctx.client.get_resource('ConfigMap', base_configmap_name, ctx.namespace)
              current_code = current_configmap.dig('data', 'agent.rb')

              raise "ConfigMap '#{base_configmap_name}' does not contain agent.rb" unless current_code

              # Get current version from annotations (default to v0 if not set)
              current_version_str = current_configmap.dig('metadata', 'annotations', 'langop.io/version') || 'v0'
              current_version = current_version_str.sub(/^v/, '').to_i
              new_version = current_version + 1
              new_version_str = "v#{new_version}"

              # Replace the neural task with the symbolic implementation
              # Build full task code from body code
              full_task_code = build_full_task_code(proposal[:task_definition], proposal[:proposed_code])
              updated_code = replace_task_in_code(current_code, task_name, full_task_code)

              # Create new versioned ConfigMap name
              versioned_configmap_name = "#{agent_name}-code-#{new_version_str}"

              # Build new versioned ConfigMap with ownerReferences for automatic garbage collection
              new_configmap = {
                'apiVersion' => 'v1',
                'kind' => 'ConfigMap',
                'metadata' => {
                  'name' => versioned_configmap_name,
                  'namespace' => ctx.namespace,
                  'labels' => {
                    'app' => agent_name,
                    'langop.io/agent' => agent_name,
                    'langop.io/component' => 'agent-code'
                  },
                  'annotations' => {
                    'langop.io/version' => new_version_str,
                    'langop.io/optimized' => 'true',
                    'langop.io/optimized-at' => Time.now.iso8601,
                    'langop.io/optimized-task' => task_name,
                    'langop.io/previous-version' => current_version_str
                  },
                  'ownerReferences' => [
                    {
                      'apiVersion' => 'v1',
                      'kind' => 'ConfigMap',
                      'name' => base_configmap_name,
                      'uid' => current_configmap.metadata.uid,
                      'controller' => false,
                      'blockOwnerDeletion' => false
                    }
                  ]
                },
                'data' => {
                  'agent.rb' => updated_code
                }
              }

              # Create the new versioned ConfigMap
              ctx.client.create_resource(new_configmap)

              # Update the base ConfigMap to point to the new version and include updated code
              # This maintains backward compatibility with agents not using versioning
              updated_base_configmap = {
                'apiVersion' => 'v1',
                'kind' => 'ConfigMap',
                'metadata' => {
                  'name' => base_configmap_name,
                  'namespace' => ctx.namespace,
                  'resourceVersion' => current_configmap.metadata.resourceVersion,
                  'labels' => current_configmap.dig('metadata', 'labels') || {},
                  'annotations' => {
                    'langop.io/version' => new_version_str,
                    'langop.io/latest-versioned-configmap' => versioned_configmap_name,
                    'langop.io/optimized' => 'true',
                    'langop.io/optimized-at' => Time.now.iso8601,
                    'langop.io/optimized-task' => task_name
                  }
                },
                'data' => {
                  'agent.rb' => updated_code
                }
              }

              # Update the base ConfigMap
              ctx.client.update_resource('ConfigMap', base_configmap_name, ctx.namespace, updated_base_configmap, 'v1')

              # Restart the agent pod to pick up changes
              restart_agent_pod(ctx, agent_name)

              # Clean up old versions (keep last 5)
              cleanup_old_configmap_versions(ctx, agent_name, keep_last: 5)

              {
                success: true,
                task_name: task_name,
                version: new_version_str,
                configmap: versioned_configmap_name,
                updated_code: proposal[:proposed_code],
                action: 'applied',
                message: "Optimization for '#{task_name}' applied as #{new_version_str}"
              }
            rescue StandardError => e
              {
                success: false,
                task_name: task_name,
                error: e.message,
                action: 'failed',
                message: "Failed to apply optimization: #{e.message}"
              }
            end

            # Cleanup old versioned ConfigMaps, keeping only the most recent N versions
            #
            # @param ctx [ClusterContext] Cluster context
            # @param agent_name [String] Agent name
            # @param keep_last [Integer] Number of versions to keep
            def cleanup_old_configmap_versions(ctx, agent_name, keep_last: 5)
              # Find all versioned ConfigMaps for this agent
              configmaps = ctx.client.list_resources(
                'ConfigMap',
                namespace: ctx.namespace,
                label_selector: "langop.io/agent=#{agent_name},langop.io/component=agent-code"
              )

              # Filter to only versioned ConfigMaps (exclude base ConfigMap)
              versioned_cms = configmaps.select do |cm|
                cm.dig('metadata', 'name').match?(/#{agent_name}-code-v\d+/)
              end

              # Sort by version number (descending)
              sorted_cms = versioned_cms.sort_by do |cm|
                version_str = cm.dig('metadata', 'annotations', 'langop.io/version') || 'v0'
                -version_str.sub(/^v/, '').to_i # Negative for descending sort
              end

              # Delete old versions beyond keep_last
              to_delete = sorted_cms[keep_last..] || []
              to_delete.each do |cm|
                cm_name = cm.dig('metadata', 'name')
                begin
                  ctx.client.delete_resource('ConfigMap', cm_name, ctx.namespace)
                  Formatters::ProgressFormatter.info("Cleaned up old version '#{cm_name}'")
                rescue StandardError => e
                  Formatters::ProgressFormatter.warn("Could not delete old ConfigMap '#{cm_name}': #{e.message}")
                end
              end
            end

            # Build full task code from task definition and body code
            #
            # @param task_definition [Object] Task definition with inputs/outputs
            # @param body_code [String] Task body code
            # @return [String] Complete task code
            def build_full_task_code(task_definition, body_code)
              inputs_str = (task_definition.inputs || {}).map { |k, v| "#{k}: '#{v}'" }.join(', ')
              outputs_str = (task_definition.outputs || {}).map { |k, v| "#{k}: '#{v}'" }.join(', ')

              # Indent the body code properly (2 spaces)
              body_lines = body_code.strip.lines
              indented_body = body_lines.map { |line| "  #{line}" }.join
              indented_body += "\n" unless indented_body.end_with?("\n")

              <<~RUBY
                task :#{task_definition.name},
                     inputs: { #{inputs_str} },
                     outputs: { #{outputs_str} } do |inputs|
                #{indented_body}end
              RUBY
            end

            # Replace a task definition in agent code
            #
            # @param code [String] Full agent code
            # @param task_name [String, Symbol] Task name to replace
            # @param new_task_code [String] New task code
            # @return [String] Updated agent code
            def replace_task_in_code(code, task_name, new_task_code)
              # Match the task definition including any trailing do block
              # Pattern matches: task :name, ... (neural) or task :name, ... do |inputs| ... end (symbolic)
              task_pattern = /task\s+:#{Regexp.escape(task_name.to_s)},?\s*.*?(?=\n\s*(?:task\s+:|main\s+do|end\s*$))/m

              raise "Could not find task ':#{task_name}' in agent code" unless code.match?(task_pattern)

              # Ensure new_task_code has proper trailing newline
              new_code = "#{new_task_code.strip}\n\n"

              code.gsub(task_pattern, new_code.strip)
            end

            # Restart agent pod by deleting it (Deployment will recreate)
            #
            # @param ctx [ClusterContext] Cluster context
            # @param agent_name [String] Agent name
            def restart_agent_pod(ctx, agent_name)
              # Find pods for this agent
              pods = ctx.client.list_resources('Pod', namespace: ctx.namespace, label_selector: "app=#{agent_name}")

              pods.each do |pod|
                pod_name = pod.dig('metadata', 'name')
                begin
                  ctx.client.delete_resource('Pod', pod_name, ctx.namespace)
                  Formatters::ProgressFormatter.info("Restarting pod '#{pod_name}'")
                rescue StandardError => e
                  Formatters::ProgressFormatter.warn("Could not delete pod '#{pod_name}': #{e.message}")
                end
              end
            end
          end
        end
      end
    end
  end
end
