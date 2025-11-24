# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/helpers/user_prompts'

RSpec.describe LanguageOperator::CLI::Helpers::UserPrompts do
  describe '.confirm' do
    it 'returns true when user enters y' do
      allow($stdin).to receive(:gets).and_return("y\n")
      expect(described_class.confirm('Test message')).to be true
    end

    it 'returns true when user enters Y' do
      allow($stdin).to receive(:gets).and_return("Y\n")
      expect(described_class.confirm('Test message')).to be true
    end

    it 'returns false when user enters n' do
      allow($stdin).to receive(:gets).and_return("n\n")
      expect(described_class.confirm('Test message')).to be false
    end

    it 'returns false when user enters anything else' do
      allow($stdin).to receive(:gets).and_return("maybe\n")
      expect(described_class.confirm('Test message')).to be false
    end

    it 'returns false when user enters nothing' do
      allow($stdin).to receive(:gets).and_return("\n")
      expect(described_class.confirm('Test message')).to be false
    end

    it 'returns true when force is true regardless of input' do
      expect(described_class.confirm('Test message', force: true)).to be true
    end

    it 'handles nil input gracefully' do
      allow($stdin).to receive(:gets).and_return(nil)
      expect(described_class.confirm('Test message')).to be false
    end
  end

  describe '.confirm!' do
    it 'continues when user confirms' do
      allow($stdin).to receive(:gets).and_return("y\n")
      expect { described_class.confirm!('Test message') }.not_to raise_error
    end

    it 'exits when user does not confirm' do
      allow($stdin).to receive(:gets).and_return("n\n")
      expect { described_class.confirm!('Test message') }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    it 'continues when force is true' do
      expect { described_class.confirm!('Test message', force: true) }.not_to raise_error
    end

    it 'displays custom cancel message on exit' do
      allow($stdin).to receive(:gets).and_return("n\n")
      expect { described_class.confirm!('Test', cancel_message: 'Custom message') }.to raise_error(SystemExit)
    end
  end

  describe '.ask' do
    it 'returns user input when provided' do
      allow($stdin).to receive(:gets).and_return("user input\n")
      expect(described_class.ask('Enter something')).to eq('user input')
    end

    it 'returns default value when user enters nothing and default is provided' do
      allow($stdin).to receive(:gets).and_return("\n")
      expect(described_class.ask('Enter something', default: 'default')).to eq('default')
    end

    it 'returns empty string when user enters nothing and no default' do
      allow($stdin).to receive(:gets).and_return("\n")
      expect(described_class.ask('Enter something')).to eq('')
    end

    it 'handles nil input gracefully' do
      allow($stdin).to receive(:gets).and_return(nil)
      expect(described_class.ask('Enter something', default: 'default')).to eq('default')
    end
  end

  describe '.select' do
    let(:options) { ['Option A', 'Option B', 'Option C'] }

    it 'returns selected option for valid input' do
      allow($stdin).to receive(:gets).and_return("2\n")
      expect(described_class.select('Choose option:', options)).to eq('Option B')
    end

    it 'returns first option when user selects 1' do
      allow($stdin).to receive(:gets).and_return("1\n")
      expect(described_class.select('Choose option:', options)).to eq('Option A')
    end

    it 'returns last option when user selects last number' do
      allow($stdin).to receive(:gets).and_return("3\n")
      expect(described_class.select('Choose option:', options)).to eq('Option C')
    end

    it 'retries on invalid numeric input and then accepts valid input' do
      allow($stdin).to receive(:gets).and_return("0\n", "2\n")
      expect(described_class.select('Choose option:', options)).to eq('Option B')
    end

    it 'retries on out-of-range input and then accepts valid input' do
      allow($stdin).to receive(:gets).and_return("5\n", "1\n")
      expect(described_class.select('Choose option:', options)).to eq('Option A')
    end

    it 'retries on non-numeric input and then accepts valid input' do
      allow($stdin).to receive(:gets).and_return("abc\n", "3\n")
      expect(described_class.select('Choose option:', options)).to eq('Option C')
    end

    it 'retries on empty input and then accepts valid input' do
      allow($stdin).to receive(:gets).and_return("\n", "1\n")
      expect(described_class.select('Choose option:', options)).to eq('Option A')
    end

    it 'exits gracefully when user types q' do
      allow($stdin).to receive(:gets).and_return("q\n")
      expect { described_class.select('Choose option:', options) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    it 'exits gracefully when user types quit' do
      allow($stdin).to receive(:gets).and_return("quit\n")
      expect { described_class.select('Choose option:', options) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    it 'exits gracefully when user types Q (case insensitive)' do
      allow($stdin).to receive(:gets).and_return("Q\n")
      expect { described_class.select('Choose option:', options) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    it 'handles nil input gracefully' do
      allow($stdin).to receive(:gets).and_return(nil, "1\n")
      expect(described_class.select('Choose option:', options)).to eq('Option A')
    end

    it 'retries multiple times for consecutive invalid inputs' do
      allow($stdin).to receive(:gets).and_return("0\n", "abc\n", "5\n", "2\n")
      expect(described_class.select('Choose option:', options)).to eq('Option B')
    end

    context 'with single option' do
      let(:single_option) { ['Only Option'] }

      it 'works with single option list' do
        allow($stdin).to receive(:gets).and_return("1\n")
        expect(described_class.select('Choose:', single_option)).to eq('Only Option')
      end
    end

    context 'display formatting' do
      it 'displays prompt and numbered options' do
        allow($stdin).to receive(:gets).and_return("1\n")

        # Capture output instead of mocking specific calls
        expect { described_class.select('Choose option:', options) }.to output(/Choose option:.*1\. Option A.*2\. Option B.*3\. Option C/m).to_stdout
      end
    end
  end
end
