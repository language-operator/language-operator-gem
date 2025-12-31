# frozen_string_literal: true

module LanguageOperator
  module Constants
    # Kubernetes label constants and builder methods for consistent metadata across all resources
    module KubernetesLabels
      # Standard Kubernetes labels
      NAME = 'app.kubernetes.io/name'
      COMPONENT = 'app.kubernetes.io/component'
      MANAGED_BY = 'app.kubernetes.io/managed-by'
      PART_OF = 'app.kubernetes.io/part-of'
      VERSION = 'app.kubernetes.io/version'

      # Language Operator specific values
      PROJECT_NAME = 'language-operator'
      MANAGED_BY_AICTL = 'langop'
      COMPONENT_AGENT = 'agent'
      COMPONENT_TEST_AGENT = 'test-agent'

      # Custom Language Operator labels
      TOOL_LABEL = 'langop.io/tool'
      LEARNING_DISABLED_LABEL = 'langop.io/learning-disabled'
      KIND_LABEL = 'langop.io/kind'
      CLUSTER_LABEL = 'langop.io/cluster'

      class << self
        # Build standard agent labels for deployments and pods
        #
        # @param agent_name [String] The name of the agent
        # @return [Hash] Hash of labels for Kubernetes resources
        def agent_labels(agent_name)
          {
            NAME => agent_name,
            COMPONENT => COMPONENT_AGENT,
            MANAGED_BY => MANAGED_BY_AICTL,
            PART_OF => PROJECT_NAME
          }
        end

        # Build test agent labels for temporary test pods
        #
        # @param name [String] The name of the test agent
        # @return [Hash] Hash of labels for test Kubernetes resources
        def test_agent_labels(name)
          {
            NAME => name,
            COMPONENT => COMPONENT_TEST_AGENT,
            MANAGED_BY => MANAGED_BY_AICTL,
            PART_OF => PROJECT_NAME
          }
        end

        # Build a label selector string for finding agent pods
        #
        # @param agent_name [String] The normalized agent name
        # @return [String] Label selector string for kubectl commands
        def agent_selector(agent_name)
          "#{NAME}=#{agent_name}"
        end

        # Build a label selector string for finding tool pods
        #
        # @param tool_name [String] The tool name
        # @return [String] Label selector string for kubectl commands
        def tool_selector(tool_name)
          "#{TOOL_LABEL}=#{tool_name}"
        end

        # Common cluster management labels
        #
        # @return [Hash] Hash of labels for cluster management resources
        def cluster_management_labels
          {
            MANAGED_BY => MANAGED_BY_AICTL
          }
        end
      end
    end
  end
end
