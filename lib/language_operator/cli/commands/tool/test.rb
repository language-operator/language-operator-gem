# frozen_string_literal: true

require 'net/http'

module LanguageOperator
  module CLI
    module Commands
      module Tool
        # Tool testing commands
        module Test
          def self.included(base)
            base.class_eval do
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
            end
          end
        end
      end
    end
  end
end
