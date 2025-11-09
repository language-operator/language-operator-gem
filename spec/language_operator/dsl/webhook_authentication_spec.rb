# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/webhook_authentication'

RSpec.describe LanguageOperator::Dsl::WebhookAuthentication do
  let(:auth) { described_class.new }

  describe '#verify_signature' do
    it 'configures signature verification' do
      auth.verify_signature(
        header: 'X-Hub-Signature',
        secret: 'secret123',
        algorithm: :sha256,
        prefix: 'sha256='
      )

      expect(auth.type).to eq(:signature)
      expect(auth.config[:header]).to eq('X-Hub-Signature')
      expect(auth.config[:secret]).to eq('secret123')
      expect(auth.config[:algorithm]).to eq(:sha256)
      expect(auth.config[:prefix]).to eq('sha256=')
    end

    it 'uses default algorithm if not specified' do
      auth.verify_signature(header: 'X-Signature', secret: 'secret')

      expect(auth.config[:algorithm]).to eq(:sha256)
    end
  end

  describe '#verify_api_key' do
    it 'configures API key verification' do
      auth.verify_api_key(header: 'X-API-Key', key: 'key123')

      expect(auth.type).to eq(:api_key)
      expect(auth.config[:header]).to eq('X-API-Key')
      expect(auth.config[:key]).to eq('key123')
    end
  end

  describe '#verify_bearer_token' do
    it 'configures bearer token verification' do
      auth.verify_bearer_token(token: 'token123')

      expect(auth.type).to eq(:bearer_token)
      expect(auth.config[:token]).to eq('token123')
    end
  end

  describe '#verify_basic_auth' do
    it 'configures basic auth verification' do
      auth.verify_basic_auth(username: 'user', password: 'pass')

      expect(auth.type).to eq(:basic_auth)
      expect(auth.config[:username]).to eq('user')
      expect(auth.config[:password]).to eq('pass')
    end
  end

  describe '#verify_custom' do
    it 'configures custom authentication callback' do
      callback = proc { |_context| true }
      auth.verify_custom(&callback)

      expect(auth.type).to eq(:custom)
      expect(auth.config[:callback]).to eq(callback)
    end
  end

  describe '#any_of' do
    it 'configures multiple authentication methods (any)' do
      auth.any_of do
        verify_api_key(header: 'X-API-Key', key: 'key1')
        verify_bearer_token(token: 'token1')
      end

      expect(auth.type).to eq(:any_of)
      expect(auth.config[:methods]).to be_an(Array)
      expect(auth.config[:methods].length).to eq(2)
      expect(auth.config[:methods][0].type).to eq(:api_key)
      expect(auth.config[:methods][1].type).to eq(:bearer_token)
    end
  end

  describe '#all_of' do
    it 'configures multiple authentication methods (all)' do
      auth.all_of do
        verify_api_key(header: 'X-API-Key', key: 'key1')
        verify_signature(header: 'X-Signature', secret: 'secret')
      end

      expect(auth.type).to eq(:all_of)
      expect(auth.config[:methods]).to be_an(Array)
      expect(auth.config[:methods].length).to eq(2)
      expect(auth.config[:methods][0].type).to eq(:api_key)
      expect(auth.config[:methods][1].type).to eq(:signature)
    end
  end
end
