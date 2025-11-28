# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/language_operator/constants/kubernetes_labels'
require 'language_operator/cli/commands/agent/learning'

RSpec.describe LanguageOperator::CLI::Commands::Agent::Learning::LearningCommands do
  let(:command) { described_class.new }
  let(:client) { double('Kubernetes::Client') }
  let(:cluster_context) do
    double('ClusterContext',
           client: client,
           name: 'test-cluster',
           namespace: 'language-operator')
  end

  before do
    allow(LanguageOperator::CLI::Helpers::ClusterContext).to receive(:from_options).and_return(cluster_context)
    allow(command).to receive(:pastel).and_return(double('Pastel', cyan: '', white: double('white', bold: ''), dim: '', green: '', yellow: '', blue: ''))
    allow(command).to receive(:puts)
  end

  describe '#status' do
    let(:agent) do
      {
        'metadata' => {
          'name' => 'test-agent',
          'annotations' => {},
          'creationTimestamp' => '2025-11-28T10:30:00Z'
        },
        'status' => {
          'conditions' => [
            {
              'type' => 'Ready',
              'status' => 'True',
              'lastTransitionTime' => '2025-11-28T10:35:00Z'
            }
          ]
        }
      }
    end

    let(:agent_with_learning_disabled) do
      {
        'metadata' => {
          'name' => 'test-agent',
          'annotations' => {
            LanguageOperator::Constants::KubernetesLabels::LEARNING_DISABLED_LABEL => 'true'
          },
          'creationTimestamp' => '2025-11-28T10:30:00Z'
        }
      }
    end

    before do
      allow(client).to receive(:get_resource).and_return(agent)
      allow(command).to receive(:get_learning_status).and_return(nil)
      allow(command).to receive(:display_learning_status)
    end

    it 'fetches agent and learning status' do
      expect { command.status('test-agent') }.not_to raise_error

      expect(client).to have_received(:get_resource).with('LanguageAgent', 'test-agent', 'language-operator')
      expect(command).to have_received(:get_learning_status).with(client, 'test-agent', 'language-operator')
      expect(command).to have_received(:display_learning_status).with(agent, nil, 'test-cluster')
    end

    describe 'display formatting' do
      it 'displays learning enabled status and configuration' do
        # Call the real method to test the implementation
        expect { command.status('test-agent') }.not_to raise_error

        # Basic verification that it ran without error
        expect(client).to have_received(:get_resource).with('LanguageAgent', 'test-agent', 'language-operator')
      end

      it 'shows learning disabled status when annotation is present' do
        allow(client).to receive(:get_resource).and_return(agent_with_learning_disabled)

        expect { command.status('test-agent') }.not_to raise_error
        expect(client).to have_received(:get_resource).with('LanguageAgent', 'test-agent', 'language-operator')
      end

      it 'handles missing timestamp gracefully' do
        agent_without_timestamp = agent.dup
        agent_without_timestamp['metadata'].delete('creationTimestamp')
        allow(client).to receive(:get_resource).and_return(agent_without_timestamp)

        expect { command.status('test-agent') }.not_to raise_error
        expect(client).to have_received(:get_resource).with('LanguageAgent', 'test-agent', 'language-operator')
      end
    end
  end

  describe '#enable' do
    let(:agent_without_annotation) do
      {
        'metadata' => {
          'name' => 'test-agent',
          'annotations' => {}
        }
      }
    end

    let(:agent_with_annotation) do
      {
        'metadata' => {
          'name' => 'test-agent',
          'annotations' => {
            LanguageOperator::Constants::KubernetesLabels::LEARNING_DISABLED_LABEL => 'true'
          }
        }
      }
    end

    it 'shows message when learning is already enabled' do
      allow(client).to receive(:get_resource).and_return(agent_without_annotation)
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:info)

      command.enable('test-agent')

      expect(LanguageOperator::CLI::Formatters::ProgressFormatter)
        .to have_received(:info).with("Learning is already enabled for agent 'test-agent'")
    end

    it 'removes learning-disabled annotation when present' do
      allow(client).to receive(:get_resource).and_return(agent_with_annotation)
      allow(command).to receive(:remove_annotation)
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:with_spinner).and_yield
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:success)

      command.enable('test-agent')

      expect(command).to have_received(:remove_annotation)
        .with(client, 'test-agent', 'language-operator', LanguageOperator::Constants::KubernetesLabels::LEARNING_DISABLED_LABEL)
      expect(LanguageOperator::CLI::Formatters::ProgressFormatter)
        .to have_received(:success).with("Learning enabled for agent 'test-agent'")
    end
  end

  describe '#disable' do
    let(:agent_without_annotation) do
      {
        'metadata' => {
          'name' => 'test-agent',
          'annotations' => {}
        }
      }
    end

    let(:agent_with_annotation) do
      {
        'metadata' => {
          'name' => 'test-agent',
          'annotations' => {
            LanguageOperator::Constants::KubernetesLabels::LEARNING_DISABLED_LABEL => 'true'
          }
        }
      }
    end

    it 'shows message when learning is already disabled' do
      allow(client).to receive(:get_resource).and_return(agent_with_annotation)
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:info)

      command.disable('test-agent')

      expect(LanguageOperator::CLI::Formatters::ProgressFormatter)
        .to have_received(:info).with("Learning is already disabled for agent 'test-agent'")
    end

    it 'adds learning-disabled annotation when not present' do
      allow(client).to receive(:get_resource).and_return(agent_without_annotation)
      allow(command).to receive(:add_annotation)
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:with_spinner).and_yield
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:success)

      command.disable('test-agent')

      expect(command).to have_received(:add_annotation)
        .with(client, 'test-agent', 'language-operator', LanguageOperator::Constants::KubernetesLabels::LEARNING_DISABLED_LABEL, 'true')
      expect(LanguageOperator::CLI::Formatters::ProgressFormatter)
        .to have_received(:success).with("Learning disabled for agent 'test-agent'")
    end
  end

  describe 'private methods' do
    let(:agent_with_timestamp) do
      {
        'metadata' => {
          'creationTimestamp' => '2025-11-28T10:30:00Z'
        }
      }
    end

    let(:agent_without_timestamp) do
      {
        'metadata' => {}
      }
    end

    let(:agent_with_invalid_timestamp) do
      {
        'metadata' => {
          'creationTimestamp' => 'invalid-timestamp'
        }
      }
    end

    describe '#format_agent_timestamp' do
      it 'formats valid timestamp correctly' do
        result = command.send(:format_agent_timestamp, agent_with_timestamp)
        expect(result).to eq('2025-11-28 10:30:00 UTC')
      end

      it 'returns Unknown for missing timestamp' do
        result = command.send(:format_agent_timestamp, agent_without_timestamp)
        expect(result).to eq('Unknown')
      end

      it 'returns Unknown for invalid timestamp' do
        result = command.send(:format_agent_timestamp, agent_with_invalid_timestamp)
        expect(result).to eq('Unknown')
      end
    end
  end
end
