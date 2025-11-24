# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/executor'

RSpec.describe LanguageOperator::Agent::Executor do
  let(:agent) { instance_double('LanguageOperator::Agent::Base', workspace_path: '/tmp/test') }
  let(:executor) { described_class.new(agent) }

  describe '#parse_float_env' do
    before { allow(executor).to receive(:logger).and_return(double('Logger', warn: nil)) }

    context 'with valid float values' do
      it 'parses valid float strings' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('3.14')
        result = executor.send(:parse_float_env, 'TEST_KEY')
        expect(result).to eq(3.14)
      end

      it 'parses integer strings as floats' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('42')
        result = executor.send(:parse_float_env, 'TEST_KEY')
        expect(result).to eq(42.0)
      end

      it 'handles strings with whitespace' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('  5.25  ')
        result = executor.send(:parse_float_env, 'TEST_KEY')
        expect(result).to eq(5.25)
      end

      it 'handles zero values' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('0.0')
        result = executor.send(:parse_float_env, 'TEST_KEY')
        expect(result).to eq(0.0)
      end

      it 'handles negative values' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('-10.5')
        result = executor.send(:parse_float_env, 'TEST_KEY')
        expect(result).to eq(-10.5)
      end
    end

    context 'with invalid or missing values' do
      it 'returns nil for missing environment variable' do
        allow(ENV).to receive(:fetch).with('MISSING_KEY', nil).and_return(nil)
        result = executor.send(:parse_float_env, 'MISSING_KEY')
        expect(result).to be_nil
      end

      it 'returns nil for empty string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('')
        result = executor.send(:parse_float_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil for whitespace-only string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('   ')
        result = executor.send(:parse_float_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil and warns for invalid string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('invalid')
        logger = double('Logger')
        allow(executor).to receive(:logger).and_return(logger)

        expect(logger).to receive(:warn).with('Invalid float value for TEST_KEY: invalid. Ignoring.')
        result = executor.send(:parse_float_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil and warns for mixed string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('123abc')
        logger = double('Logger')
        allow(executor).to receive(:logger).and_return(logger)

        expect(logger).to receive(:warn).with('Invalid float value for TEST_KEY: 123abc. Ignoring.')
        result = executor.send(:parse_float_env, 'TEST_KEY')
        expect(result).to be_nil
      end
    end
  end

  describe '#parse_int_env' do
    before { allow(executor).to receive(:logger).and_return(double('Logger', warn: nil)) }

    context 'with valid integer values' do
      it 'parses valid integer strings' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('42')
        result = executor.send(:parse_int_env, 'TEST_KEY')
        expect(result).to eq(42)
      end

      it 'handles strings with whitespace' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('  123  ')
        result = executor.send(:parse_int_env, 'TEST_KEY')
        expect(result).to eq(123)
      end

      it 'handles zero values' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('0')
        result = executor.send(:parse_int_env, 'TEST_KEY')
        expect(result).to eq(0)
      end

      it 'handles negative values' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('-50')
        result = executor.send(:parse_int_env, 'TEST_KEY')
        expect(result).to eq(-50)
      end
    end

    context 'with invalid or missing values' do
      it 'returns nil for missing environment variable' do
        allow(ENV).to receive(:fetch).with('MISSING_KEY', nil).and_return(nil)
        result = executor.send(:parse_int_env, 'MISSING_KEY')
        expect(result).to be_nil
      end

      it 'returns nil for empty string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('')
        result = executor.send(:parse_int_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil for whitespace-only string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('   ')
        result = executor.send(:parse_int_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil and warns for invalid string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('invalid')
        logger = double('Logger')
        allow(executor).to receive(:logger).and_return(logger)

        expect(logger).to receive(:warn).with('Invalid integer value for TEST_KEY: invalid. Ignoring.')
        result = executor.send(:parse_int_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil and warns for float string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('3.14')
        logger = double('Logger')
        allow(executor).to receive(:logger).and_return(logger)

        expect(logger).to receive(:warn).with('Invalid integer value for TEST_KEY: 3.14. Ignoring.')
        result = executor.send(:parse_int_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil and warns for mixed string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('123abc')
        logger = double('Logger')
        allow(executor).to receive(:logger).and_return(logger)

        expect(logger).to receive(:warn).with('Invalid integer value for TEST_KEY: 123abc. Ignoring.')
        result = executor.send(:parse_int_env, 'TEST_KEY')
        expect(result).to be_nil
      end
    end
  end

  describe '#parse_array_env' do
    # Use allocate to avoid constructor ENV calls interfering with tests
    let(:simple_executor) { described_class.allocate }

    context 'with valid array values' do
      it 'parses comma-separated values' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('one,two,three')
        result = simple_executor.send(:parse_array_env, 'TEST_KEY')
        expect(result).to eq(%w[one two three])
      end

      it 'trims whitespace around values' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('  one ,  two  , three  ')
        result = simple_executor.send(:parse_array_env, 'TEST_KEY')
        expect(result).to eq(%w[one two three])
      end

      it 'handles single values' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('single')
        result = simple_executor.send(:parse_array_env, 'TEST_KEY')
        expect(result).to eq(['single'])
      end

      it 'filters out empty strings' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('one,,two, ,three')
        result = simple_executor.send(:parse_array_env, 'TEST_KEY')
        expect(result).to eq(%w[one two three])
      end

      it 'handles mixed content with empty elements' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('  one ,  , two ,   , three  ')
        result = simple_executor.send(:parse_array_env, 'TEST_KEY')
        expect(result).to eq(%w[one two three])
      end
    end

    context 'with invalid or missing values' do
      it 'returns nil for missing environment variable' do
        allow(ENV).to receive(:fetch).with('MISSING_KEY', nil).and_return(nil)
        result = simple_executor.send(:parse_array_env, 'MISSING_KEY')
        expect(result).to be_nil
      end

      it 'returns nil for empty string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('')
        result = simple_executor.send(:parse_array_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil for whitespace-only string' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('   ')
        result = simple_executor.send(:parse_array_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil for string with only commas and whitespace' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return(' , , ')
        result = simple_executor.send(:parse_array_env, 'TEST_KEY')
        expect(result).to be_nil
      end

      it 'returns nil for string with only commas' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return(',,,')
        result = simple_executor.send(:parse_array_env, 'TEST_KEY')
        expect(result).to be_nil
      end
    end

    context 'consistency with other parsing methods' do
      it 'behaves like parse_float_env and parse_int_env for empty values' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('')

        float_result = simple_executor.send(:parse_float_env, 'TEST_KEY')
        int_result = simple_executor.send(:parse_int_env, 'TEST_KEY')
        array_result = simple_executor.send(:parse_array_env, 'TEST_KEY')

        expect(float_result).to be_nil
        expect(int_result).to be_nil
        expect(array_result).to be_nil
      end

      it 'behaves like parse_float_env and parse_int_env for whitespace values' do
        allow(ENV).to receive(:fetch).with('TEST_KEY', nil).and_return('   ')

        float_result = simple_executor.send(:parse_float_env, 'TEST_KEY')
        int_result = simple_executor.send(:parse_int_env, 'TEST_KEY')
        array_result = simple_executor.send(:parse_array_env, 'TEST_KEY')

        expect(float_result).to be_nil
        expect(int_result).to be_nil
        expect(array_result).to be_nil
      end
    end
  end

  describe 'safety configuration integration' do
    context 'when parse methods return nil for invalid values' do
      let(:agent_definition) { double('AgentDefinition', constraints: { daily_budget: nil }) }
      let(:test_agent) { instance_double('LanguageOperator::Agent::Base', workspace_path: '/tmp/test') }

      before do
        # Mock all ENV vars that the executor might access
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('DAILY_BUDGET', nil).and_return('invalid')
        allow(ENV).to receive(:fetch).with('SAFETY_ENABLED', 'true').and_return('true')
        allow(ENV).to receive(:fetch).with('SHOW_FULL_RESPONSES', 'false').and_return('false')
      end

      it 'handles nil values gracefully in safety configuration' do
        # Create executor with proper mocking
        test_executor = described_class.new(test_agent, agent_definition: agent_definition)
        logger = double('Logger', warn: nil)
        allow(test_executor).to receive(:logger).and_return(logger)

        # Test that parse_float_env returns nil for invalid value and warns
        expect(logger).to receive(:warn).with('Invalid float value for DAILY_BUDGET: invalid. Ignoring.')
        result = test_executor.send(:parse_float_env, 'DAILY_BUDGET')
        expect(result).to be_nil
      end
    end
  end
end
