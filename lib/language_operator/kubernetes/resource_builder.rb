# frozen_string_literal: true

module LanguageOperator
  module Kubernetes
    # Builds Kubernetes resource manifests for language-operator
    class ResourceBuilder
      class << self
        # Build a LanguageCluster resource
        def language_cluster(name, namespace: nil, labels: {})
          build_resource('LanguageCluster', name, {
                           'namespace' => namespace || name,
                           'resourceQuota' => default_resource_quota,
                           'networkPolicy' => default_network_policy
                         }, namespace: namespace, labels: labels)
        end

        # Build a LanguageAgent resource
        def language_agent(name, instructions:, cluster: nil, schedule: nil, persona: nil, tools: [], models: [],
                           mode: nil, workspace: true, labels: {})
          # Determine mode: reactive, scheduled, or autonomous
          spec_mode = mode || (schedule ? 'scheduled' : 'autonomous')

          spec = {
            'instructions' => instructions,
            'mode' => spec_mode,
            'image' => 'ghcr.io/language-operator/agent:latest'
          }

          spec['schedule'] = schedule if schedule
          spec['persona'] = persona if persona
          # Convert tool names to toolRef objects
          spec['toolRefs'] = tools.map { |t| { 'name' => t } } unless tools.empty?
          # Convert model names to modelRef objects
          spec['modelRefs'] = models.map { |m| { 'name' => m } } unless models.empty?
          # Enable workspace by default for state persistence
          spec['workspace'] = { 'enabled' => workspace } if workspace

          build_resource('LanguageAgent', name, spec, namespace: cluster, labels: labels)
        end

        # Build a LanguageTool resource
        def language_tool(name, type:, config: {}, cluster: nil, labels: {})
          build_resource('LanguageTool', name, {
                           'type' => type,
                           'config' => config
                         }, namespace: cluster, labels: labels)
        end

        # Build a LanguageModel resource
        def language_model(name, provider:, model:, endpoint: nil, cluster: nil, labels: {})
          spec = {
            'provider' => provider,
            'modelName' => model
          }
          spec['endpoint'] = endpoint if endpoint

          build_resource('LanguageModel', name, spec, namespace: cluster, labels: labels)
        end

        # Build a LanguagePersona resource
        def language_persona(name, description:, tone:, system_prompt:, cluster: nil, labels: {})
          build_resource('LanguagePersona', name, {
                           'displayName' => name.split('-').map(&:capitalize).join(' '),
                           'description' => description,
                           'tone' => tone,
                           'systemPrompt' => system_prompt
                         }, namespace: cluster, labels: labels)
        end

        # Build a LanguagePersona resource with full spec control
        def build_persona(name:, spec:, namespace: nil, labels: {})
          build_resource('LanguagePersona', name, spec, namespace: namespace, labels: labels)
        end

        # Build a Kubernetes Service resource for a reactive agent
        #
        # @param agent_name [String] Name of the agent
        # @param namespace [String] Kubernetes namespace
        # @param port [Integer] Service port (default: 8080)
        # @param labels [Hash] Additional labels
        # @return [Hash] Service manifest
        def agent_service(agent_name, namespace: nil, port: 8080, labels: {})
          {
            'apiVersion' => 'v1',
            'kind' => 'Service',
            'metadata' => {
              'name' => agent_name,
              'namespace' => namespace || 'default',
              'labels' => default_labels.merge(
                'app.kubernetes.io/name' => agent_name,
                'app.kubernetes.io/component' => 'agent'
              ).merge(labels)
            },
            'spec' => {
              'type' => 'ClusterIP',
              'selector' => {
                'app.kubernetes.io/name' => agent_name,
                'app.kubernetes.io/component' => 'agent'
              },
              'ports' => [
                {
                  'name' => 'http',
                  'protocol' => 'TCP',
                  'port' => port,
                  'targetPort' => port
                }
              ]
            }
          }
        end

        private

        # Build a standard language-operator Kubernetes resource
        #
        # @param kind [String] The Kubernetes resource kind
        # @param name [String] The resource name
        # @param spec [Hash] The resource spec
        # @param namespace [String, nil] The namespace (defaults to 'default')
        # @param labels [Hash] Additional labels to merge with defaults
        # @return [Hash] Complete Kubernetes resource manifest
        def build_resource(kind, name, spec, namespace: nil, labels: {})
          {
            'apiVersion' => 'langop.io/v1alpha1',
            'kind' => kind,
            'metadata' => {
              'name' => name,
              'namespace' => namespace || 'default',
              'labels' => default_labels.merge(labels)
            },
            'spec' => spec
          }
        end

        def default_labels
          {
            'app.kubernetes.io/managed-by' => 'aictl',
            'app.kubernetes.io/part-of' => 'language-operator'
          }
        end

        def default_resource_quota
          {
            'hard' => {
              'requests.cpu' => '4',
              'requests.memory' => '8Gi',
              'limits.cpu' => '8',
              'limits.memory' => '16Gi'
            }
          }
        end

        def default_network_policy
          {
            'egress' => {
              'allowDNS' => ['8.8.8.8/32', '8.8.4.4/32'],
              'allowHTTPS' => ['0.0.0.0/0']
            }
          }
        end
      end
    end
  end
end
