# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/errors/handler'
require 'language_operator/cli/errors/thor_errors'

RSpec.describe LanguageOperator::CLI::Errors::Handler do
  let(:handler) { described_class }

  describe '.handle_not_found' do
    let(:error) { StandardError.new('Agent not found') }
    let(:context) { { resource_type: 'LanguageAgent', resource_name: 'test-agent' } }

    it 'raises NotFoundError' do
      expect do
        handler.handle_not_found(error, context)
      end.to raise_error(LanguageOperator::CLI::Errors::NotFoundError) do |e|
        expect(e.message).to include('Agent')
        expect(e.message).to include('test-agent')
        expect(e.message).to include('not found')
        expect(e.exit_code).to eq(2)
      end
    end

    context 'when DEBUG environment variable is set' do
      before { ENV['DEBUG'] = '1' }
      after { ENV.delete('DEBUG') }

      it 'raises the original error' do
        expect do
          handler.handle_not_found(error, context)
        end.to raise_error(StandardError, 'Agent not found')
      end
    end
  end

  describe '.handle_generic' do
    let(:error) { StandardError.new('Something went wrong') }
    let(:context) { { operation: 'deploy agent' } }

    it 'raises Thor::Error' do
      expect do
        handler.handle_generic(error, context)
      end.to raise_error(Thor::Error) do |e|
        expect(e.message).to include('Failed to deploy agent')
        expect(e.message).to include('Something went wrong')
      end
    end

    context 'when DEBUG environment variable is set' do
      before { ENV['DEBUG'] = '1' }
      after { ENV.delete('DEBUG') }

      it 'raises the original error' do
        expect do
          handler.handle_generic(error, context)
        end.to raise_error(StandardError, 'Something went wrong')
      end
    end
  end

  describe '.handle_no_cluster_selected' do
    it 'raises ValidationError' do
      expect do
        handler.handle_no_cluster_selected
      end.to raise_error(LanguageOperator::CLI::Errors::ValidationError) do |e|
        expect(e.message).to eq('No cluster selected')
        expect(e.exit_code).to eq(3)
      end
    end
  end

  describe '.handle_no_models_available' do
    it 'raises ValidationError' do
      expect do
        handler.handle_no_models_available
      end.to raise_error(LanguageOperator::CLI::Errors::ValidationError) do |e|
        expect(e.message).to eq('No models found in cluster')
        expect(e.exit_code).to eq(3)
      end
    end
  end

  describe '.handle_synthesis_failed' do
    it 'raises SynthesisError' do
      expect do
        handler.handle_synthesis_failed('Invalid agent definition')
      end.to raise_error(LanguageOperator::CLI::Errors::SynthesisError) do |e|
        expect(e.message).to include('Synthesis failed')
        expect(e.message).to include('Invalid agent definition')
        expect(e.exit_code).to eq(6)
      end
    end
  end

  describe '.handle_already_exists' do
    let(:context) { { resource_type: 'LanguageAgent', resource_name: 'test-agent' } }

    it 'raises ValidationError' do
      expect do
        handler.handle_already_exists(context)
      end.to raise_error(LanguageOperator::CLI::Errors::ValidationError) do |e|
        expect(e.message).to include('Agent')
        expect(e.message).to include('test-agent')
        expect(e.message).to include('already exists')
        expect(e.exit_code).to eq(3)
      end
    end
  end
end