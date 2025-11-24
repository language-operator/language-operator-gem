# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'language_operator/agent/webhook_authenticator'

RSpec.describe LanguageOperator::Agent::WebhookAuthenticator do
  let(:context_with_headers) { { headers: headers } }
  let(:context_with_body) { { headers: headers, body: body } }

  describe '.authenticate' do
    context 'when no authentication is required' do
      it 'returns true' do
        expect(described_class.authenticate(nil, {})).to be true
      end
    end

    context 'when authentication type is unknown' do
      let(:auth) { double('auth', type: :unknown) }

      it 'returns false' do
        expect(described_class.authenticate(auth, {})).to be false
      end
    end
  end

  describe '.verify_basic_auth' do
    let(:config) { { username: 'test_user', password: 'test_pass' } }
    let(:valid_credentials) { Base64.encode64('test_user:test_pass').strip }
    let(:headers) { { 'Authorization' => "Basic #{valid_credentials}" } }

    context 'with valid credentials' do
      it 'returns true' do
        result = described_class.send(:verify_basic_auth, config, context_with_headers)
        expect(result).to be true
      end
    end

    context 'with invalid username' do
      let(:invalid_credentials) { Base64.encode64('wrong_user:test_pass').strip }
      let(:headers) { { 'Authorization' => "Basic #{invalid_credentials}" } }

      it 'returns false' do
        result = described_class.send(:verify_basic_auth, config, context_with_headers)
        expect(result).to be false
      end
    end

    context 'with invalid password' do
      let(:invalid_credentials) { Base64.encode64('test_user:wrong_pass').strip }
      let(:headers) { { 'Authorization' => "Basic #{invalid_credentials}" } }

      it 'returns false' do
        result = described_class.send(:verify_basic_auth, config, context_with_headers)
        expect(result).to be false
      end
    end

    context 'with malformed credentials (no colon)' do
      let(:malformed_credentials) { Base64.encode64('just_username_no_colon').strip }
      let(:headers) { { 'Authorization' => "Basic #{malformed_credentials}" } }

      it 'returns false without raising error' do
        expect do
          result = described_class.send(:verify_basic_auth, config, context_with_headers)
          expect(result).to be false
        end.not_to raise_error
      end
    end

    context 'with empty credentials' do
      let(:empty_credentials) { Base64.encode64('').strip }
      let(:headers) { { 'Authorization' => "Basic #{empty_credentials}" } }

      it 'returns false without raising error' do
        expect do
          result = described_class.send(:verify_basic_auth, config, context_with_headers)
          expect(result).to be false
        end.not_to raise_error
      end
    end

    context 'with credentials containing only colon' do
      let(:colon_only_credentials) { Base64.encode64(':').strip }
      let(:headers) { { 'Authorization' => "Basic #{colon_only_credentials}" } }

      it 'returns false' do
        result = described_class.send(:verify_basic_auth, config, context_with_headers)
        expect(result).to be false
      end
    end

    context 'with credentials having empty password' do
      let(:empty_password_credentials) { Base64.encode64('test_user:').strip }
      let(:headers) { { 'Authorization' => "Basic #{empty_password_credentials}" } }

      it 'returns false' do
        result = described_class.send(:verify_basic_auth, config, context_with_headers)
        expect(result).to be false
      end
    end

    context 'with invalid base64' do
      let(:headers) { { 'Authorization' => 'Basic invalid_base64!' } }

      it 'returns false without raising error' do
        expect do
          result = described_class.send(:verify_basic_auth, config, context_with_headers)
          expect(result).to be false
        end.not_to raise_error
      end
    end

    context 'without Authorization header' do
      let(:headers) { {} }

      it 'returns false' do
        result = described_class.send(:verify_basic_auth, config, context_with_headers)
        expect(result).to be false
      end
    end

    context 'with non-Basic authorization' do
      let(:headers) { { 'Authorization' => 'Bearer token123' } }

      it 'returns false' do
        result = described_class.send(:verify_basic_auth, config, context_with_headers)
        expect(result).to be false
      end
    end
  end

  describe '.verify_bearer_token' do
    let(:config) { { token: 'secret_token' } }
    let(:headers) { { 'Authorization' => 'Bearer secret_token' } }

    context 'with valid token' do
      it 'returns true' do
        result = described_class.send(:verify_bearer_token, config, context_with_headers)
        expect(result).to be true
      end
    end

    context 'with invalid token' do
      let(:headers) { { 'Authorization' => 'Bearer wrong_token' } }

      it 'returns false' do
        result = described_class.send(:verify_bearer_token, config, context_with_headers)
        expect(result).to be false
      end
    end

    context 'with malformed bearer header' do
      let(:headers) { { 'Authorization' => 'Bearer' } }

      it 'returns false' do
        result = described_class.send(:verify_bearer_token, config, context_with_headers)
        expect(result).to be false
      end
    end

    context 'without Authorization header' do
      let(:headers) { {} }

      it 'returns false' do
        result = described_class.send(:verify_bearer_token, config, context_with_headers)
        expect(result).to be false
      end
    end
  end

  describe '.verify_api_key' do
    let(:config) { { header: 'X-API-Key', key: 'secret_key' } }
    let(:headers) { { 'X-API-Key' => 'secret_key' } }

    context 'with valid API key' do
      it 'returns true' do
        result = described_class.send(:verify_api_key, config, context_with_headers)
        expect(result).to be true
      end
    end

    context 'with invalid API key' do
      let(:headers) { { 'X-API-Key' => 'wrong_key' } }

      it 'returns false' do
        result = described_class.send(:verify_api_key, config, context_with_headers)
        expect(result).to be false
      end
    end

    context 'without API key header' do
      let(:headers) { {} }

      it 'returns false' do
        result = described_class.send(:verify_api_key, config, context_with_headers)
        expect(result).to be false
      end
    end
  end

  describe '.verify_signature' do
    let(:config) { { header: 'X-Signature', secret: 'webhook_secret', algorithm: :sha256 } }
    let(:body) { '{"test": "payload"}' }
    let(:expected_signature) { OpenSSL::HMAC.hexdigest('sha256', 'webhook_secret', body) }
    let(:headers) { { 'X-Signature' => expected_signature } }

    context 'with valid signature' do
      it 'returns true' do
        result = described_class.send(:verify_signature, config, context_with_body)
        expect(result).to be true
      end
    end

    context 'with invalid signature' do
      let(:headers) { { 'X-Signature' => 'invalid_signature' } }

      it 'returns false' do
        result = described_class.send(:verify_signature, config, context_with_body)
        expect(result).to be false
      end
    end

    context 'with signature prefix' do
      let(:config) { { header: 'X-Signature', secret: 'webhook_secret', algorithm: :sha256, prefix: 'sha256=' } }
      let(:headers) { { 'X-Signature' => "sha256=#{expected_signature}" } }

      it 'strips prefix and validates' do
        result = described_class.send(:verify_signature, config, context_with_body)
        expect(result).to be true
      end
    end

    context 'without signature header' do
      let(:headers) { {} }

      it 'returns false' do
        result = described_class.send(:verify_signature, config, context_with_body)
        expect(result).to be false
      end
    end
  end

  describe '.secure_compare' do
    context 'with identical strings' do
      it 'returns true' do
        result = described_class.send(:secure_compare, 'test', 'test')
        expect(result).to be true
      end
    end

    context 'with different strings' do
      it 'returns false' do
        result = described_class.send(:secure_compare, 'test', 'different')
        expect(result).to be false
      end
    end

    context 'with nil values' do
      it 'returns false for nil first argument' do
        result = described_class.send(:secure_compare, nil, 'test')
        expect(result).to be false
      end

      it 'returns false for nil second argument' do
        result = described_class.send(:secure_compare, 'test', nil)
        expect(result).to be false
      end

      it 'returns false for both nil arguments' do
        result = described_class.send(:secure_compare, nil, nil)
        expect(result).to be false
      end
    end

    context 'with different length strings' do
      it 'returns false' do
        result = described_class.send(:secure_compare, 'short', 'much_longer_string')
        expect(result).to be false
      end
    end
  end

  describe '.get_header' do
    let(:headers) { { 'Content-Type' => 'application/json', 'x-custom' => 'value' } }
    let(:context) { { headers: headers } }

    context 'with exact case match' do
      it 'returns the header value' do
        result = described_class.send(:get_header, context, 'Content-Type')
        expect(result).to eq('application/json')
      end
    end

    context 'with case-insensitive match' do
      it 'returns the header value' do
        result = described_class.send(:get_header, context, 'content-type')
        expect(result).to eq('application/json')
      end

      it 'returns the header value for uppercase' do
        result = described_class.send(:get_header, context, 'X-CUSTOM')
        expect(result).to eq('value')
      end
    end

    context 'with non-existent header' do
      it 'returns nil' do
        result = described_class.send(:get_header, context, 'X-Missing')
        expect(result).to be_nil
      end
    end

    context 'with no headers' do
      let(:context) { {} }

      it 'returns nil' do
        result = described_class.send(:get_header, context, 'Content-Type')
        expect(result).to be_nil
      end
    end
  end
end
