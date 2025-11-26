# frozen_string_literal: true

require 'k8s-ruby'
require 'yaml'
require_relative '../utils/secure_path'

module LanguageOperator
  module Kubernetes
    # Kubernetes client wrapper for interacting with language-operator resources
    class Client
      attr_reader :client

      # Get singleton K8s client instance with automatic config detection
      # @return [LanguageOperator::Kubernetes::Client] Client instance
      # @raise [RuntimeError] if client initialization fails
      def self.instance
        @instance ||= build_singleton
      end

      # Reset the singleton (useful for testing)
      # @return [nil]
      def self.reset!
        @instance = nil
      end

      # Check if running inside a Kubernetes cluster
      # @return [Boolean] True if in-cluster, false otherwise
      def self.in_cluster?
        File.exist?('/var/run/secrets/kubernetes.io/serviceaccount/token')
      end

      def initialize(kubeconfig: nil, context: nil, in_cluster: false)
        @in_cluster = in_cluster
        @kubeconfig = kubeconfig || ENV.fetch('KUBECONFIG', LanguageOperator::Utils::SecurePath.expand_home_path('.kube/config'))
        @context = context
        @client = build_client
      end

      # Get the current Kubernetes context name
      def current_context
        return nil if @in_cluster

        config = K8s::Config.load_file(@kubeconfig)
        @context || config.current_context
      rescue Errno::ENOENT
        nil
      end

      # Get the current namespace from the context.
      # Returns the namespace from service account (in-cluster) or kubeconfig context.
      # Gracefully handles all filesystem errors and returns nil on failure.
      #
      # @return [String, nil] the current namespace, or nil if unable to determine
      def current_namespace
        if @in_cluster
          # In-cluster: read from service account namespace
          File.read('/var/run/secrets/kubernetes.io/serviceaccount/namespace').strip
        else
          config = K8s::Config.load_file(@kubeconfig)
          context_name = current_context
          context_obj = config.context(context_name)
          context_obj&.namespace
        end
      rescue SystemCallError, IOError
        nil
      end

      # Create or update a Kubernetes resource
      def apply_resource(resource)
        namespace = resource.dig('metadata', 'namespace')
        name = resource.dig('metadata', 'name')
        kind = resource['kind']
        api_version = resource['apiVersion']

        begin
          # Try to get existing resource
          existing = get_resource(kind, name, namespace, api_version)
          if existing
            # Merge existing metadata (especially resourceVersion) with new resource
            merged_resource = if resource.is_a?(Hash)
                                resource.dup
                              else
                                resource.to_h
                              end
            merged_resource['metadata'] ||= {}
            merged_resource['metadata']['resourceVersion'] = existing.metadata.resourceVersion
            merged_resource['metadata']['uid'] = existing.metadata.uid if existing.metadata.uid

            # Update existing resource
            update_resource(kind, name, namespace, merged_resource, api_version)
          else
            # Create new resource
            create_resource(resource)
          end
        rescue K8s::Error::NotFound
          # Resource doesn't exist, create it
          create_resource(resource)
        end
      end

      # Create a resource
      def create_resource(resource)
        resource_client = resource_client_for_resource(resource)
        # Convert hash to K8s::Resource if needed
        k8s_resource = if resource.is_a?(K8s::Resource)
                         resource
                       else
                         # Remove resourceVersion if present - it should not be set on new resources
                         resource_hash = resource.dup
                         resource_hash['metadata']&.delete('resourceVersion')
                         K8s::Resource.new(resource_hash)
                       end
        resource_client.create_resource(k8s_resource)
      end

      # Update a resource
      def update_resource(kind, _name, namespace, resource, api_version)
        resource_client = resource_client_for(kind, namespace, api_version)
        # Convert hash to K8s::Resource if needed
        k8s_resource = resource.is_a?(K8s::Resource) ? resource : K8s::Resource.new(resource)
        resource_client.update_resource(k8s_resource)
      end

      # Get a resource
      def get_resource(kind, name, namespace = nil, api_version = nil)
        resource_client = resource_client_for(kind, namespace, api_version || default_api_version(kind))
        resource_client.get(name)
      end

      # List resources
      def list_resources(kind, namespace: nil, api_version: nil, label_selector: nil)
        resource_client = resource_client_for(kind, namespace, api_version || default_api_version(kind))
        opts = {}
        opts[:labelSelector] = label_selector if label_selector

        resource_client.list(**opts)
      end

      # Delete a resource
      def delete_resource(kind, name, namespace = nil, api_version = nil)
        resource_client = resource_client_for(kind, namespace, api_version || default_api_version(kind))
        resource_client.delete(name)
      end

      # Check if namespace exists
      def namespace_exists?(name)
        @client.api('v1').resource('namespaces').get(name)
        true
      rescue K8s::Error::NotFound
        false
      end

      # Create namespace
      def create_namespace(name, labels: {})
        resource = {
          'apiVersion' => 'v1',
          'kind' => 'Namespace',
          'metadata' => {
            'name' => name,
            'labels' => labels
          }
        }
        create_resource(resource)
      end

      # Check if operator is installed
      def operator_installed?
        # Check if LanguageCluster CRD exists
        @client.apis(prefetch_resources: true)
               .find { |api| api.api_version == 'langop.io/v1alpha1' }
      rescue StandardError
        false
      end

      # Get operator version
      def operator_version
        deployment = @client.api('apps/v1')
                            .resource('deployments', namespace: 'kube-system')
                            .get(Constants::KubernetesLabels::PROJECT_NAME)
        deployment.dig('metadata', 'labels', Constants::KubernetesLabels::VERSION) || 'unknown'
      rescue K8s::Error::NotFound
        nil
      end

      private

      # Build singleton instance with automatic config detection
      def self.build_singleton
        if in_cluster?
          new(in_cluster: true)
        else
          new
        end
      rescue StandardError => e
        raise "Failed to initialize Kubernetes client: #{e.message}"
      end
      private_class_method :build_singleton

      def build_client
        if @in_cluster
          K8s::Client.in_cluster_config
        else
          config = K8s::Config.load_file(@kubeconfig)
          if @context
            # Set the current-context to the specified context
            config_hash = config.to_h
            config_hash['current-context'] = @context
            config = K8s::Config.new(**config_hash)
          end
          K8s::Client.config(config)
        end
      end

      def resource_client_for_resource(resource)
        kind = resource['kind']
        namespace = resource.dig('metadata', 'namespace')
        api_version = resource['apiVersion']
        resource_client_for(kind, namespace, api_version)
      end

      def resource_client_for(kind, namespace, api_version)
        api_client = api_for_version(api_version)
        resource_name = kind_to_resource_name(kind)
        if namespace
          api_client.resource(resource_name, namespace: namespace)
        else
          api_client.resource(resource_name)
        end
      end

      def api_for_version(api_version)
        if api_version.include?('/')
          group, version = api_version.split('/', 2)
          @client.api("#{group}/#{version}")
        else
          @client.api(api_version)
        end
      end

      def kind_to_resource_name(kind)
        # Convert Kind (singular, capitalized) to resource name (plural, lowercase)
        case kind.downcase
        when 'languagecluster'
          'languageclusters'
        when 'languageagent'
          'languageagents'
        when 'languagetool'
          'languagetools'
        when 'languagemodel'
          'languagemodels'
        when 'languageclient'
          'languageclients'
        when 'languagepersona'
          'languagepersonas'
        when 'namespace'
          'namespaces'
        when 'configmap'
          'configmaps'
        when 'secret'
          'secrets'
        when 'service'
          'services'
        when 'deployment'
          'deployments'
        when 'statefulset'
          'statefulsets'
        when 'cronjob'
          'cronjobs'
        else
          # Generic pluralization - add 's'
          "#{kind.downcase}s"
        end
      end

      def default_api_version(kind)
        case kind.downcase
        when 'languagecluster', 'languageagent', 'languagetool', 'languagemodel', 'languageclient', 'languagepersona'
          'langop.io/v1alpha1'
        when 'namespace', 'configmap', 'secret', 'service'
          'v1'
        when 'deployment', 'statefulset'
          'apps/v1'
        when 'cronjob'
          'batch/v1'
        else
          'v1'
        end
      end
    end
  end
end
