# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module Agent
        module Helpers
          # Helper methods for parsing agent code from ConfigMaps
          module CodeParser
            # Load agent definition from ConfigMap
            #
            # @param ctx [ClusterContext] Cluster context
            # @param agent_name [String] Name of the agent
            # @return [Object, nil] Agent definition or nil if not found
            def load_agent_definition(ctx, agent_name)
              # Try to get the agent code ConfigMap
              configmap_name = "#{agent_name}-code"
              begin
                configmap = ctx.client.get_resource('ConfigMap', configmap_name, ctx.namespace)
                code_content = configmap.dig('data', 'agent.rb')

                return nil unless code_content

                # Parse the code to extract agent definition
                # For now, we'll create a mock definition with the task structure
                # In a full implementation, this would eval the code safely
                parse_agent_code(code_content)
              rescue K8s::Error::NotFound
                nil
              rescue StandardError => e
                @logger&.error("Failed to load agent definition: #{e.message}")
                nil
              end
            end

            # Parse agent code to extract definition
            #
            # @param code [String] Ruby agent code
            # @return [Object] Agent definition structure
            def parse_agent_code(code)
              require_relative '../../../../dsl/agent_definition'

              # Create a minimal agent definition structure
              agent_def = Struct.new(:tasks, :name, :mcp_servers) do
                def initialize
                  super({}, 'agent', {})
                end
              end

              agent = agent_def.new

              # Parse tasks from code - extract full task definitions
              code.scan(/task\s+:(\w+),?\s*(.*?)(?=\n\s*(?:task\s+:|main\s+do|end\s*$))/m) do |match|
                task_name = match[0].to_sym
                task_block = match[1]

                # Check if neural (has instructions but no do block) or symbolic
                is_neural = task_block.include?('instructions:') && !task_block.match?(/\bdo\s*\|/)

                # Extract instructions
                instructions = extract_string_value(task_block, 'instructions')

                # Extract inputs hash
                inputs = extract_hash_value(task_block, 'inputs')

                # Extract outputs hash
                outputs = extract_hash_value(task_block, 'outputs')

                task = Struct.new(:name, :neural?, :instructions, :inputs, :outputs).new(
                  task_name, is_neural, instructions, inputs, outputs
                )

                agent.tasks[task_name] = task
              end

              agent
            end

            # Extract a string value from DSL code (e.g., instructions: "...")
            #
            # @param code [String] Code snippet
            # @param key [String] Key to extract
            # @return [String] Extracted value or empty string
            def extract_string_value(code, key)
              # Match both single and double quoted strings, including multi-line
              match = code.match(/#{key}:\s*(['"])(.*?)\1/m) ||
                      code.match(/#{key}:\s*(['"])(.+?)\1/m)
              match ? match[2] : ''
            end

            # Extract a hash value from DSL code (e.g., inputs: { foo: 'bar' })
            #
            # @param code [String] Code snippet
            # @param key [String] Key to extract
            # @return [Hash] Extracted hash or empty hash
            def extract_hash_value(code, key)
              match = code.match(/#{key}:\s*\{([^}]*)\}/)
              return {} unless match

              hash_content = match[1].strip
              return {} if hash_content.empty?

              # Parse simple key: 'value' or key: "value" pairs
              result = {}
              hash_content.scan(/(\w+):\s*(['"])([^'"]*)\2/) do |k, _quote, v|
                result[k.to_sym] = v
              end
              result
            end
          end
        end
      end
    end
  end
end
