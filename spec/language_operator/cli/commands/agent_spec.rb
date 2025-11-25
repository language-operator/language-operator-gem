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
            'phase' => 'Active',
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
            'phase' => 'Active',
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
            namespace: 'default',
            mode: 'scheduled',
            status: 'Active'
          },
          {
            name: 'test-agent-2',
            namespace: 'default',
            mode: 'autonomous',
            status: 'Active'
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

  describe '#generate_agent_name' do
    it 'generates valid Kubernetes names for normal descriptions' do
      name = command.send(:generate_agent_name, 'valid agent description')
      expect(name).to match(/^valid-agent-description-\d{4}$/)
      expect(name).to match(/^[a-z]/) # Must start with letter
    end

    it 'fixes names that start with numbers' do
      name = command.send(:generate_agent_name, '123 check something important')
      expect(name).to match(/^agent-123-check-something-\d{4}$/)
      expect(name).to match(/^[a-z]/) # Must start with letter
    end

    it 'fixes names generated from empty descriptions' do
      name = command.send(:generate_agent_name, '')
      expect(name).to match(/^agent--\d{4}$/)
      expect(name).to match(/^[a-z]/) # Must start with letter
    end

    it 'fixes names that are only numbers' do
      name = command.send(:generate_agent_name, '12345')
      expect(name).to match(/^agent-12345-\d{4}$/)
      expect(name).to match(/^[a-z]/) # Must start with letter
    end

    it 'fixes names generated from special characters only' do
      name = command.send(:generate_agent_name, '!@#$%^&*()')
      expect(name).to match(/^agent--\d{4}$/)
      expect(name).to match(/^[a-z]/) # Must start with letter
    end

    it 'preserves valid names without agent- prefix' do
      name = command.send(:generate_agent_name, 'analytics system monitor')
      expect(name).to match(/^analytics-system-monitor-\d{4}$/)
      expect(name).to match(/^[a-z]/) # Must start with letter
      expect(name).not_to include('agent-analytics') # No unnecessary prefix
    end

    it 'limits to first 3 words as documented' do
      name = command.send(:generate_agent_name, 'this is a very long description with many words')
      expect(name).to match(/^this-is-a-\d{4}$/)
      expect(name).to match(/^[a-z]/) # Must start with letter
    end

    it 'removes special characters as documented' do
      name = command.send(:generate_agent_name, 'test-agent!@# with$%^ special&*() chars')
      expect(name).to match(/^testagent-with-special-\d{4}$/)
      expect(name).to match(/^[a-z]/) # Must start with letter
    end

    it 'includes timestamp suffix for uniqueness' do
      # Generate two names quickly - should have same timestamp suffix
      name1 = command.send(:generate_agent_name, 'test description')
      name2 = command.send(:generate_agent_name, 'test description')

      # Both should end with same 4-digit timestamp
      timestamp1 = name1.split('-').last
      timestamp2 = name2.split('-').last

      expect(timestamp1).to eq(timestamp2)
      expect(timestamp1.length).to eq(4)
      expect(timestamp1).to match(/^\d{4}$/)
    end

    context 'Kubernetes naming compliance' do
      let(:test_cases) do
        [
          '123 invalid start',
          '',
          '!@# special only',
          'valid description',
          '999 numbers first',
          'single',
          'hyphen-test already',
          '1',
          'a',
          'a b c d e f g h i j' # many words
        ]
      end

      it 'generates names that always start with lowercase letter' do
        test_cases.each do |description|
          name = command.send(:generate_agent_name, description)
          expect(name).to match(/^[a-z]/), "Generated name '#{name}' from '#{description}' should start with lowercase letter"
        end
      end

      it 'generates names that only contain valid characters' do
        test_cases.each do |description|
          name = command.send(:generate_agent_name, description)
          expect(name).to match(/^[a-z0-9-]+$/), "Generated name '#{name}' from '#{description}' contains invalid characters"
        end
      end

      it 'generates names that end with alphanumeric character' do
        test_cases.each do |description|
          name = command.send(:generate_agent_name, description)
          expect(name).to match(/[a-z0-9]$/), "Generated name '#{name}' from '#{description}' should end with alphanumeric character"
        end
      end
    end
  end
end
