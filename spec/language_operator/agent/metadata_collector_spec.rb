# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Agent::MetadataCollector do
  let(:agent_config) do
    {
      'agent' => {
        'name' => 'test-agent',
        'instructions' => 'Test agent for unit tests',
        'persona' => 'test-persona'
      },
      'llm' => {
        'provider' => 'anthropic',
        'model' => 'claude-3-haiku'
      }
    }
  end

  let(:agent) do
    instance_double(
      LanguageOperator::Agent::Base,
      config: agent_config,
      mode: 'reactive',
      workspace_path: '/tmp/test-workspace',
      workspace_available?: true
    ).tap do |agent_mock|
      allow(agent_mock).to receive(:respond_to?).with(:servers_info).and_return(true)
      allow(agent_mock).to receive(:servers_info).and_return([
        { name: 'test-server', tool_count: 3 }
      ])
    end
  end

  let(:collector) { described_class.new(agent) }

  before do
    # Mock environment variables
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('AGENT_NAME', anything).and_return('test-agent')
    allow(ENV).to receive(:fetch).with('AGENT_CLUSTER', anything).and_return('test-cluster')
    allow(ENV).to receive(:fetch).with('AGENT_NAMESPACE', anything).and_return('test-namespace')
    allow(ENV).to receive(:fetch).with('KUBERNETES_SERVICE_HOST', anything).and_return('kubernetes.default.svc')
    allow(ENV).to receive(:fetch).with('OTEL_EXPORTER_OTLP_ENDPOINT', anything).and_return('http://jaeger:14268/api/traces')
  end

  describe '#collect' do
    it 'returns complete metadata structure' do
      metadata = collector.collect

      expect(metadata).to have_key(:identity)
      expect(metadata).to have_key(:runtime)
      expect(metadata).to have_key(:environment)
      expect(metadata).to have_key(:operational)
      expect(metadata).to have_key(:capabilities)
    end
  end

  describe '#collect_identity' do
    it 'returns agent identity information' do
      identity = collector.collect_identity

      expect(identity[:name]).to eq('test-agent')
      expect(identity[:description]).to eq('Test agent for unit tests')
      expect(identity[:persona]).to eq('test-persona')
      expect(identity[:mode]).to eq('reactive')
      expect(identity[:version]).to eq(LanguageOperator::VERSION)
    end
  end

  describe '#collect_runtime' do
    it 'returns runtime information' do
      runtime = collector.collect_runtime

      expect(runtime[:uptime]).to be_a(String)
      expect(runtime[:started_at]).to match(/\d{4}-\d{2}-\d{2}T/)
      expect(runtime[:process_id]).to eq(Process.pid)
      expect(runtime[:workspace_available]).to be true
      expect(runtime[:mcp_servers_connected]).to eq(1)
    end
  end

  describe '#collect_environment' do
    it 'returns environment information' do
      environment = collector.collect_environment

      expect(environment[:cluster]).to eq('test-cluster')
      expect(environment[:namespace]).to eq('test-namespace')
      expect(environment[:workspace_path]).to eq('/tmp/test-workspace')
      expect(environment[:kubernetes_enabled]).to be true
      expect(environment[:telemetry_enabled]).to be true
    end
  end

  describe '#collect_operational' do
    it 'returns operational state' do
      operational = collector.collect_operational

      expect(operational[:status]).to be_a(String)
      expect([true, false]).to include(operational[:ready])
      expect(operational[:mode]).to eq('reactive')
      expect(operational[:workspace][:available]).to be true
    end
  end

  describe '#collect_capabilities' do
    it 'returns capability information' do
      capabilities = collector.collect_capabilities

      expect(capabilities[:tools]).to be_an(Array)
      expect(capabilities[:tools].first[:server]).to eq('test-server')
      expect(capabilities[:tools].first[:tool_count]).to eq(3)
      expect(capabilities[:total_tools]).to eq(3)
      expect(capabilities[:llm_provider]).to eq('anthropic')
      expect(capabilities[:llm_model]).to eq('claude-3-haiku')
    end
  end

  describe '#summary_for_prompt' do
    it 'returns formatted summary for prompt injection' do
      summary = collector.summary_for_prompt

      expect(summary[:agent_name]).to eq('test-agent')
      expect(summary[:agent_description]).to eq('Test agent for unit tests')
      expect(summary[:agent_mode]).to eq('reactive')
      expect(summary[:cluster]).to eq('test-cluster')
      expect(summary[:namespace]).to eq('test-namespace')
      expect(summary[:status]).to be_a(String)
      expect(summary[:tool_count]).to eq(3)
      expect(summary[:llm_model]).to eq('claude-3-haiku')
    end
  end
end