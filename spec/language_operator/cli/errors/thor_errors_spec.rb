# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/errors/thor_errors'

RSpec.describe LanguageOperator::CLI::Errors do
  describe 'ThorCompatibleError' do
    it 'extends Thor::Error' do
      expect(described_class::ThorCompatibleError.new).to be_a(Thor::Error)
    end

    it 'defaults to exit code 1' do
      error = described_class::ThorCompatibleError.new('test error')
      expect(error.exit_code).to eq(1)
    end

    it 'accepts custom exit code' do
      error = described_class::ThorCompatibleError.new('test error', 42)
      expect(error.exit_code).to eq(42)
    end
  end

  describe 'NotFoundError' do
    it 'has exit code 2' do
      error = described_class::NotFoundError.new('Resource not found')
      expect(error.exit_code).to eq(2)
      expect(error.message).to eq('Resource not found')
    end
  end

  describe 'ValidationError' do
    it 'has exit code 3' do
      error = described_class::ValidationError.new('Validation failed')
      expect(error.exit_code).to eq(3)
      expect(error.message).to eq('Validation failed')
    end
  end

  describe 'NetworkError' do
    it 'has exit code 4' do
      error = described_class::NetworkError.new('Network failed')
      expect(error.exit_code).to eq(4)
      expect(error.message).to eq('Network failed')
    end
  end

  describe 'AuthError' do
    it 'has exit code 5' do
      error = described_class::AuthError.new('Auth failed')
      expect(error.exit_code).to eq(5)
      expect(error.message).to eq('Auth failed')
    end
  end

  describe 'SynthesisError' do
    it 'has exit code 6' do
      error = described_class::SynthesisError.new('Synthesis failed')
      expect(error.exit_code).to eq(6)
      expect(error.message).to eq('Synthesis failed')
    end
  end
end