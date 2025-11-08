# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/chat_endpoint_definition'

RSpec.describe LanguageOperator::Dsl::ChatEndpointDefinition do
  let(:agent_name) { 'test-agent' }
  let(:chat_endpoint) { described_class.new(agent_name) }

  describe '#initialize' do
    it 'sets agent name' do
      expect(chat_endpoint.instance_variable_get(:@agent_name)).to eq(agent_name)
    end

    it 'sets default temperature' do
      expect(chat_endpoint.temperature).to eq(0.7)
    end

    it 'sets default max_tokens' do
      expect(chat_endpoint.max_tokens).to eq(2000)
    end

    it 'sets default model_name to agent name' do
      expect(chat_endpoint.model_name).to eq(agent_name)
    end

    it 'sets default top_p' do
      expect(chat_endpoint.top_p).to eq(1.0)
    end

    it 'sets default frequency_penalty' do
      expect(chat_endpoint.frequency_penalty).to eq(0.0)
    end

    it 'sets default presence_penalty' do
      expect(chat_endpoint.presence_penalty).to eq(0.0)
    end

    it 'sets default stop_sequences to nil' do
      expect(chat_endpoint.stop_sequences).to be_nil
    end
  end

  describe '#system_prompt' do
    it 'returns nil by default' do
      expect(chat_endpoint.system_prompt).to be_nil
    end

    it 'sets system prompt' do
      prompt = 'You are a helpful assistant'
      chat_endpoint.system_prompt(prompt)
      expect(chat_endpoint.system_prompt).to eq(prompt)
    end

    it 'supports multi-line prompts' do
      prompt = <<~PROMPT
        You are a GitHub expert.
        Help users with GitHub workflows.
      PROMPT
      chat_endpoint.system_prompt(prompt)
      expect(chat_endpoint.system_prompt).to eq(prompt)
    end
  end

  describe '#temperature' do
    it 'returns current temperature' do
      expect(chat_endpoint.temperature).to eq(0.7)
    end

    it 'sets temperature' do
      chat_endpoint.temperature(0.9)
      expect(chat_endpoint.temperature).to eq(0.9)
    end

    it 'accepts zero temperature' do
      chat_endpoint.temperature(0.0)
      expect(chat_endpoint.temperature).to eq(0.0)
    end

    it 'accepts high temperature' do
      chat_endpoint.temperature(2.0)
      expect(chat_endpoint.temperature).to eq(2.0)
    end
  end

  describe '#max_tokens' do
    it 'returns current max_tokens' do
      expect(chat_endpoint.max_tokens).to eq(2000)
    end

    it 'sets max_tokens' do
      chat_endpoint.max_tokens(4000)
      expect(chat_endpoint.max_tokens).to eq(4000)
    end
  end

  describe '#model' do
    it 'returns current model_name' do
      expect(chat_endpoint.model).to eq(agent_name)
    end

    it 'sets model_name' do
      chat_endpoint.model('custom-model-v1')
      expect(chat_endpoint.model).to eq('custom-model-v1')
    end
  end

  describe '#top_p' do
    it 'returns current top_p' do
      expect(chat_endpoint.top_p).to eq(1.0)
    end

    it 'sets top_p' do
      chat_endpoint.top_p(0.8)
      expect(chat_endpoint.top_p).to eq(0.8)
    end
  end

  describe '#frequency_penalty' do
    it 'returns current frequency_penalty' do
      expect(chat_endpoint.frequency_penalty).to eq(0.0)
    end

    it 'sets frequency_penalty' do
      chat_endpoint.frequency_penalty(0.5)
      expect(chat_endpoint.frequency_penalty).to eq(0.5)
    end

    it 'accepts negative values' do
      chat_endpoint.frequency_penalty(-0.5)
      expect(chat_endpoint.frequency_penalty).to eq(-0.5)
    end
  end

  describe '#presence_penalty' do
    it 'returns current presence_penalty' do
      expect(chat_endpoint.presence_penalty).to eq(0.0)
    end

    it 'sets presence_penalty' do
      chat_endpoint.presence_penalty(0.5)
      expect(chat_endpoint.presence_penalty).to eq(0.5)
    end

    it 'accepts negative values' do
      chat_endpoint.presence_penalty(-0.5)
      expect(chat_endpoint.presence_penalty).to eq(-0.5)
    end
  end

  describe '#stop' do
    it 'returns nil by default' do
      expect(chat_endpoint.stop).to be_nil
    end

    it 'sets stop sequences' do
      sequences = %W[\n END]
      chat_endpoint.stop(sequences)
      expect(chat_endpoint.stop).to eq(sequences)
    end

    it 'accepts empty array' do
      chat_endpoint.stop([])
      expect(chat_endpoint.stop).to eq([])
    end
  end

  describe 'DSL block configuration' do
    it 'supports instance_eval for DSL configuration' do
      chat_endpoint.instance_eval do
        system_prompt 'You are helpful'
        temperature 0.8
        max_tokens 3000
        model 'custom-model'
        top_p 0.9
        frequency_penalty 0.2
        presence_penalty 0.3
        stop ["\n"]
      end

      expect(chat_endpoint.system_prompt).to eq('You are helpful')
      expect(chat_endpoint.temperature).to eq(0.8)
      expect(chat_endpoint.max_tokens).to eq(3000)
      expect(chat_endpoint.model_name).to eq('custom-model')
      expect(chat_endpoint.top_p).to eq(0.9)
      expect(chat_endpoint.frequency_penalty).to eq(0.2)
      expect(chat_endpoint.presence_penalty).to eq(0.3)
      expect(chat_endpoint.stop_sequences).to eq(["\n"])
    end
  end
end
