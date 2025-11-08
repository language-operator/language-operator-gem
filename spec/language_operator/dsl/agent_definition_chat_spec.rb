# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/agent_definition'

RSpec.describe LanguageOperator::Dsl::AgentDefinition, 'chat endpoint support' do
  let(:agent_name) { 'test-chat-agent' }
  let(:agent_def) { described_class.new(agent_name) }

  describe '#as_chat_endpoint' do
    it 'creates ChatEndpointDefinition' do
      chat_endpoint = agent_def.as_chat_endpoint
      expect(chat_endpoint).to be_a(LanguageOperator::Dsl::ChatEndpointDefinition)
    end

    it 'returns same instance when called multiple times' do
      first = agent_def.as_chat_endpoint
      second = agent_def.as_chat_endpoint
      expect(first).to be(second)
    end

    it 'sets execution mode to reactive' do
      expect(agent_def.mode).to eq(:autonomous)
      agent_def.as_chat_endpoint
      expect(agent_def.mode).to eq(:reactive)
    end

    it 'does not override reactive mode if already set' do
      agent_def.mode(:reactive)
      agent_def.as_chat_endpoint
      expect(agent_def.mode).to eq(:reactive)
    end

    it 'accepts configuration block' do
      agent_def.as_chat_endpoint do
        system_prompt 'You are helpful'
        temperature 0.9
        max_tokens 3000
      end

      expect(agent_def.chat_endpoint.system_prompt).to eq('You are helpful')
      expect(agent_def.chat_endpoint.temperature).to eq(0.9)
      expect(agent_def.chat_endpoint.max_tokens).to eq(3000)
    end

    it 'allows chaining configuration' do
      agent_def.as_chat_endpoint do
        system_prompt 'GitHub expert'
        model 'github-expert-v1'
        temperature 0.7
        max_tokens 2000
        top_p 0.95
        frequency_penalty 0.1
        presence_penalty 0.1
        stop ["\n\n"]
      end

      chat_endpoint = agent_def.chat_endpoint
      expect(chat_endpoint.system_prompt).to eq('GitHub expert')
      expect(chat_endpoint.model_name).to eq('github-expert-v1')
      expect(chat_endpoint.temperature).to eq(0.7)
      expect(chat_endpoint.max_tokens).to eq(2000)
      expect(chat_endpoint.top_p).to eq(0.95)
      expect(chat_endpoint.frequency_penalty).to eq(0.1)
      expect(chat_endpoint.presence_penalty).to eq(0.1)
      expect(chat_endpoint.stop_sequences).to eq(["\n\n"])
    end
  end

  describe '#chat_endpoint' do
    it 'returns nil by default' do
      expect(agent_def.chat_endpoint).to be_nil
    end

    it 'returns ChatEndpointDefinition after calling as_chat_endpoint' do
      agent_def.as_chat_endpoint
      expect(agent_def.chat_endpoint).to be_a(LanguageOperator::Dsl::ChatEndpointDefinition)
    end
  end

  describe 'hybrid agent configuration' do
    it 'supports chat endpoint with webhooks' do
      agent_def.as_chat_endpoint do
        system_prompt 'I respond to both chat and webhooks'
        temperature 0.8
      end

      agent_def.webhook('/test') do
        method :post
        on_request { |_context| { status: 'ok' } }
      end

      expect(agent_def.chat_endpoint).not_to be_nil
      expect(agent_def.webhooks).not_to be_empty
      expect(agent_def.mode).to eq(:reactive)
    end

    it 'supports chat endpoint with MCP server' do
      agent_def.as_chat_endpoint do
        system_prompt 'I provide chat and MCP tools'
        model 'hybrid-agent-v1'
      end

      agent_def.as_mcp_server do
        tool 'test_tool' do
          description 'A test tool'
          execute { |_params| 'result' }
        end
      end

      expect(agent_def.chat_endpoint).not_to be_nil
      expect(agent_def.mcp_server).not_to be_nil
      expect(agent_def.mcp_server.tools?).to be true
      expect(agent_def.mode).to eq(:reactive)
    end

    it 'supports all three modes simultaneously' do
      agent_def.as_chat_endpoint do
        system_prompt 'Ultimate hybrid agent'
      end

      agent_def.webhook('/webhook') do
        method :post
        on_request { |_context| { status: 'received' } }
      end

      agent_def.as_mcp_server do
        tool 'hybrid_tool' do
          description 'Hybrid tool'
          execute { |_params| 'done' }
        end
      end

      expect(agent_def.chat_endpoint).not_to be_nil
      expect(agent_def.webhooks.size).to eq(1)
      expect(agent_def.mcp_server).not_to be_nil
      expect(agent_def.mode).to eq(:reactive)
    end
  end

  describe 'full agent DSL example' do
    it 'creates complete chat endpoint agent' do
      agent_def.description 'GitHub expert agent'
      agent_def.mode :reactive

      agent_def.as_chat_endpoint do
        system_prompt <<~PROMPT
          You are a GitHub expert assistant with deep knowledge of:
          - GitHub API and workflows
          - Pull requests, issues, and code review
          - GitHub Actions and CI/CD
          - Repository management and best practices
        PROMPT

        model 'github-expert-v1'
        temperature 0.7
        max_tokens 2000
      end

      expect(agent_def.name).to eq('test-chat-agent')
      expect(agent_def.description).to eq('GitHub expert agent')
      expect(agent_def.mode).to eq(:reactive)
      expect(agent_def.chat_endpoint.model_name).to eq('github-expert-v1')
      expect(agent_def.chat_endpoint.system_prompt).to include('GitHub expert assistant')
    end
  end
end
