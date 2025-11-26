# frozen_string_literal: true

require_relative '../../constants/kubernetes_labels'

module LanguageOperator
  module CLI
    module Helpers
      # Utilities for working with Kubernetes labels
      module LabelUtils
        # Normalize an agent name for use as a Kubernetes label value
        #
        # Kubernetes label values must follow DNS-1123 subdomain format:
        # - contain only lowercase alphanumeric characters, '-' or '.'
        # - start and end with an alphanumeric character
        # - be at most 63 characters
        #
        # @param agent_name [String] The agent name to normalize
        # @return [String] A valid label value
        def self.normalize_agent_name(agent_name)
          # Agent names should already be valid Kubernetes resource names,
          # which are compatible with label values. Just ensure lowercase.
          agent_name.to_s.downcase
        end

        # Build a label selector for finding agent pods
        #
        # @param agent_name [String] The agent name
        # @return [String] A label selector string
        def self.agent_pod_selector(agent_name)
          normalized_name = normalize_agent_name(agent_name)
          Constants::KubernetesLabels.agent_selector(normalized_name)
        end

        # Validate that an agent name will work as a label value
        #
        # @param agent_name [String] The agent name to validate
        # @return [Boolean] true if valid, false otherwise
        def self.valid_label_value?(agent_name)
          return false if agent_name.nil? || agent_name.empty?

          # Check original string first (before normalization)
          agent_str = agent_name.to_s

          # Check DNS-1123 subdomain requirements:
          # - 63 characters or less
          # - lowercase letters, numbers, hyphens, and dots only
          # - start and end with alphanumeric character
          return false if agent_str.length > 63
          return false unless agent_str.match?(/\A[a-z0-9]([a-z0-9\-.]*[a-z0-9])?\z/)

          true
        end

        # Get debugging information about label selector matching
        #
        # @param ctx [ClusterContext] Kubernetes context
        # @param agent_name [String] Agent name being searched
        # @return [Hash] Debug information about the search
        def self.debug_pod_search(ctx, agent_name)
          selector = agent_pod_selector(agent_name)

          {
            agent_name: agent_name,
            normalized_name: normalize_agent_name(agent_name),
            label_selector: selector,
            namespace: ctx.namespace,
            valid_label_value: valid_label_value?(agent_name)
          }
        end

        # Convert deployment labels to pod selector and find matching pods
        #
        # This method handles the common pattern of extracting selector labels from a deployment,
        # converting them to a label selector string, and finding matching pods.
        #
        # @param ctx [ClusterContext] Kubernetes context with client and namespace
        # @param deployment_name [String] Name of the deployment (for error messages)
        # @param labels [Hash, Object] Deployment selector labels (may be K8s::Resource or Hash)
        # @return [Array] Array of pod resources matching the labels
        # @raise [RuntimeError] If labels are nil, empty, or no pods found
        def self.find_pods_by_deployment_labels(ctx, deployment_name, labels)
          raise "Deployment '#{deployment_name}' has no selector labels" if labels.nil?

          # Convert to hash if needed (K8s API may return K8s::Resource objects)
          labels_hash = labels.respond_to?(:to_h) ? labels.to_h : labels
          raise "Deployment '#{deployment_name}' has empty selector labels" if labels_hash.empty?

          # Convert labels to Kubernetes label selector format
          label_selector = labels_hash.map { |k, v| "#{k}=#{v}" }.join(',')

          # Find matching pods
          ctx.client.list_resources('Pod', namespace: ctx.namespace, label_selector: label_selector)
        end
      end
    end
  end
end
