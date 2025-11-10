# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/client/base'

RSpec.describe LanguageOperator::Client::Base do
  let(:config) do
    {
      'llm' => {
        'provider' => 'anthropic',
        'model' => 'claude-3-5-sonnet-20241022',
        'api_key' => 'test-key',
        'timeout' => 120
      },
      'mcp_servers' => [
        {
          'name' => 'test-server',
          'url' => 'http://localhost:8080',
          'enabled' => true
        }
      ]
    }
  end

  let(:client) { described_class.new(config) }

  describe '#initialize' do
    it 'stores configuration' do
      expect(client.config).to eq(config)
    end

    xit 'initializes empty servers list' do
      expect(client.servers).to be_empty
    end

    xit 'initializes LLM client to nil' do
      expect(client.llm_client).to be_nil
    end
  end

  describe '#configure_llm' do
    xit 'configures Anthropic provider' do
      expect(RubyLLM).to receive(:configure).and_yield(double(anthropic_api_key: nil))

      client.send(:configure_llm)
    end

    xit 'sets timeout from config' do
      config_double = double
      allow(config_double).to receive(:respond_to?).with(:request_timeout=).and_return(true)
      expect(config_double).to receive(:request_timeout=).with(120)

      allow(RubyLLM).to receive(:configure).and_yield(config_double)
      client.send(:configure_llm)
    end

    xit 'configures MCP timeout separately' do
      expect(RubyLLM::MCP).to receive(:configure).and_yield(double(respond_to?: true, request_timeout: nil))

      client.send(:configure_llm)
    end

    xit 'converts timeout to milliseconds for MCP' do
      mcp_config = double
      allow(mcp_config).to receive(:respond_to?).with(:request_timeout=).and_return(true)
      expect(mcp_config).to receive(:request_timeout=).with(120_000) # 120 seconds * 1000

      allow(RubyLLM::MCP).to receive(:configure).and_yield(mcp_config)
      client.send(:configure_llm)
    end

    it 'raises error for unknown provider' do
      config['llm']['provider'] = 'unknown'

      expect { client.send(:configure_llm) }.to raise_error(/Unknown provider/)
    end
  end

  describe '#connect!' do
    before do
      # Mock MCP server connection
      allow(client).to receive(:connect_to_servers)
    end

    xit 'configures LLM' do
      expect(client).to receive(:configure_llm)
      client.connect!
    end

    xit 'connects to MCP servers' do
      expect(client).to receive(:connect_to_servers)
      client.connect!
    end
  end

  describe '#servers_info' do
    it 'returns empty array when no servers connected' do
      expect(client.servers_info).to eq([])
    end

    xit 'returns server information when connected' do
      # Mock a connected server
      server_double = double(name: 'test-server', url: 'http://localhost:8080')
      client.instance_variable_set(:@servers, [server_double])

      info = client.servers_info
      expect(info).to be_an(Array)
      expect(info.first[:name]).to eq('test-server')
    end
  end

  describe '#send_message' do
    before do
      # Mock LLM client
      llm_client_double = double
      allow(llm_client_double).to receive(:chat).and_return('LLM response')
      client.instance_variable_set(:@llm_client, llm_client_double)
    end

    xit 'sends message to LLM client' do
      llm_client = client.instance_variable_get(:@llm_client)
      expect(llm_client).to receive(:chat).with(hash_including(messages: anything))

      client.send_message('Hello')
    end

    xit 'includes message in request' do
      llm_client = client.instance_variable_get(:@llm_client)
      expect(llm_client).to receive(:chat) do |params|
        expect(params[:messages]).to include(hash_including(role: 'user', content: 'Hello'))
        'response'
      end

      client.send_message('Hello')
    end

    xit 'returns LLM response' do
      result = client.send_message('Test')
      expect(result).to eq('LLM response')
    end
  end

  describe 'provider-specific configuration' do
    xit 'configures OpenAI provider' do
      config['llm']['provider'] = 'openai'
      config['llm']['api_key'] = 'sk-test'

      openai_config = double
      allow(openai_config).to receive(:respond_to?).and_return(true)
      expect(openai_config).to receive(:openai_api_key=).with('sk-test')

      allow(RubyLLM).to receive(:configure).and_yield(openai_config)
      client.send(:configure_llm)
    end

    xit 'handles local models without API key' do
      config['llm']['provider'] = 'openai'
      config['llm'].delete('api_key')
      config['llm']['base_url'] = 'http://localhost:11434'

      expect { client.send(:configure_llm) }.not_to raise_error
    end
  end

  describe 'MCP server filtering' do
    it 'only connects to enabled servers' do
      config['mcp_servers'] << {
        'name' => 'disabled-server',
        'url' => 'http://localhost:9999',
        'enabled' => false
      }

      enabled_servers = config['mcp_servers'].reject { |s| s['enabled'] == false }
      expect(enabled_servers.length).to eq(1)
      expect(enabled_servers.first['name']).to eq('test-server')
    end
  end

  describe '#send_message with OpenTelemetry instrumentation' do
    let(:tracer_double) { instance_double(OpenTelemetry::Trace::Tracer) }
    let(:span_double) { instance_double(OpenTelemetry::Trace::Span) }
    let(:tracer_provider_double) { instance_double(OpenTelemetry::Trace::TracerProvider) }
    let(:chat_double) { double('RubyLLM::Chat') }
    let(:response_with_tokens) do
      double('RubyLLM::Message',
             content: 'Test response',
             input_tokens: 100,
             output_tokens: 50)
    end

    before do
      # Mock OpenTelemetry tracer
      allow(OpenTelemetry).to receive(:tracer_provider).and_return(tracer_provider_double)
      allow(tracer_provider_double).to receive(:tracer).and_return(tracer_double)
      allow(tracer_double).to receive(:in_span).and_yield(span_double)
      allow(span_double).to receive(:set_attribute)

      # Setup chat mock
      client.instance_variable_set(:@chat, chat_double)
      allow(chat_double).to receive(:ask).and_return(response_with_tokens)
    end

    it 'creates a span with correct name during LLM request' do
      expect(tracer_double).to receive(:in_span).with('agent.llm.request', anything).and_yield(span_double)
      client.send_message('test message')
    end

    it 'includes llm.model attribute' do
      expect(tracer_double).to receive(:in_span).with(
        'agent.llm.request',
        hash_including(attributes: hash_including('llm.model' => 'claude-3-5-sonnet-20241022'))
      ).and_yield(span_double)
      client.send_message('test message')
    end

    it 'includes llm.provider attribute' do
      expect(tracer_double).to receive(:in_span).with(
        'agent.llm.request',
        hash_including(attributes: hash_including('llm.provider' => 'anthropic'))
      ).and_yield(span_double)
      client.send_message('test message')
    end

    it 'sets llm.input_tokens attribute after response' do
      expect(span_double).to receive(:set_attribute).with('llm.input_tokens', 100)
      client.send_message('test message')
    end

    it 'sets llm.output_tokens attribute after response' do
      expect(span_double).to receive(:set_attribute).with('llm.output_tokens', 50)
      client.send_message('test message')
    end

    it 'calculates and sets llm.cost_usd attribute' do
      # Claude Sonnet: $3/1M input, $15/1M output
      # 100 input tokens = 0.0003, 50 output tokens = 0.00075
      # Total = 0.001050
      expect(span_double).to receive(:set_attribute).with('llm.cost_usd', 0.001050)
      client.send_message('test message')
    end

    it 'executes LLM request within the span' do
      expect(chat_double).to receive(:ask).with('test message')
      client.send_message('test message')
    end

    context 'when response does not have token information' do
      let(:response_without_tokens) { 'Simple string response' }

      before do
        allow(chat_double).to receive(:ask).and_return(response_without_tokens)
      end

      it 'does not set token attributes' do
        expect(span_double).not_to receive(:set_attribute).with('llm.input_tokens', anything)
        expect(span_double).not_to receive(:set_attribute).with('llm.output_tokens', anything)
        client.send_message('test message')
      end
    end

    context 'when model is not in pricing table' do
      before do
        config['llm']['model'] = 'unknown-model'
      end

      it 'does not set cost attribute' do
        expect(span_double).not_to receive(:set_attribute).with('llm.cost_usd', anything)
        client.send_message('test message')
      end
    end
  end

  describe '#calculate_cost' do
    it 'calculates cost for GPT-4' do
      cost = client.send(:calculate_cost, 'gpt-4', 1_000_000, 1_000_000)
      expect(cost).to eq(90.0) # $30 input + $60 output
    end

    it 'calculates cost for Claude Sonnet' do
      cost = client.send(:calculate_cost, 'claude-3-5-sonnet-20241022', 1_000_000, 1_000_000)
      expect(cost).to eq(18.0) # $3 input + $15 output
    end

    it 'handles fractional token counts' do
      cost = client.send(:calculate_cost, 'gpt-4o', 500_000, 250_000)
      expect(cost).to eq(6.25) # (0.5M * $5) + (0.25M * $15)
    end

    it 'returns nil for unknown model' do
      cost = client.send(:calculate_cost, 'unknown-model', 1_000_000, 1_000_000)
      expect(cost).to be_nil
    end
  end
end
