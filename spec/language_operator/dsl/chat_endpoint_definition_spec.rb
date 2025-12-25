# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Dsl::ChatEndpointDefinition do
  let(:definition) { described_class.new('test-agent') }

  describe 'initialization' do
    it 'sets default values' do
      expect(definition.system_prompt).to be_nil
      expect(definition.temperature).to eq(0.7)
      expect(definition.max_tokens).to eq(2000)
      expect(definition.model_name).to eq('test-agent')
      expect(definition.identity_awareness_enabled).to be true
      expect(definition.prompt_template_level).to eq(:standard)
      expect(definition.context_injection_level).to eq(:standard)
    end
  end

  describe 'identity awareness configuration' do
    describe '#enable_identity_awareness' do
      it 'sets and returns identity awareness setting' do
        expect(definition.enable_identity_awareness).to be true
        
        definition.enable_identity_awareness(false)
        expect(definition.enable_identity_awareness).to be false
      end
    end

    describe '#prompt_template' do
      it 'sets and returns template level' do
        expect(definition.prompt_template).to eq(:standard)
        
        definition.prompt_template(:detailed)
        expect(definition.prompt_template).to eq(:detailed)
      end

      it 'raises error for invalid template level' do
        expect { definition.prompt_template(:invalid) }
          .to raise_error(ArgumentError, /Invalid template level/)
      end

      it 'accepts valid template levels' do
        %i[minimal standard detailed comprehensive].each do |level|
          expect { definition.prompt_template(level) }.not_to raise_error
        end
      end
    end

    describe '#context_injection' do
      it 'sets and returns context injection level' do
        expect(definition.context_injection).to eq(:standard)
        
        definition.context_injection(:detailed)
        expect(definition.context_injection).to eq(:detailed)
      end

      it 'raises error for invalid context level' do
        expect { definition.context_injection(:invalid) }
          .to raise_error(ArgumentError, /Invalid context level/)
      end

      it 'accepts valid context levels' do
        %i[none minimal standard detailed].each do |level|
          expect { definition.context_injection(level) }.not_to raise_error
        end
      end
    end

    describe '#identity_awareness' do
      it 'returns current configuration when no block given' do
        config = definition.identity_awareness
        
        expect(config[:enabled]).to be true
        expect(config[:prompt_template]).to eq(:standard)
        expect(config[:context_injection]).to eq(:standard)
      end

      it 'allows configuration via block' do
        definition.identity_awareness do
          enabled false
          prompt_template :minimal
          context_injection :none
        end

        expect(definition.identity_awareness_enabled).to be false
        expect(definition.prompt_template_level).to eq(:minimal)
        expect(definition.context_injection_level).to eq(:none)
      end
    end
  end

  describe 'backward compatibility' do
    it 'maintains existing API' do
      definition.system_prompt('Test prompt')
      definition.temperature(0.8)
      definition.max_tokens(1500)

      expect(definition.system_prompt).to eq('Test prompt')
      expect(definition.temperature).to eq(0.8)
      expect(definition.max_tokens).to eq(1500)
    end
  end

  describe 'DSL usage example' do
    it 'works with realistic configuration' do
      definition.system_prompt('You are a helpful assistant')
      
      definition.identity_awareness do
        enabled true
        prompt_template :detailed
        context_injection :standard
      end
      
      definition.temperature(0.7)
      definition.max_tokens(2000)

      expect(definition.system_prompt).to eq('You are a helpful assistant')
      expect(definition.identity_awareness_enabled).to be true
      expect(definition.prompt_template_level).to eq(:detailed)
      expect(definition.context_injection_level).to eq(:standard)
      expect(definition.temperature).to eq(0.7)
      expect(definition.max_tokens).to eq(2000)
    end
  end
end