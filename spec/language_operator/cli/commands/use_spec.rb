# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/commands/use'

RSpec.describe LanguageOperator::CLI::Commands::Use do
  let(:command) { described_class.new }
  let(:cluster_name) { 'test-cluster' }
  let(:cluster_config) do
    {
      name: cluster_name,
      namespace: 'test-namespace',
      context: 'test-context',
      kubeconfig: '/tmp/kubeconfig',
      created: '2025-11-25T12:00:00Z'
    }
  end
  let(:mock_k8s_client) { double('K8s Client') }
  let(:cluster_resource) do
    {
      'status' => { 'phase' => 'Ready' },
      'spec' => { 'domain' => 'agents.example.com' }
    }
  end

  before do
    allow(LanguageOperator::Config::ClusterConfig).to receive(:cluster_exists?).and_return(true)
    allow(LanguageOperator::Config::ClusterConfig).to receive(:set_current_cluster)
    allow(LanguageOperator::Config::ClusterConfig).to receive(:get_cluster).and_return(cluster_config)
    allow(LanguageOperator::CLI::Helpers::ClusterValidator).to receive(:kubernetes_client).and_return(mock_k8s_client)
    allow(mock_k8s_client).to receive(:get_resource).and_return(cluster_resource)
    allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:success)
    allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:error)
    allow(command).to receive(:format_cluster_details)
    allow($stdout).to receive(:puts)
  end

  describe '#switch' do
    context 'when cluster exists' do
      it 'switches to cluster and displays details with domain' do
        expect(LanguageOperator::Config::ClusterConfig).to receive(:set_current_cluster).with(cluster_name)
        expect(command).to receive(:format_cluster_details) do |args|
          expect(args[:name]).to eq(cluster_name)
          expect(args[:namespace]).to eq('test-namespace')
          expect(args[:context]).to eq('test-context')
          expect(args[:domain]).to eq('agents.example.com')
          expect(args[:status]).to eq('Ready')
          expect(args[:created]).to eq('2025-11-25T12:00:00Z')
        end

        command.switch(cluster_name)
      end

      it 'handles cluster without domain' do
        cluster_without_domain = {
          'status' => { 'phase' => 'Ready' },
          'spec' => {}
        }
        allow(mock_k8s_client).to receive(:get_resource).and_return(cluster_without_domain)

        expect(command).to receive(:format_cluster_details) do |args|
          expect(args[:domain]).to be_nil
          expect(args[:status]).to eq('Ready')
        end

        command.switch(cluster_name)
      end

      it 'handles kubernetes connection errors gracefully' do
        allow(LanguageOperator::CLI::Helpers::ClusterValidator)
          .to receive(:kubernetes_client).and_raise(StandardError, 'Connection failed')

        expect(command).to receive(:format_cluster_details) do |args|
          expect(args[:name]).to eq(cluster_name)
          expect(args[:status]).to eq('Connection Error')
          expect(args).not_to have_key(:domain)
        end

        command.switch(cluster_name)
      end

      it 'shows success message' do
        expect(LanguageOperator::CLI::Formatters::ProgressFormatter)
          .to receive(:success).with("Switched to cluster 'test-cluster'")

        command.switch(cluster_name)
      end
    end

    context 'when cluster does not exist' do
      let(:available_clusters) { [{ name: 'cluster1' }, { name: 'cluster2' }] }

      before do
        allow(LanguageOperator::Config::ClusterConfig).to receive(:cluster_exists?).and_return(false)
        allow(LanguageOperator::Config::ClusterConfig).to receive(:list_clusters).and_return(available_clusters)
        allow(command).to receive(:exit)
        
        # Mock Kubernetes client for find_cluster_in_kubernetes method
        mock_find_k8s_client = double('K8s Client for find')
        allow(LanguageOperator::Kubernetes::Client).to receive(:new).and_return(mock_find_k8s_client)
        allow(mock_find_k8s_client).to receive(:list_resources).with('LanguageCluster', namespace: nil).and_return([])
      end

      it 'shows error and lists available clusters' do
        expect(LanguageOperator::CLI::Formatters::ProgressFormatter)
          .to receive(:error).with("Cluster 'test-cluster' not found")
        expect($stdout).to receive(:puts).with("\nAvailable clusters:")
        expect($stdout).to receive(:puts).with('  - cluster1')
        expect($stdout).to receive(:puts).with('  - cluster2')
        expect(command).to receive(:exit).with(1)

        command.switch(cluster_name)
      end
    end
  end
end
