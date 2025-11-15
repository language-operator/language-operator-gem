# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Helpers
      # Helper module for checking which agents depend on specific resources
      # (tools, models, personas). Used by CLI commands to warn before deletion.
      module ResourceDependencyChecker
        # Find agents that use a specific tool
        #
        # @param agents [Array<Hash>] Array of agent resources from kubectl
        # @param tool_name [String] Name of the tool to check
        # @return [Array<Hash>] Agents that reference this tool
        def self.agents_using_tool(agents, tool_name)
          agents.select do |agent|
            agent_tools = agent.dig('spec', 'tools') || []
            agent_tools.include?(tool_name)
          end
        end

        # Find agents that use a specific language model
        #
        # @param agents [Array<Hash>] Array of agent resources from kubectl
        # @param model_name [String] Name of the model to check
        # @return [Array<Hash>] Agents that reference this model
        def self.agents_using_model(agents, model_name)
          agents.select do |agent|
            agent_model_refs = agent.dig('spec', 'modelRefs') || []
            agent_models = agent_model_refs.map { |ref| ref['name'] }
            agent_models.include?(model_name)
          end
        end

        # Find agents that use a specific persona
        #
        # @param agents [Array<Hash>] Array of agent resources from kubectl
        # @param persona_name [String] Name of the persona to check
        # @return [Array<Hash>] Agents that reference this persona
        def self.agents_using_persona(agents, persona_name)
          agents.select do |agent|
            agent.dig('spec', 'persona') == persona_name
          end
        end

        # Count how many agents use a specific tool
        #
        # @param agents [Array<Hash>] Array of agent resources
        # @param tool_name [String] Name of the tool
        # @return [Integer] Count of agents using this tool
        def self.tool_usage_count(agents, tool_name)
          agents_using_tool(agents, tool_name).size
        end
      end
    end
  end
end
