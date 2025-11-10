# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/base'

RSpec.describe LanguageOperator::Agent::Base do
  let(:config) do
    {
      'llm' => {
        'provider' => 'anthropic',
        'model' => 'claude-3-5-sonnet-20241022',
        'api_key' => 'test-key'
      },
      'mcp_servers' => []
    }
  end

  let(:agent) { described_class.new(config) }

  before do
    # Mock OpenTelemetry configuration to avoid actual setup in tests
    allow(LanguageOperator::Agent::Telemetry).to receive(:configure)
    # Mock logger
    logger_double = instance_double(LanguageOperator::Logger)
    allow(logger_double).to receive(:info)
    allow(logger_double).to receive(:debug)
    allow(logger_double).to receive(:warn)
    allow(logger_double).to receive(:error)
    allow_any_instance_of(described_class).to receive(:logger).and_return(logger_double)
  end

  after do
    ENV.delete('OTEL_EXPORTER_OTLP_ENDPOINT')
  end

  describe '#initialize' do
    it 'calls Telemetry.configure' do
      expect(LanguageOperator::Agent::Telemetry).to receive(:configure)
      described_class.new(config)
    end

    it 'logs OpenTelemetry enabled when endpoint is set' do
      ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = 'http://otel-collector:4318'
      logger_double = instance_double(LanguageOperator::Logger)
      expect(logger_double).to receive(:info).with('OpenTelemetry enabled')
      allow(logger_double).to receive(:debug)
      allow_any_instance_of(described_class).to receive(:logger).and_return(logger_double)
      described_class.new(config)
    end

    it 'logs OpenTelemetry disabled when endpoint is not set' do
      logger_double = instance_double(LanguageOperator::Logger)
      expect(logger_double).to receive(:info).with('OpenTelemetry disabled')
      allow(logger_double).to receive(:debug)
      allow_any_instance_of(described_class).to receive(:logger).and_return(logger_double)
      described_class.new(config)
    end

    it 'does not raise error without OpenTelemetry endpoint' do
      expect { described_class.new(config) }.not_to raise_error
    end
    it 'sets workspace path from environment or default' do
      expect(agent.workspace_path).to eq('/workspace')
    end

    it 'sets mode from environment or default' do
      expect(agent.mode).to eq('autonomous')
    end

    it 'initializes with custom workspace path' do
      ENV['WORKSPACE_PATH'] = '/custom/workspace'
      agent = described_class.new(config)
      expect(agent.workspace_path).to eq('/custom/workspace')
      ENV.delete('WORKSPACE_PATH')
    end

    it 'initializes with custom mode' do
      ENV['AGENT_MODE'] = 'scheduled'
      agent = described_class.new(config)
      expect(agent.mode).to eq('scheduled')
      ENV.delete('AGENT_MODE')
    end
  end

  describe '#workspace_available?' do
    it 'returns true for writable workspace' do
      Dir.mktmpdir do |dir|
        agent.instance_variable_set(:@workspace_path, dir)
        expect(agent.workspace_available?).to be true
      end
    end

    it 'returns false for non-existent workspace' do
      agent.instance_variable_set(:@workspace_path, '/nonexistent/path')
      expect(agent.workspace_available?).to be false
    end

    it 'returns false for read-only workspace' do
      skip 'Root user can write to read-only directories' if Process.uid == 0

      Dir.mktmpdir do |dir|
        agent.instance_variable_set(:@workspace_path, dir)
        File.chmod(0o444, dir)
        expect(agent.workspace_available?).to be false
        File.chmod(0o755, dir) # Cleanup
      end
    end
  end

  describe '#execute_goal' do
    it 'creates executor and executes goal' do
      # Mock the executor
      executor_double = instance_double(LanguageOperator::Agent::Executor)
      allow(LanguageOperator::Agent::Executor).to receive(:new).and_return(executor_double)
      allow(executor_double).to receive(:execute).and_return('Goal completed')

      result = agent.execute_goal('Test goal')
      expect(result).to eq('Goal completed')
    end
  end

  describe 'modes' do
    it 'validates autonomous mode' do
      ENV['AGENT_MODE'] = 'autonomous'
      agent = described_class.new(config)
      expect(agent.mode).to eq('autonomous')
      ENV.delete('AGENT_MODE')
    end

    it 'validates interactive mode' do
      ENV['AGENT_MODE'] = 'interactive'
      agent = described_class.new(config)
      expect(agent.mode).to eq('interactive')
      ENV.delete('AGENT_MODE')
    end

    it 'validates scheduled mode' do
      ENV['AGENT_MODE'] = 'scheduled'
      agent = described_class.new(config)
      expect(agent.mode).to eq('scheduled')
      ENV.delete('AGENT_MODE')
    end

    it 'validates event-driven mode' do
      ENV['AGENT_MODE'] = 'event-driven'
      agent = described_class.new(config)
      expect(agent.mode).to eq('event-driven')
      ENV.delete('AGENT_MODE')
    end
  end

  describe '#run' do
    xit 'raises error for unknown mode' do
      agent.instance_variable_set(:@mode, 'unknown')

      expect { agent.run }.to raise_error(/Unknown agent mode/)
    end
  end
end
