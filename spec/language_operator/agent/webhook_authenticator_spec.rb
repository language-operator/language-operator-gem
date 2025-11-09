# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/webhook_authenticator'
require 'language_operator/dsl/webhook_authentication'
require 'openssl'
require 'base64'

RSpec.describe LanguageOperator::Agent::WebhookAuthenticator do
  describe '.authenticate' do
    let(:context) do
      {
        headers: {},
        body: 'test body',
        params: {}
      }
    end

    context 'with no authentication' do
      it 'returns true' do
        expect(described_class.authenticate(nil, context)).to be true
      end
    end

    context 'with signature authentication' do
      let(:secret) { 'my-secret' }
      let(:body) { 'test payload' }
      let(:signature) { OpenSSL::HMAC.hexdigest('sha256', secret, body) }

      let(:auth) do
        auth = LanguageOperator::Dsl::WebhookAuthentication.new
        auth.verify_signature(header: 'X-Signature', secret: secret, algorithm: :sha256)
        auth
      end

      it 'authenticates valid signature' do
        ctx = context.merge(
          headers: { 'X-Signature' => signature },
          body: body
        )

        expect(described_class.authenticate(auth, ctx)).to be true
      end

      it 'rejects invalid signature' do
        ctx = context.merge(
          headers: { 'X-Signature' => 'invalid' },
          body: body
        )

        expect(described_class.authenticate(auth, ctx)).to be false
      end

      it 'rejects missing signature' do
        ctx = context.merge(body: body)

        expect(described_class.authenticate(auth, ctx)).to be false
      end

      it 'handles signature with prefix' do
        auth_with_prefix = LanguageOperator::Dsl::WebhookAuthentication.new
        auth_with_prefix.verify_signature(
          header: 'X-Hub-Signature-256',
          secret: secret,
          algorithm: :sha256,
          prefix: 'sha256='
        )

        ctx = context.merge(
          headers: { 'X-Hub-Signature-256' => "sha256=#{signature}" },
          body: body
        )

        expect(described_class.authenticate(auth_with_prefix, ctx)).to be true
      end
    end

    context 'with API key authentication' do
      let(:api_key) { 'secret-key-123' }

      let(:auth) do
        auth = LanguageOperator::Dsl::WebhookAuthentication.new
        auth.verify_api_key(header: 'X-API-Key', key: api_key)
        auth
      end

      it 'authenticates valid API key' do
        ctx = context.merge(headers: { 'X-API-Key' => api_key })

        expect(described_class.authenticate(auth, ctx)).to be true
      end

      it 'rejects invalid API key' do
        ctx = context.merge(headers: { 'X-API-Key' => 'wrong-key' })

        expect(described_class.authenticate(auth, ctx)).to be false
      end

      it 'rejects missing API key' do
        expect(described_class.authenticate(auth, context)).to be false
      end
    end

    context 'with bearer token authentication' do
      let(:token) { 'bearer-token-123' }

      let(:auth) do
        auth = LanguageOperator::Dsl::WebhookAuthentication.new
        auth.verify_bearer_token(token: token)
        auth
      end

      it 'authenticates valid bearer token' do
        ctx = context.merge(headers: { 'Authorization' => "Bearer #{token}" })

        expect(described_class.authenticate(auth, ctx)).to be true
      end

      it 'handles case-insensitive Bearer prefix' do
        ctx = context.merge(headers: { 'Authorization' => "bearer #{token}" })

        expect(described_class.authenticate(auth, ctx)).to be true
      end

      it 'rejects invalid bearer token' do
        ctx = context.merge(headers: { 'Authorization' => 'Bearer wrong-token' })

        expect(described_class.authenticate(auth, ctx)).to be false
      end

      it 'rejects missing authorization header' do
        expect(described_class.authenticate(auth, context)).to be false
      end

      it 'rejects malformed authorization header' do
        ctx = context.merge(headers: { 'Authorization' => 'NotBearer token' })

        expect(described_class.authenticate(auth, ctx)).to be false
      end
    end

    context 'with basic auth authentication' do
      let(:username) { 'testuser' }
      let(:password) { 'testpass' }
      let(:credentials) { Base64.strict_encode64("#{username}:#{password}") }

      let(:auth) do
        auth = LanguageOperator::Dsl::WebhookAuthentication.new
        auth.verify_basic_auth(username: username, password: password)
        auth
      end

      it 'authenticates valid credentials' do
        ctx = context.merge(headers: { 'Authorization' => "Basic #{credentials}" })

        expect(described_class.authenticate(auth, ctx)).to be true
      end

      it 'rejects invalid credentials' do
        wrong_creds = Base64.strict_encode64('wrong:creds')
        ctx = context.merge(headers: { 'Authorization' => "Basic #{wrong_creds}" })

        expect(described_class.authenticate(auth, ctx)).to be false
      end

      it 'rejects missing authorization header' do
        expect(described_class.authenticate(auth, context)).to be false
      end
    end

    context 'with custom authentication' do
      let(:auth) do
        auth = LanguageOperator::Dsl::WebhookAuthentication.new
        auth.verify_custom do |ctx|
          ctx[:headers]['X-Custom-Auth'] == 'valid'
        end
        auth
      end

      it 'authenticates when callback returns true' do
        ctx = context.merge(headers: { 'X-Custom-Auth' => 'valid' })

        expect(described_class.authenticate(auth, ctx)).to be true
      end

      it 'rejects when callback returns false' do
        ctx = context.merge(headers: { 'X-Custom-Auth' => 'invalid' })

        expect(described_class.authenticate(auth, ctx)).to be false
      end

      it 'handles callback errors gracefully' do
        error_auth = LanguageOperator::Dsl::WebhookAuthentication.new
        error_auth.verify_custom { raise 'Error!' }

        expect(described_class.authenticate(error_auth, context)).to be false
      end
    end

    context 'with any_of authentication' do
      let(:auth) do
        auth = LanguageOperator::Dsl::WebhookAuthentication.new
        auth.any_of do
          verify_api_key(header: 'X-API-Key', key: 'key1')
          verify_bearer_token(token: 'token1')
        end
        auth
      end

      it 'authenticates if first method succeeds' do
        ctx = context.merge(headers: { 'X-API-Key' => 'key1' })

        expect(described_class.authenticate(auth, ctx)).to be true
      end

      it 'authenticates if second method succeeds' do
        ctx = context.merge(headers: { 'Authorization' => 'Bearer token1' })

        expect(described_class.authenticate(auth, ctx)).to be true
      end

      it 'rejects if all methods fail' do
        ctx = context.merge(headers: { 'X-API-Key' => 'wrong' })

        expect(described_class.authenticate(auth, ctx)).to be false
      end
    end

    context 'with all_of authentication' do
      let(:auth) do
        auth = LanguageOperator::Dsl::WebhookAuthentication.new
        auth.all_of do
          verify_api_key(header: 'X-API-Key', key: 'key1')
          verify_custom { |ctx| ctx[:params]['valid'] == 'true' }
        end
        auth
      end

      it 'authenticates if all methods succeed' do
        ctx = context.merge(
          headers: { 'X-API-Key' => 'key1' },
          params: { 'valid' => 'true' }
        )

        expect(described_class.authenticate(auth, ctx)).to be true
      end

      it 'rejects if any method fails' do
        ctx = context.merge(
          headers: { 'X-API-Key' => 'key1' },
          params: { 'valid' => 'false' }
        )

        expect(described_class.authenticate(auth, ctx)).to be false
      end
    end
  end

  describe '.validate' do
    let(:context) do
      {
        headers: { 'Content-Type' => 'application/json' },
        body: '{}',
        params: {}
      }
    end

    context 'with header validation' do
      let(:validations) do
        [{ type: :headers, config: { 'X-Required' => nil, 'X-Specific' => 'value' } }]
      end

      it 'passes with all required headers' do
        ctx = context.merge(
          headers: {
            'Content-Type' => 'application/json',
            'X-Required' => 'any',
            'X-Specific' => 'value'
          }
        )

        errors = described_class.validate(validations, ctx)
        expect(errors).to be_empty
      end

      it 'fails when required header is missing' do
        errors = described_class.validate(validations, context)

        expect(errors).to include('Missing required header: X-Required')
      end

      it 'fails when header has wrong value' do
        ctx = context.merge(
          headers: {
            'X-Required' => 'any',
            'X-Specific' => 'wrong'
          }
        )

        errors = described_class.validate(validations, ctx)
        expect(errors).to include('Invalid value for header X-Specific')
      end
    end

    context 'with content-type validation' do
      let(:validations) do
        [{ type: :content_type, config: ['application/json'] }]
      end

      it 'passes with correct content type' do
        errors = described_class.validate(validations, context)
        expect(errors).to be_empty
      end

      it 'handles content type with charset' do
        ctx = context.merge(
          headers: { 'Content-Type' => 'application/json; charset=utf-8' }
        )

        errors = described_class.validate(validations, ctx)
        expect(errors).to be_empty
      end

      it 'fails with incorrect content type' do
        ctx = context.merge(
          headers: { 'Content-Type' => 'text/plain' }
        )

        errors = described_class.validate(validations, ctx)
        expect(errors).not_to be_empty
        expect(errors.first).to include('Invalid Content-Type')
      end

      it 'fails when content type is missing' do
        ctx = context.merge(headers: {})

        errors = described_class.validate(validations, ctx)
        expect(errors).to include('Missing Content-Type header')
      end
    end

    context 'with custom validation' do
      it 'passes when callback returns true' do
        validations = [
          { type: :custom, config: proc { |_ctx| true } }
        ]

        errors = described_class.validate(validations, context)
        expect(errors).to be_empty
      end

      it 'fails when callback returns error message' do
        validations = [
          { type: :custom, config: proc { |_ctx| 'Custom error' } }
        ]

        errors = described_class.validate(validations, context)
        expect(errors).to include('Custom error')
      end
    end

    context 'with multiple validations' do
      let(:validations) do
        [
          { type: :headers, config: { 'X-Required' => nil } },
          { type: :content_type, config: ['application/json'] },
          { type: :custom, config: proc { |ctx| ctx[:params]['valid'] ? true : 'Invalid params' } }
        ]
      end

      it 'collects all validation errors' do
        ctx = {
          headers: { 'Content-Type' => 'text/plain' },
          params: {}
        }

        errors = described_class.validate(validations, ctx)
        expect(errors.length).to eq(3)
      end
    end
  end
end
