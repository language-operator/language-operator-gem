# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/base'

RSpec.describe LanguageOperator::Agent::Base do
  let(:config) do
    {
      'llm' => {
        'provider' => 'openai',
        'model' => 'gpt-4'
      },
      'mcp_servers' => []
    }
  end

  describe '#initialize' do
    context 'when AGENT_MODE is properly set' do
      before { ENV['AGENT_MODE'] = 'scheduled' }
      after { ENV.delete('AGENT_MODE') }

      it 'uses the specified mode' do
        agent = described_class.new(config)
        expect(agent.mode).to eq('scheduled')
      end
    end

    context 'when AGENT_MODE is unset' do
      before { ENV.delete('AGENT_MODE') }

      it 'defaults to autonomous mode' do
        agent = described_class.new(config)
        expect(agent.mode).to eq('autonomous')
      end
    end

    context 'when AGENT_MODE is empty string' do
      before { ENV['AGENT_MODE'] = '' }
      after { ENV.delete('AGENT_MODE') }

      it 'defaults to autonomous mode' do
        agent = described_class.new(config)
        expect(agent.mode).to eq('autonomous')
      end
    end

    context 'when AGENT_MODE is whitespace only' do
      before { ENV['AGENT_MODE'] = '   ' }
      after { ENV.delete('AGENT_MODE') }

      it 'defaults to autonomous mode' do
        agent = described_class.new(config)
        expect(agent.mode).to eq('autonomous')
      end
    end

    context 'when AGENT_MODE has valid value with whitespace' do
      before { ENV['AGENT_MODE'] = '  reactive  ' }
      after { ENV.delete('AGENT_MODE') }

      it 'preserves the value (normalization happens later)' do
        agent = described_class.new(config)
        expect(agent.mode).to eq('  reactive  ')
      end
    end
  end

  describe '#run' do
    let(:agent) { described_class.new(config) }

    before do
      # Mock the connection and run methods to avoid actual execution
      allow(agent).to receive(:connect!)
      allow(agent).to receive(:run_autonomous)
      allow(agent).to receive(:run_scheduled)
      allow(agent).to receive(:run_reactive)
      allow(agent).to receive(:flush_telemetry)
    end

    context 'with valid normalized modes' do
      it 'runs in autonomous mode' do
        agent.instance_variable_set(:@mode, 'autonomous')
        expect(agent).to receive(:run_autonomous)
        agent.run
      end

      it 'runs in scheduled mode' do
        agent.instance_variable_set(:@mode, 'scheduled')
        expect(agent).to receive(:run_scheduled)
        agent.run
      end

      it 'runs in autonomous mode for interactive alias' do
        agent.instance_variable_set(:@mode, 'interactive')
        expect(agent).to receive(:run_autonomous)
        agent.run
      end
    end

    context 'with invalid mode' do
      it 'raises helpful error for empty mode' do
        agent.instance_variable_set(:@mode, '')
        expect { agent.run }.to raise_error(
          ArgumentError,
          /AGENT_MODE environment variable is required but is unset or empty/
        )
      end

      it 'raises helpful error for invalid mode' do
        agent.instance_variable_set(:@mode, 'invalid')
        expect { agent.run }.to raise_error(
          ArgumentError,
          /Unknown execution mode: invalid\. Valid modes:/
        )
      end
    end
  end

  describe 'mode normalization integration' do
    before do
      # Mock methods to avoid actual execution
      allow_any_instance_of(described_class).to receive(:connect!)
      allow_any_instance_of(described_class).to receive(:run_autonomous)
      allow_any_instance_of(described_class).to receive(:flush_telemetry)
    end

    context 'when AGENT_MODE uses aliases' do
      after { ENV.delete('AGENT_MODE') }

      it 'normalizes interactive to autonomous' do
        ENV['AGENT_MODE'] = 'interactive'
        agent = described_class.new(config)

        expect(LanguageOperator::Constants.normalize_mode(agent.mode)).to eq('autonomous')
      end

      it 'normalizes webhook to reactive' do
        ENV['AGENT_MODE'] = 'webhook'
        agent = described_class.new(config)

        expect(LanguageOperator::Constants.normalize_mode(agent.mode)).to eq('reactive')
      end
    end

    context 'end-to-end behavior with problematic AGENT_MODE values' do
      after { ENV.delete('AGENT_MODE') }

      it 'handles unset AGENT_MODE gracefully' do
        ENV.delete('AGENT_MODE')
        agent = described_class.new(config)

        expect { agent.run }.not_to raise_error
        expect(agent.mode).to eq('autonomous')
      end

      it 'handles empty AGENT_MODE gracefully' do
        ENV['AGENT_MODE'] = ''
        agent = described_class.new(config)

        expect { agent.run }.not_to raise_error
        expect(agent.mode).to eq('autonomous')
      end

      it 'handles whitespace AGENT_MODE gracefully' do
        ENV['AGENT_MODE'] = '   '
        agent = described_class.new(config)

        expect { agent.run }.not_to raise_error
        expect(agent.mode).to eq('autonomous')
      end
    end
  end

  describe 'Kubernetes client initialization' do
    after do
      ENV.delete('KUBERNETES_SERVICE_HOST')
    end

    context 'when in Kubernetes environment' do
      before do
        ENV['KUBERNETES_SERVICE_HOST'] = 'kubernetes.default.svc'
        allow(LanguageOperator::Kubernetes::Client).to receive(:instance)
          .and_return(instance_double(LanguageOperator::Kubernetes::Client))
      end

      it 'initializes Kubernetes client' do
        expect(LanguageOperator::Kubernetes::Client).to receive(:instance)
        agent = described_class.new(config)
        expect(agent.kubernetes_client).not_to be_nil
      end
    end

    context 'when not in Kubernetes environment' do
      before do
        ENV.delete('KUBERNETES_SERVICE_HOST')
      end

      it 'does not initialize Kubernetes client' do
        expect(LanguageOperator::Kubernetes::Client).not_to receive(:instance)
        agent = described_class.new(config)
        expect(agent.kubernetes_client).to be_nil
      end
    end

    context 'when Kubernetes client initialization fails' do
      before do
        ENV['KUBERNETES_SERVICE_HOST'] = 'kubernetes.default.svc'
        allow(LanguageOperator::Kubernetes::Client).to receive(:instance)
          .and_raise(StandardError.new('K8s client error'))
      end

      it 'handles the error gracefully and logs warning' do
        logger = instance_double(Logger)
        allow(Logger).to receive(:new).and_return(logger)
        expect(logger).to receive(:warn).with('Failed to initialize Kubernetes client', error: 'K8s client error')
        
        agent = described_class.new(config)
        expect(agent.kubernetes_client).to be_nil
      end
    end
  end
end
