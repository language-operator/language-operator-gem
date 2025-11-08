# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'language_operator/agent'
require 'language_operator/agent/web_server'

RSpec.describe LanguageOperator::Agent::WebServer do
  include Rack::Test::Methods

  let(:agent_config) do
    {
      'agent' => {
        'name' => 'test-webhook-agent',
        'instructions' => 'Process webhooks'
      },
      'llm' => {
        'provider' => 'anthropic',
        'model' => 'claude-3-5-sonnet-20241022',
        'api_key' => 'test-key'
      },
      'mcp' => { 'servers' => {} }
    }
  end

  let(:agent) { LanguageOperator::Agent::Base.new(agent_config) }
  let(:web_server) { described_class.new(agent, port: 8080) }
  let(:app) { web_server.send(:rack_app) }

  describe '#initialize' do
    it 'creates a web server with default port' do
      server = described_class.new(agent)
      expect(server.port).to eq(8080)
    end

    it 'accepts custom port' do
      server = described_class.new(agent, port: 9000)
      expect(server.port).to eq(9000)
    end

    it 'uses PORT environment variable' do
      ENV['PORT'] = '3000'
      server = described_class.new(agent)
      expect(server.port).to eq(3000)
      ENV.delete('PORT')
    end
  end

  describe 'default routes' do
    describe 'GET /health' do
      it 'returns healthy status' do
        get '/health'

        expect(last_response).to be_ok
        expect(last_response.content_type).to include('application/json')

        body = JSON.parse(last_response.body)
        expect(body['status']).to eq('healthy')
        expect(body['agent']).to eq('LanguageOperator::Agent::Base')
      end
    end

    describe 'GET /ready' do
      it 'returns ready status when workspace is available' do
        allow(agent).to receive(:workspace_available?).and_return(true)

        get '/ready'

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body['status']).to eq('ready')
      end

      it 'returns not ready when workspace is unavailable' do
        allow(agent).to receive(:workspace_available?).and_return(false)

        get '/ready'

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body['status']).to eq('not_ready')
      end
    end

    describe 'POST /webhook' do
      it 'handles default webhook endpoint' do
        # Mock the executor
        executor = instance_double(LanguageOperator::Agent::Executor)
        allow(LanguageOperator::Agent::Executor).to receive(:new).and_return(executor)
        allow(executor).to receive(:execute_with_context).and_return('Processed')

        post '/webhook', { data: 'test' }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body['status']).to eq('processed')
      end
    end
  end

  describe '#register_route' do
    it 'registers a custom route' do
      handler_called = false
      web_server.register_route('/custom', method: :post) do |_context|
        handler_called = true
        { message: 'custom route' }
      end

      expect(web_server.route_exists?('/custom', :post)).to be true
    end

    it 'handles custom route requests' do
      web_server.register_route('/test', method: :post) do |context|
        { received: context[:params] }
      end

      post '/test', { foo: 'bar' }.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['received']).to be_a(Hash)
    end

    it 'supports different HTTP methods' do
      web_server.register_route('/get-endpoint', method: :get) do
        { method: 'GET' }
      end

      web_server.register_route('/put-endpoint', method: :put) do
        { method: 'PUT' }
      end

      get '/get-endpoint'
      expect(last_response).to be_ok

      put '/put-endpoint'
      expect(last_response).to be_ok
    end
  end

  describe 'request handling' do
    it 'returns 404 for unknown routes' do
      get '/nonexistent'

      expect(last_response.status).to eq(404)
      body = JSON.parse(last_response.body)
      expect(body['error']).to eq('Not Found')
    end

    it 'handles errors gracefully' do
      web_server.register_route('/error', method: :get) do
        raise StandardError, 'Test error'
      end

      get '/error'

      expect(last_response.status).to eq(500)
      body = JSON.parse(last_response.body)
      expect(body['error']).to eq('StandardError')
      expect(body['message']).to eq('Test error')
    end

    it 'extracts request context correctly' do
      received_context = nil
      web_server.register_route('/context-test', method: :post) do |context|
        received_context = context
        { ok: true }
      end

      post '/context-test',
           { data: 'test' }.to_json,
           'CONTENT_TYPE' => 'application/json',
           'HTTP_X_CUSTOM_HEADER' => 'value'

      expect(received_context).to include(
        path: '/context-test',
        method: 'POST'
      )
      expect(received_context[:headers]).to include('X-Custom-Header' => 'value')
    end
  end

  describe '#route_exists?' do
    it 'returns true for registered routes' do
      web_server.register_route('/test', method: :post) { { ok: true } }
      expect(web_server.route_exists?('/test', :post)).to be true
    end

    it 'returns false for non-existent routes' do
      expect(web_server.route_exists?('/nonexistent', :post)).to be false
    end

    it 'distinguishes between HTTP methods' do
      web_server.register_route('/test', method: :get) { { ok: true } }
      expect(web_server.route_exists?('/test', :get)).to be true
      expect(web_server.route_exists?('/test', :post)).to be false
    end
  end
end
