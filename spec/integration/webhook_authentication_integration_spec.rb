# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'language_operator'
require 'openssl'

RSpec.describe 'Webhook Authentication Integration', type: :integration do
  include Rack::Test::Methods

  let(:secret) { 'webhook-secret-123' }
  let(:api_key) { 'api-key-456' }

  # Define test agent with authenticated webhooks
  let(:agent_definition) do
    LanguageOperator::Dsl.define_agents do
      agent 'auth-test-agent' do
        mode :reactive

        # Webhook with signature authentication
        webhook '/signature-auth' do
          method :post
          authenticate do
            verify_signature(
              header: 'X-Signature',
              secret: 'webhook-secret-123',
              algorithm: :sha256
            )
          end
          on_request { |_ctx| { status: 'authenticated' } }
        end

        # Webhook with API key authentication
        webhook '/api-key-auth' do
          method :post
          authenticate do
            verify_api_key(header: 'X-API-Key', key: 'api-key-456')
          end
          on_request { |_ctx| { status: 'authenticated' } }
        end

        # Webhook with bearer token authentication
        webhook '/bearer-auth' do
          method :post
          authenticate do
            verify_bearer_token(token: 'bearer-token-789')
          end
          on_request { |_ctx| { status: 'authenticated' } }
        end

        # Webhook with validation
        webhook '/validated' do
          method :post
          require_content_type 'application/json'
          require_headers('X-Request-ID' => nil)
          on_request { |_ctx| { status: 'validated' } }
        end

        # Webhook with both authentication and validation
        webhook '/auth-and-validate' do
          method :post
          authenticate do
            verify_api_key(header: 'X-API-Key', key: 'api-key-456')
          end
          require_content_type 'application/json'
          on_request { |_ctx| { status: 'success' } }
        end

        # Webhook with any_of authentication
        webhook '/any-auth' do
          method :post
          authenticate do
            any_of do
              verify_api_key(header: 'X-API-Key', key: 'key1')
              verify_bearer_token(token: 'token1')
            end
          end
          on_request { |_ctx| { status: 'authenticated' } }
        end

        # Webhook with all_of authentication
        webhook '/all-auth' do
          method :post
          authenticate do
            all_of do
              verify_api_key(header: 'X-API-Key', key: 'key1')
              verify_custom { |ctx| ctx[:params]['valid'] == 'true' }
            end
          end
          on_request { |_ctx| { status: 'authenticated' } }
        end
      end
    end

    LanguageOperator::Dsl.agent_registry.get('auth-test-agent')
  end

  let(:agent_instance) do
    LanguageOperator::Agent::Base.new(
      name: 'auth-test-agent',
      persona: 'test agent',
      model: 'claude-sonnet-4'
    )
  end

  let(:web_server) do
    server = LanguageOperator::Agent::WebServer.new(agent_instance)
    agent_definition.instance_variable_get(:@webhooks).each do |webhook|
      webhook.register(server)
    end
    server
  end

  def app
    web_server.send(:rack_app)
  end

  describe 'signature authentication' do
    let(:body) { '{"test":"data"}' }
    let(:signature) { OpenSSL::HMAC.hexdigest('sha256', secret, body) }

    it 'allows requests with valid signature' do
      post '/signature-auth', body, { 'X-Signature' => signature }

      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json['status']).to eq('authenticated')
    end

    it 'rejects requests with invalid signature' do
      post '/signature-auth', body, { 'X-Signature' => 'invalid' }

      expect(last_response.status).to eq(401)
      json = JSON.parse(last_response.body)
      expect(json['error']).to eq('Unauthorized')
    end

    it 'rejects requests without signature' do
      post '/signature-auth', body

      expect(last_response.status).to eq(401)
    end
  end

  describe 'API key authentication' do
    it 'allows requests with valid API key' do
      post '/api-key-auth', '{}', { 'X-API-Key' => api_key }

      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json['status']).to eq('authenticated')
    end

    it 'rejects requests with invalid API key' do
      post '/api-key-auth', '{}', { 'X-API-Key' => 'wrong-key' }

      expect(last_response.status).to eq(401)
    end

    it 'rejects requests without API key' do
      post '/api-key-auth', '{}'

      expect(last_response.status).to eq(401)
    end
  end

  describe 'bearer token authentication' do
    it 'allows requests with valid bearer token' do
      post '/bearer-auth', '{}', { 'Authorization' => 'Bearer bearer-token-789' }

      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json['status']).to eq('authenticated')
    end

    it 'rejects requests with invalid bearer token' do
      post '/bearer-auth', '{}', { 'Authorization' => 'Bearer wrong-token' }

      expect(last_response.status).to eq(401)
    end

    it 'rejects requests without authorization header' do
      post '/bearer-auth', '{}'

      expect(last_response.status).to eq(401)
    end
  end

  describe 'validation' do
    it 'allows requests that pass validation' do
      post '/validated', '{}',
           {
             'HTTP_CONTENT_TYPE' => 'application/json',
             'X-Request-ID' => 'req-123'
           }

      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json['status']).to eq('validated')
    end

    it 'rejects requests with wrong content type' do
      post '/validated', '{}',
           {
             'HTTP_CONTENT_TYPE' => 'text/plain',
             'X-Request-ID' => 'req-123'
           }

      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)
      expect(json['error']).to eq('Bad Request')
      expect(json['errors']).to be_an(Array)
    end

    it 'rejects requests missing required headers' do
      post '/validated', '{}', { 'HTTP_CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)
      expect(json['errors']).to include('Missing required header: X-Request-ID')
    end
  end

  describe 'combined authentication and validation' do
    it 'allows requests that pass both checks' do
      post '/auth-and-validate', '{}',
           {
             'X-API-Key' => api_key,
             'HTTP_CONTENT_TYPE' => 'application/json'
           }

      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json['status']).to eq('success')
    end

    it 'rejects on failed authentication before validation' do
      post '/auth-and-validate', '{}',
           {
             'X-API-Key' => 'wrong-key',
             'HTTP_CONTENT_TYPE' => 'application/json'
           }

      expect(last_response.status).to eq(401)
    end

    it 'rejects on failed validation after authentication' do
      post '/auth-and-validate', '{}',
           {
             'X-API-Key' => api_key,
             'HTTP_CONTENT_TYPE' => 'text/plain'
           }

      expect(last_response.status).to eq(400)
    end
  end

  describe 'any_of authentication' do
    it 'allows with first method' do
      post '/any-auth', '{}', { 'X-API-Key' => 'key1' }

      expect(last_response.status).to eq(200)
    end

    it 'allows with second method' do
      post '/any-auth', '{}', { 'Authorization' => 'Bearer token1' }

      expect(last_response.status).to eq(200)
    end

    it 'rejects when all methods fail' do
      post '/any-auth', '{}'

      expect(last_response.status).to eq(401)
    end
  end

  describe 'all_of authentication' do
    it 'allows when all methods succeed' do
      post '/all-auth?valid=true', '{}', { 'X-API-Key' => 'key1' }

      expect(last_response.status).to eq(200)
    end

    it 'rejects when any method fails' do
      post '/all-auth?valid=false', '{}', { 'X-API-Key' => 'key1' }

      expect(last_response.status).to eq(401)
    end
  end

  describe 'backward compatibility' do
    it 'works with webhooks without authentication' do
      # The default /health endpoint doesn't have authentication
      get '/health'

      expect(last_response.status).to eq(200)
    end
  end
end
