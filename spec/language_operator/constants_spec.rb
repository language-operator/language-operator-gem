# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/constants'

RSpec.describe LanguageOperator::Constants do
  describe '.normalize_mode' do
    context 'with nil input' do
      it 'returns nil' do
        expect(described_class.normalize_mode(nil)).to be_nil
      end
    end

    context 'with valid modes' do
      it 'normalizes primary modes correctly' do
        expect(described_class.normalize_mode('autonomous')).to eq('autonomous')
        expect(described_class.normalize_mode('scheduled')).to eq('scheduled')
        expect(described_class.normalize_mode('reactive')).to eq('reactive')
      end

      it 'normalizes mode aliases correctly' do
        expect(described_class.normalize_mode('interactive')).to eq('autonomous')
        expect(described_class.normalize_mode('webhook')).to eq('reactive')
        expect(described_class.normalize_mode('http')).to eq('reactive')
        expect(described_class.normalize_mode('event-driven')).to eq('scheduled')
      end

      it 'handles case insensitive input' do
        expect(described_class.normalize_mode('AUTONOMOUS')).to eq('autonomous')
        expect(described_class.normalize_mode('Interactive')).to eq('autonomous')
        expect(described_class.normalize_mode('SCHEDULED')).to eq('scheduled')
      end

      it 'handles whitespace around valid modes' do
        expect(described_class.normalize_mode('  autonomous  ')).to eq('autonomous')
        expect(described_class.normalize_mode("\tinteractive\n")).to eq('autonomous')
        expect(described_class.normalize_mode('  SCHEDULED  ')).to eq('scheduled')
      end
    end

    context 'with empty or whitespace input' do
      it 'raises helpful error for empty string' do
        expect { described_class.normalize_mode('') }.to raise_error(
          ArgumentError,
          /AGENT_MODE environment variable is required but is unset or empty/
        )
      end

      it 'raises helpful error for whitespace-only string' do
        expect { described_class.normalize_mode('   ') }.to raise_error(
          ArgumentError,
          /AGENT_MODE environment variable is required but is unset or empty/
        )
      end

      it 'raises helpful error for tab/newline whitespace' do
        expect { described_class.normalize_mode("\t\n  \r") }.to raise_error(
          ArgumentError,
          /AGENT_MODE environment variable is required but is unset or empty/
        )
      end

      it 'includes valid modes in error message' do
        expect { described_class.normalize_mode('') }.to raise_error(
          ArgumentError,
          /Please set AGENT_MODE to one of: #{LanguageOperator::Constants::ALL_MODE_ALIASES.join(', ')}/
        )
      end
    end

    context 'with invalid modes' do
      it 'raises error for unknown mode' do
        expect { described_class.normalize_mode('invalid') }.to raise_error(
          ArgumentError,
          /Unknown execution mode: invalid\. Valid modes:/
        )
      end

      it 'raises error for partial matches' do
        expect { described_class.normalize_mode('auto') }.to raise_error(
          ArgumentError,
          /Unknown execution mode: auto\. Valid modes:/
        )
      end

      it 'includes all valid modes in error message' do
        expect { described_class.normalize_mode('bad_mode') }.to raise_error(
          ArgumentError,
          /Valid modes: #{LanguageOperator::Constants::ALL_MODE_ALIASES.join(', ')}/
        )
      end
    end

    context 'error message quality' do
      it 'provides specific guidance for empty AGENT_MODE' do
        error_message = nil
        begin
          described_class.normalize_mode('')
        rescue ArgumentError => e
          error_message = e.message
        end

        expect(error_message).to include('AGENT_MODE environment variable is required')
        expect(error_message).to include('unset or empty')
        expect(error_message).to include('Please set AGENT_MODE')
        expect(error_message).to include('autonomous')
        expect(error_message).to include('interactive')
        expect(error_message).to include('scheduled')
      end

      it 'provides clear guidance for invalid modes' do
        error_message = nil
        begin
          described_class.normalize_mode('wrong')
        rescue ArgumentError => e
          error_message = e.message
        end

        expect(error_message).to include('Unknown execution mode: wrong')
        expect(error_message).to include('Valid modes:')
        expect(error_message).to include('autonomous')
        expect(error_message).to include('interactive')
        expect(error_message).to include('scheduled')
      end
    end
  end

  describe '.valid_mode?' do
    it 'returns true for valid modes' do
      expect(described_class.valid_mode?('autonomous')).to be true
      expect(described_class.valid_mode?('interactive')).to be true
      expect(described_class.valid_mode?('webhook')).to be true
    end

    it 'returns false for invalid modes' do
      expect(described_class.valid_mode?('invalid')).to be false
      expect(described_class.valid_mode?(nil)).to be false
      expect(described_class.valid_mode?('')).to be false
    end

    it 'handles case insensitive validation' do
      expect(described_class.valid_mode?('AUTONOMOUS')).to be true
      expect(described_class.valid_mode?('Interactive')).to be true
    end

    it 'handles whitespace in validation' do
      expect(described_class.valid_mode?('  autonomous  ')).to be true
      expect(described_class.valid_mode?("\tinteractive\n")).to be true
    end
  end
end
