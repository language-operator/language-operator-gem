# frozen_string_literal: true

require_relative 'cluster_validator'

module LanguageOperator
  module CLI
    module Helpers
      # Encapsulates cluster context (name, config, client) to reduce boilerplate
      # in command implementations.
      #
      # Instead of repeating:
      #   cluster = ClusterValidator.get_cluster(options[:cluster])
      #   cluster_config = ClusterValidator.get_cluster_config(cluster)
      #   k8s = ClusterValidator.kubernetes_client(options[:cluster])
      #
      # Use:
      #   ctx = ClusterContext.from_options(options)
      #   # Access: ctx.name, ctx.config, ctx.client, ctx.namespace
      class ClusterContext
        attr_reader :name, :config, :client, :namespace

        # Create ClusterContext from command options hash
        # @param options [Hash] Thor command options (expects :cluster key)
        # @return [ClusterContext] Initialized context
        def self.from_options(options)
          name = ClusterValidator.get_cluster(options[:cluster])
          config = ClusterValidator.get_cluster_config(name)
          client = ClusterValidator.kubernetes_client(options[:cluster])
          new(name, config, client)
        end

        # Initialize with cluster details
        # @param name [String] Cluster name
        # @param config [Hash] Cluster configuration
        # @param client [LanguageOperator::Kubernetes::Client] K8s client
        def initialize(name, config, client)
          @name = name
          @config = config
          @client = client
          @namespace = config[:namespace]
        end

        # Build kubectl command args for this cluster context
        # @return [Hash] kubectl arguments
        def kubectl_args
          {
            kubeconfig: config[:kubeconfig] ? "--kubeconfig=#{config[:kubeconfig]}" : '',
            context: config[:context] ? "--context=#{config[:context]}" : '',
            namespace: "-n #{namespace}"
          }
        end

        # Build kubectl command prefix string
        # @return [String] kubectl command prefix
        def kubectl_prefix
          args = kubectl_args
          "kubectl #{args[:kubeconfig]} #{args[:context]} #{args[:namespace]}".strip.squeeze(' ')
        end
      end
    end
  end
end
