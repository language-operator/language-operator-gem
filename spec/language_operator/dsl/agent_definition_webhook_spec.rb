# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Dsl::AgentDefinition, 'webhook support' do
  let(:agent_def) { described_class.new('test-agent') }

  describe '#webhook' do
    it 'creates a webhook definition' do
      webhook = agent_def.webhook('/test/path') do
        method :post
      end

      expect(webhook).to be_a(LanguageOperator::Dsl::WebhookDefinition)
      expect(webhook.path).to eq('/test/path')
    end

    it 'adds webhook to webhooks array' do
      agent_def.webhook('/path1') { method :post }
      agent_def.webhook('/path2') { method :get }

      expect(agent_def.webhooks.size).to eq(2)
      expect(agent_def.webhooks[0].path).to eq('/path1')
      expect(agent_def.webhooks[1].path).to eq('/path2')
    end

    it 'sets execution mode to reactive' do
      expect(agent_def.execution_mode).to eq(:autonomous)

      agent_def.webhook('/test') { method :post }

      expect(agent_def.execution_mode).to eq(:reactive)
    end

    it 'does not override explicit mode' do
      agent_def.mode(:scheduled)
      agent_def.webhook('/test') { method :post }

      expect(agent_def.execution_mode).to eq(:scheduled)
    end

    it 'configures webhook with DSL block' do
      handler_result = nil

      agent_def.webhook('/github/pr') do
        method :post
        on_request do |context|
          handler_result = context[:params]
          { status: 'processed' }
        end
      end

      webhook = agent_def.webhooks.first
      expect(webhook.http_method).to eq(:post)
      expect(webhook.handler).to be_a(Proc)

      # Test handler execution
      webhook.handler.call({ params: { foo: 'bar' } })
      expect(handler_result).to eq({ foo: 'bar' })
    end
  end

  describe 'reactive mode agent definition' do
    it 'can define a complete webhook agent' do
      agent_def = described_class.new('github-webhook-handler')

      agent_def.instance_eval do
        description 'Handle GitHub webhooks'
        mode :reactive

        webhook '/github/pr-opened' do
          method :post
          on_request do |context|
            { pr_url: context[:params]['pull_request']['url'] }
          end
        end

        webhook '/github/issue-created' do
          method :post
          on_request do |context|
            { issue_number: context[:params]['issue']['number'] }
          end
        end
      end

      expect(agent_def.name).to eq('github-webhook-handler')
      expect(agent_def.execution_mode).to eq(:reactive)
      expect(agent_def.webhooks.size).to eq(2)
      expect(agent_def.webhooks[0].path).to eq('/github/pr-opened')
      expect(agent_def.webhooks[1].path).to eq('/github/issue-created')
    end
  end

  describe '#build_agent_config' do
    it 'builds agent configuration hash' do
      agent_def.description('Test agent description')
      agent_def.persona('You are a helpful assistant')

      config = agent_def.send(:build_agent_config)

      expect(config).to include('agent', 'llm', 'mcp')
      expect(config['agent']['name']).to eq('test-agent')
      expect(config['agent']['instructions']).to eq('Test agent description')
      expect(config['agent']['persona']).to eq('You are a helpful assistant')
    end

    it 'uses environment variables for LLM config' do
      ENV['LLM_PROVIDER'] = 'openai'
      ENV['LLM_MODEL'] = 'gpt-4'

      config = agent_def.send(:build_agent_config)

      expect(config['llm']['provider']).to eq('openai')
      expect(config['llm']['model']).to eq('gpt-4')

      ENV.delete('LLM_PROVIDER')
      ENV.delete('LLM_MODEL')
    end

    it 'has default LLM configuration' do
      config = agent_def.send(:build_agent_config)

      expect(config['llm']['provider']).to eq('anthropic')
      expect(config['llm']['model']).to eq('claude-3-5-sonnet-20241022')
    end
  end
end
