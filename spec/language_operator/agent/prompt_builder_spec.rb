# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Agent::PromptBuilder do
  let(:agent_config) do
    {
      'agent' => {
        'name' => 'test-agent',
        'instructions' => 'Test agent for building prompts',
        'persona' => 'helpful-assistant'
      }
    }
  end

  let(:agent) do
    instance_double(
      LanguageOperator::Agent::Base,
      config: agent_config,
      mode: 'reactive',
      workspace_path: '/tmp/test',
      workspace_available?: true
    ).tap do |mock|
      allow(mock).to receive(:respond_to?).with(:servers_info).and_return(true)
      allow(mock).to receive(:servers_info).and_return([])
    end
  end

  let(:chat_config) do
    nil  # No chat config needed - identity awareness is always enabled
  end

  let(:builder) { described_class.new(agent, chat_config) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('AGENT_NAME', anything).and_return('test-agent')
    allow(ENV).to receive(:fetch).with('AGENT_CLUSTER', anything).and_return('test-cluster')
  end

  describe '#build_system_prompt' do
    it 'always builds identity-aware dynamic system prompt' do
      prompt = builder.build_system_prompt

      expect(prompt).to include('test-agent')
      expect(prompt).to include('test-cluster') 
      expect(prompt).to include('reactive mode')
      expect(prompt).to include('Test agent for building prompts')
    end

    context 'with different template levels' do
      it 'builds minimal template' do
        builder = described_class.new(agent, chat_config, template: :minimal)
        prompt = builder.build_system_prompt

        expect(prompt).to include('test-agent')
        expect(prompt).to include('test-cluster')
        expect(prompt).not_to include('capabilities')
      end

      it 'builds detailed template' do
        builder = described_class.new(agent, chat_config, template: :detailed)
        prompt = builder.build_system_prompt

        expect(prompt).to include('test-agent')
        expect(prompt).to include('test-cluster')
        expect(prompt).to include('should:')
      end
    end
  end

  describe '#build_conversation_context' do
    it 'always builds conversation context' do
      context = builder.build_conversation_context

      expect(context).to include('test-agent')
      expect(context).to include('reactive')
    end
  end

  describe 'error handling' do
    context 'when metadata collection fails' do
      before do
        allow_any_instance_of(LanguageOperator::Agent::MetadataCollector)
          .to receive(:summary_for_prompt).and_raise(StandardError.new('Test error'))
      end

      it 'falls back to basic prompt' do
        prompt = builder.build_system_prompt
        expect(prompt).to include('AI assistant')  # fallback prompt
      end
    end
  end
end