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
      allow(mock_k8s_client).to receive(:get_resource).and_return(nil) # For cluster existence check
      # Mock for auto-organization detection
      allow(mock_k8s_client).to receive(:list_namespaces).with(label_selector: 'langop.io/type=organization').and_return([
        {
          'metadata' => {
            'name' => 'default-org',
            'labels' => {
              'langop.io/type' => 'organization',
              'langop.io/organization-id' => 'test-org-123'
            }
          }
        }
      ])
      # Mock for finding the specific organization namespace
      allow(mock_k8s_client).to receive(:list_namespaces).with(label_selector: 'langop.io/organization-id=test-org-123').and_return([
        {
          'metadata' => {
            'name' => 'default',
            'labels' => {
              'langop.io/organization-id' => 'test-org-123'
            }
          }
        }
      ])
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
          .with('test-cluster', hash_including(namespace: 'default', domain: 'example.com'))
          .and_return(mock_resource)

        allow(command).to receive(:options).and_return({ domain: 'example.com' })
        command.create('test-cluster')
      end
    end

    context 'with --dry-run and --domain' do
      it 'includes domain in dry-run output' do
        expect(LanguageOperator::Kubernetes::ResourceBuilder).to receive(:language_cluster)
          .with('test-cluster', hash_including(namespace: 'default', domain: 'webhooks.test.com'))
          .and_return(mock_resource)
        expect(mock_resource).to receive(:to_yaml)

        allow(command).to receive(:options).and_return({ dry_run: true, domain: 'webhooks.test.com' })
        command.create('test-cluster')
      end
    end

    context 'without --domain option' do
      it 'passes nil domain to ResourceBuilder' do
        expect(LanguageOperator::Kubernetes::ResourceBuilder).to receive(:language_cluster)
          .with('test-cluster', hash_including(namespace: 'default', domain: nil))
          .and_return(mock_resource)

        allow(command).to receive(:options).and_return({})
        command.create('test-cluster')
      end
    end

    context 'domain display in cluster details' do
      it 'includes domain in format_cluster_details when provided' do
        expect(command).to receive(:format_cluster_details) do |args|
          expect(args[:domain]).to eq('example.com')
          expect(args[:name]).to eq('test-cluster')
          expect(args[:namespace]).to eq('default')
        end

        allow(command).to receive(:options).and_return({ domain: 'example.com' })
        command.create('test-cluster')
      end

      it 'passes nil domain to format_cluster_details when not provided' do
        expect(command).to receive(:format_cluster_details) do |args|
          expect(args[:domain]).to be_nil
          expect(args[:name]).to eq('test-cluster')
        end

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

      # Mock API calls to return empty arrays and cluster resources with domains
      [mock_client1, mock_client2].each do |client|
        allow(client).to receive(:list_resources).and_return([])
        allow(client).to receive(:get_resource).and_return({
                                                             'status' => { 'phase' => 'Ready' },
                                                             'spec' => { 'domain' => 'agents.example.com' }
                                                           })
      end

      # Mock table formatter to avoid output
      allow(LanguageOperator::CLI::Formatters::TableFormatter).to receive(:clusters)

      # Suppress stdout
      allow($stdout).to receive(:puts)
    end

    context 'client caching behavior' do
      xit 'reuses clients for clusters with same kubeconfig:context' do
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

    context 'domain extraction and display' do
      it 'extracts domain from cluster resources' do
        expect(LanguageOperator::CLI::Formatters::TableFormatter).to receive(:clusters) do |table_data|
          expect(table_data).to all(have_key(:domain))
          expect(table_data.first[:domain]).to eq('agents.example.com')
        end

        command.list
      end

      it 'handles clusters without domains' do
        # Mock one client to return cluster without domain
        allow(mock_client1).to receive(:get_resource).and_return({
                                                                   'status' => { 'phase' => 'Ready' },
                                                                   'spec' => {}
                                                                 })

        expect(LanguageOperator::CLI::Formatters::TableFormatter).to receive(:clusters) do |table_data|
          cluster1_data = table_data.find { |c| c[:name].include?('cluster1') }
          expect(cluster1_data[:domain]).to be_nil
        end

        command.list
      end

      it 'shows error indicators for inaccessible clusters' do
        # Mock one client to raise error
        allow(mock_client1).to receive(:get_resource).and_raise(StandardError, 'Connection failed')

        expect(LanguageOperator::CLI::Formatters::TableFormatter).to receive(:clusters) do |table_data|
          error_clusters = table_data.select { |c| c[:domain] == '?' }
          expect(error_clusters.count).to eq(2) # cluster1 and cluster2 share same client
        end

        command.list
      end
    end
  end
end
