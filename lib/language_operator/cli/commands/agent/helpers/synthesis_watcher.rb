# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module Agent
        module Helpers
          # Helper methods for watching agent synthesis status
          module SynthesisWatcher
            # Watch synthesis status with progress spinner
            #
            # @param k8s [Kubernetes::Client] Kubernetes client
            # @param agent_name [String] Agent name
            # @param namespace [String] Namespace
            # @return [Hash] Synthesis result with success status and metadata
            def watch_synthesis_status(k8s, agent_name, namespace)
              max_wait = 600 # Wait up to 10 minutes (local models can be slow)
              interval = 2   # Check every 2 seconds
              elapsed = 0
              start_time = Time.now
              synthesis_data = {}

              Formatters::ProgressFormatter.with_spinner('Synthesizing code from instructions') do
                synthesis_result = nil
                loop do
                  status = check_synthesis_status(k8s, agent_name, namespace, synthesis_data, start_time)
                  if status
                    synthesis_result = status
                    break
                  end

                  # Timeout check
                  if elapsed >= max_wait
                    Formatters::ProgressFormatter.warn('Synthesis taking longer than expected, continuing in background...')
                    puts
                    puts 'Check synthesis status with:'
                    puts "  aictl agent inspect #{agent_name}"
                    synthesis_result = { success: true, timeout: true }
                    break
                  end

                  sleep interval
                  elapsed += interval
                end
                synthesis_result
              rescue K8s::Error::NotFound
                # Agent not found yet, keep waiting
                sleep interval
                elapsed += interval
                retry if elapsed < max_wait

                Formatters::ProgressFormatter.error('Agent resource not found')
                return { success: false }
              rescue StandardError => e
                Formatters::ProgressFormatter.warn("Could not watch synthesis: #{e.message}")
                return { success: true } # Continue anyway
              end
            end

            # Check synthesis status for a specific agent
            #
            # @param k8s [Kubernetes::Client] Kubernetes client
            # @param agent_name [String] Agent name
            # @param namespace [String] Namespace
            # @param synthesis_data [Hash] Hash to populate with synthesis metadata
            # @param start_time [Time] Synthesis start time
            # @return [Hash, nil] Synthesis status or nil if not complete
            def check_synthesis_status(k8s, agent_name, namespace, synthesis_data, start_time)
              agent = k8s.get_resource('LanguageAgent', agent_name, namespace)
              conditions = agent.dig('status', 'conditions') || []
              synthesis_status = agent.dig('status', 'synthesis')

              # Capture synthesis metadata
              if synthesis_status
                synthesis_data[:model] = synthesis_status['model']
                synthesis_data[:token_count] = synthesis_status['tokenCount']
              end

              # Check for synthesis completion
              synthesized = conditions.find { |c| c['type'] == 'Synthesized' }
              return nil unless synthesized

              if synthesized['status'] == 'True'
                duration = Time.now - start_time
                { success: true, duration: duration, **synthesis_data }
              elsif synthesized['status'] == 'False'
                Formatters::ProgressFormatter.error("Synthesis failed: #{synthesized['message']}")
                { success: false }
              end
            end
          end
        end
      end
    end
  end
end
