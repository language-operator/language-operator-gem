# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/commands/cluster'

RSpec.describe LanguageOperator::CLI::Commands::Cluster do
  let(:command) { described_class.new }

  describe '#create' do
    let(:mock_k8s_client) { double('K8s Client') }
    let(:mock_resource) { { 'apiVersion' => 'langop.io/v1alpha1', 'kind' => 'LanguageCluster' } }

    before do
      allow(LanguageOperator::Config::ClusterConfig).to receive(:cluster_exists?).and_return(false)
      allow(LanguageOperator::Kubernetes::Client).to receive(:new).and_return(mock_k8s_client)
      allow(mock_k8s_client).to receive(:current_namespace).and_return('default')
      allow(mock_k8s_client).to receive(:operator_installed?).and_return(true)
      allow(mock_k8s_client).to receive(:namespace_exists?).and_return(true)
      allow(mock_k8s_client).to receive(:current_context).and_return('test-context')
      allow(mock_k8s_client).to receive(:apply_resource).and_return(mock_resource)
      allow(LanguageOperator::Config::ClusterConfig).to receive(:add_cluster)
      allow(LanguageOperator::Config::ClusterConfig).to receive(:set_current_cluster)
      allow(LanguageOperator::Kubernetes::ResourceBuilder).to receive(:language_cluster).and_return(mock_resource)
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:with_spinner).and_yield
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:error)
      allow($stdout).to receive(:puts)
      allow(command).to receive(:format_cluster_details)
    end

    context 'with --domain option' do
      it 'passes domain to ResourceBuilder' do
        expect(LanguageOperator::Kubernetes::ResourceBuilder).to receive(:language_cluster)
          .with('test-cluster', namespace: 'default', domain: 'example.com')
          .and_return(mock_resource)

        allow(command).to receive(:options).and_return({ domain: 'example.com' })
        command.create('test-cluster')
      end
    end

    context 'with --dry-run and --domain' do
      it 'includes domain in dry-run output' do
        expect(LanguageOperator::Kubernetes::ResourceBuilder).to receive(:language_cluster)
          .with('test-cluster', namespace: 'default', domain: 'webhooks.test.com')
          .and_return(mock_resource)
        expect(mock_resource).to receive(:to_yaml)

        allow(command).to receive(:options).and_return({ dry_run: true, domain: 'webhooks.test.com' })
        command.create('test-cluster')
      end
    end

    context 'without --domain option' do
      it 'passes nil domain to ResourceBuilder' do
        expect(LanguageOperator::Kubernetes::ResourceBuilder).to receive(:language_cluster)
          .with('test-cluster', namespace: 'default', domain: nil)
          .and_return(mock_resource)

        allow(command).to receive(:options).and_return({})
        command.create('test-cluster')
      end
    end
  end

  describe '#list' do
    let(:mock_clusters) do
      [
        {
          name: 'cluster1',
          namespace: 'default',
          kubeconfig: '/tmp/kubeconfig1',
          context: 'context1'
        },
        {
          name: 'cluster2',
          namespace: 'default',
          kubeconfig: '/tmp/kubeconfig1', # Same kubeconfig/context as cluster1
          context: 'context1'
        },
        {
          name: 'cluster3',
          namespace: 'default',
          kubeconfig: '/tmp/kubeconfig2', # Different kubeconfig/context
          context: 'context2'
        }
      ]
    end

    let(:mock_client1) { double('K8s Client 1') }
    let(:mock_client2) { double('K8s Client 2') }

    before do
      allow(LanguageOperator::Config::ClusterConfig).to receive(:list_clusters).and_return(mock_clusters)
      allow(LanguageOperator::Config::ClusterConfig).to receive(:current_cluster).and_return('cluster1')
      allow(LanguageOperator::Config::ClusterConfig).to receive(:get_cluster) do |name|
        mock_clusters.find { |c| c[:name] == name }
      end

      # Mock kubeconfig validation to not exit
      allow(LanguageOperator::CLI::Helpers::ClusterValidator).to receive(:validate_kubeconfig!)

      # Mock file existence checks
      allow(File).to receive(:exist?).with('/tmp/kubeconfig1').and_return(true)
      allow(File).to receive(:exist?).with('/tmp/kubeconfig2').and_return(true)

      # Mock Kubernetes client creation
      allow(LanguageOperator::Kubernetes::Client).to receive(:new)
        .with(kubeconfig: '/tmp/kubeconfig1', context: 'context1')
        .and_return(mock_client1)
      allow(LanguageOperator::Kubernetes::Client).to receive(:new)
        .with(kubeconfig: '/tmp/kubeconfig2', context: 'context2')
        .and_return(mock_client2)

      # Mock API calls to return empty arrays
      [mock_client1, mock_client2].each do |client|
        allow(client).to receive(:list_resources).and_return([])
        allow(client).to receive(:get_resource).and_return({})
      end

      # Mock table formatter to avoid output
      allow(LanguageOperator::CLI::Formatters::TableFormatter).to receive(:clusters)

      # Suppress stdout
      allow($stdout).to receive(:puts)
    end

    context 'client caching behavior' do
      it 'reuses clients for clusters with same kubeconfig:context' do
        # Cluster1 and cluster2 share the same kubeconfig:context, so should reuse client
        expect(LanguageOperator::Kubernetes::Client).to receive(:new)
          .with(kubeconfig: '/tmp/kubeconfig1', context: 'context1')
          .once.and_return(mock_client1)

        # Cluster3 has different kubeconfig:context, so needs separate client
        expect(LanguageOperator::Kubernetes::Client).to receive(:new)
          .with(kubeconfig: '/tmp/kubeconfig2', context: 'context2')
          .once.and_return(mock_client2)

        command.list
      end

      it 'creates correct cache keys' do
        cache_keys = []
        allow(LanguageOperator::Kubernetes::Client).to receive(:new) do |args|
          cache_key = "#{args[:kubeconfig]}:#{args[:context]}"
          cache_keys << cache_key
          mock_client1
        end

        command.list

        expect(cache_keys).to contain_exactly(
          '/tmp/kubeconfig1:context1',
          '/tmp/kubeconfig2:context2'
        )
      end
    end
  end
end
