# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/commands/agent/base'

RSpec.describe LanguageOperator::CLI::Commands::Agent::Base do
  let(:command) { described_class.new }

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
          kubeconfig: '/tmp/kubeconfig2',
          context: 'context2'
        }
      ]
    end

    let(:mock_client1) { double('K8s Client 1') }
    let(:mock_client2) { double('K8s Client 2') }

    let(:mock_agents) do
      [
        {
          'metadata' => {
            'name' => 'test-agent-1',
            'namespace' => 'default'
          },
          'spec' => {
            'mode' => 'scheduled'
          },
          'status' => {
            'phase' => 'Running',
            'nextRun' => '2025-11-23T10:00:00Z',
            'executionCount' => 5
          }
        },
        {
          'metadata' => {
            'name' => 'test-agent-2',
            'namespace' => 'default'
          },
          'spec' => {
            'mode' => 'autonomous'
          },
          'status' => {
            'phase' => 'Running',
            'executionCount' => 12
          }
        }
      ]
    end

    before do
      # Mock cluster config
      allow(LanguageOperator::Config::ClusterConfig).to receive(:list_clusters).and_return(mock_clusters)
      allow(LanguageOperator::Config::ClusterConfig).to receive(:current_cluster).and_return('cluster1')

      # Mock cluster context helper
      allow(LanguageOperator::CLI::Helpers::ClusterContext).to receive(:from_options) do |options|
        cluster_name = options[:cluster] || 'cluster1'
        mock_clusters.find { |c| c[:name] == cluster_name }

        context = double('ClusterContext')
        allow(context).to receive(:name).and_return(cluster_name)
        allow(context).to receive(:namespace).and_return('default')

        client = cluster_name == 'cluster1' ? mock_client1 : mock_client2
        allow(context).to receive(:client).and_return(client)

        context
      end

      # Mock clients
      allow(mock_client1).to receive(:list_resources).with('LanguageAgent', namespace: 'default').and_return(mock_agents)
      allow(mock_client2).to receive(:list_resources).with('LanguageAgent', namespace: 'default').and_return([])

      # Mock formatters to capture output
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:info)
      allow(LanguageOperator::CLI::Formatters::TableFormatter).to receive(:agents)
      allow(LanguageOperator::CLI::Formatters::TableFormatter).to receive(:all_agents)

      # Suppress stdout
      allow($stdout).to receive(:puts)
    end

    context 'when listing agents in current cluster' do
      it 'calls list_cluster_agents with nil cluster' do
        expect(command).to receive(:list_cluster_agents).with(nil)
        command.list
      end

      it 'displays agents from current cluster' do
        expected_table_data = [
          {
            name: 'test-agent-1',
            mode: 'scheduled',
            status: 'Running',
            next_run: '2025-11-23T10:00:00Z',
            executions: 5
          },
          {
            name: 'test-agent-2',
            mode: 'autonomous',
            status: 'Running',
            next_run: 'N/A',
            executions: 12
          }
        ]

        expect(LanguageOperator::CLI::Formatters::TableFormatter).to receive(:agents).with(expected_table_data)
        command.list
      end
    end

    context 'when using --cluster option' do
      before do
        allow(command).to receive(:options).and_return({ cluster: 'cluster2' })
      end

      it 'calls list_cluster_agents with specified cluster' do
        expect(command).to receive(:list_cluster_agents).with('cluster2')
        command.list
      end

      it 'connects to specified cluster' do
        expect(LanguageOperator::CLI::Helpers::ClusterContext).to receive(:from_options).with({ cluster: 'cluster2' })
        command.list
      end
    end

    context 'when using --all-clusters option' do
      before do
        allow(command).to receive(:options).and_return({ all_clusters: true })
      end

      it 'calls list_all_clusters' do
        expect(command).to receive(:list_all_clusters)
        command.list
      end

      it 'queries all configured clusters' do
        # This would be tested inside list_all_clusters method
        # For now, just verify it's called
        expect(command).to receive(:list_all_clusters)
        command.list
      end
    end

    context 'when no agents exist' do
      before do
        allow(mock_client1).to receive(:list_resources).and_return([])
      end

      it 'displays helpful message' do
        expect($stdout).to receive(:puts).with(no_args)
        expect($stdout).to receive(:puts).with('Create an agent with:')
        expect($stdout).to receive(:puts).with('  aictl agent create "<description>"')
        command.list
      end
    end
  end
end
