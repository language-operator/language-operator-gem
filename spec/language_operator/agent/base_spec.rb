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
end
