# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/agent_definition'

RSpec.describe LanguageOperator::Dsl::AgentDefinition, 'MCP server support' do
  let(:agent_def) { described_class.new('test-agent') }

  describe '#as_mcp_server' do
    it 'creates an MCP server definition' do
      mcp_server = agent_def.as_mcp_server do
        tool 'test_tool' do
          description 'Test tool'
        end
      end

      expect(mcp_server).to be_a(LanguageOperator::Dsl::McpServerDefinition)
      expect(agent_def.mcp_server).to eq(mcp_server)
    end

    it 'sets execution mode to reactive' do
      expect(agent_def.execution_mode).to eq(:autonomous)

      agent_def.as_mcp_server do
        tool('test') { description 'Test' }
      end

      expect(agent_def.execution_mode).to eq(:reactive)
    end

    it 'does not override explicit mode' do
      agent_def.mode(:scheduled)
      agent_def.as_mcp_server do
        tool('test') { description 'Test' }
      end

      expect(agent_def.execution_mode).to eq(:scheduled)
    end

    it 'configures tools with DSL block' do
      agent_def.as_mcp_server do
        tool 'greet' do
          description 'Greet a user'

          parameter :name do
            type :string
            required true
          end

          execute do |params|
            "Hello, #{params['name']}!"
          end
        end
      end

      mcp_server = agent_def.mcp_server
      expect(mcp_server.tools.keys).to include('greet')

      tool = mcp_server.tools['greet']
      expect(tool.description).to eq('Greet a user')
      expect(tool.call('name' => 'Bob')).to eq('Hello, Bob!')
    end
  end

  describe 'complete MCP agent definition' do
    it 'can define an agent with both webhooks and MCP tools' do
      agent_def = described_class.new('hybrid-agent')

      agent_def.instance_eval do
        description 'Agent with webhooks and MCP tools'
        mode :reactive

        webhook '/webhook' do
          method :post
          on_request do |_context|
            { status: 'ok' }
          end
        end

        as_mcp_server do
          tool 'add' do
            description 'Add two numbers'

            parameter :a do
              type :number
              required true
            end

            parameter :b do
              type :number
              required true
            end

            execute do |params|
              params['a'] + params['b']
            end
          end
        end
      end

      expect(agent_def.name).to eq('hybrid-agent')
      expect(agent_def.execution_mode).to eq(:reactive)
      expect(agent_def.webhooks.size).to eq(1)
      expect(agent_def.mcp_server.tools.size).to eq(1)

      # Test webhook
      webhook = agent_def.webhooks.first
      expect(webhook.path).to eq('/webhook')

      # Test MCP tool
      add_tool = agent_def.mcp_server.tools['add']
      expect(add_tool.call('a' => 5, 'b' => 3)).to eq(8)
    end
  end
end
