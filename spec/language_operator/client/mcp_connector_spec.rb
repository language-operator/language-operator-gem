# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/client/base'

RSpec.describe LanguageOperator::Client::MCPConnector do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include LanguageOperator::Client::MCPConnector
      include LanguageOperator::Loggable
      include LanguageOperator::Retryable

      attr_reader :config, :clients, :chat

      def initialize(config)
        @config = config
        @clients = []
        @chat = nil
      end

      # Mock the tools method that would normally be provided by Base
      def tools
        []
      end

      # Mock the configure_llm method
      def configure_llm
        # No-op for testing
      end
    end
  end

  let(:instance) { test_class.new(config) }
  let(:chat_double) { double('chat', with_tools: nil, on_tool_call: nil, on_tool_result: nil) }

  before do
    # Stub RubyLLM to avoid actual connections
    allow(RubyLLM).to receive(:chat).and_return(chat_double)
  end

  describe '#connect_mcp_servers' do
    context 'when mcp_servers key is missing from config' do
      let(:config) do
        {
          'llm' => {
            'provider' => 'openai',
            'model' => 'gpt-4'
          }
          # NOTE: no 'mcp_servers' key
        }
      end

      it 'does not raise an error' do
        expect { instance.send(:connect_mcp_servers) }.not_to raise_error
      end

      it 'logs that no MCP servers are configured' do
        expect(instance.logger).to receive(:info).with('No MCP servers configured, agent will run without tools')
        expect(instance.logger).to receive(:info).with('Chat session initialized', with_tools: false, total_tools: 0)
        instance.send(:connect_mcp_servers)
      end

      it 'initializes chat without tools' do
        expect(chat_double).not_to receive(:with_tools)

        instance.send(:connect_mcp_servers)
        expect(instance.chat).to eq(chat_double)
      end
    end

    context 'when mcp_servers is an empty array' do
      let(:config) do
        {
          'llm' => {
            'provider' => 'openai',
            'model' => 'gpt-4'
          },
          'mcp_servers' => []
        }
      end

      it 'does not raise an error' do
        expect { instance.send(:connect_mcp_servers) }.not_to raise_error
      end

      it 'logs that no MCP servers are configured' do
        expect(instance.logger).to receive(:info).with('No MCP servers configured, agent will run without tools')
        expect(instance.logger).to receive(:info).with('Chat session initialized', with_tools: false, total_tools: 0)
        instance.send(:connect_mcp_servers)
      end
    end

    context 'when mcp_servers contains disabled servers' do
      let(:config) do
        {
          'llm' => {
            'provider' => 'openai',
            'model' => 'gpt-4'
          },
          'mcp_servers' => [
            {
              'name' => 'disabled-server',
              'url' => 'http://example.com',
              'transport' => 'streamable',
              'enabled' => false
            }
          ]
        }
      end

      it 'does not attempt to connect to disabled servers' do
        expect(RubyLLM::MCP).not_to receive(:client)
        expect(instance.logger).to receive(:info).with('No MCP servers configured, agent will run without tools')
        expect(instance.logger).to receive(:info).with('Chat session initialized', with_tools: false, total_tools: 0)
        instance.send(:connect_mcp_servers)
      end
    end

    context 'when mcp_servers contains enabled servers' do
      let(:config) do
        {
          'llm' => {
            'provider' => 'openai',
            'model' => 'gpt-4'
          },
          'mcp_servers' => [
            {
              'name' => 'test-server',
              'url' => 'http://example.com',
              'transport' => 'streamable',
              'enabled' => true
            }
          ]
        }
      end

      let(:mcp_client) { double('mcp_client', tools: []) }

      before do
        allow(RubyLLM::MCP).to receive(:client).and_return(mcp_client)
      end

      it 'attempts to connect to enabled servers' do
        expect(RubyLLM::MCP).to receive(:client).with(
          name: 'test-server',
          transport_type: :streamable,
          config: { url: 'http://example.com' }
        ).and_return(mcp_client)

        expect(instance.logger).to receive(:info).with('Connecting to MCP servers', count: 1)
        # Debug and other logs may appear, we just need the key ones
        allow(instance.logger).to receive(:debug)
        allow(instance.logger).to receive(:info)
        expect(instance.logger).to receive(:info).with('MCP connection summary', connected_servers: 1)
        expect(instance.logger).to receive(:info).with('Chat session initialized', with_tools: false, total_tools: 0)

        instance.send(:connect_mcp_servers)
      end
    end
  end
end
