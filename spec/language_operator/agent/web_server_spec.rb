# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'stringio'
require 'language_operator/agent/web_server'

RSpec.describe LanguageOperator::Agent::WebServer do
  include Rack::Test::Methods

  let(:agent) do
    instance_double('Agent').tap do |agent_double|
      allow(agent_double).to receive(:workspace_path).and_return('/tmp/workspace')
      allow(agent_double).to receive(:class).and_return(double(name: 'TestAgent'))
    end
  end
  let(:web_server) { described_class.new(agent) }

  describe '#build_request_context' do
    context 'when request has a body' do
      it 'reads the body and rewinds for subsequent reads' do
        body_content = '{"test": "data"}'
        request_body = StringIO.new(body_content)

        # Create a mock request
        request = instance_double('Rack::Request')
        allow(request).to receive(:body).and_return(request_body)
        allow(request).to receive(:path).and_return('/webhook')
        allow(request).to receive(:request_method).and_return('POST')
        allow(request).to receive(:params).and_return({})

        # Mock the extract_headers method
        allow(web_server).to receive(:extract_headers).and_return({})

        # Build request context
        context = web_server.send(:build_request_context, request)

        # Verify the body was included in context
        expect(context[:body]).to eq(body_content)

        # Verify the body can be read again (proving rewind worked)
        subsequent_read = request_body.read
        expect(subsequent_read).to eq(body_content)
      end

      it 'handles multiple sequential reads correctly' do
        body_content = '{"webhook": "payload"}'
        request_body = StringIO.new(body_content)

        request = instance_double('Rack::Request')
        allow(request).to receive(:body).and_return(request_body)
        allow(request).to receive(:path).and_return('/webhook')
        allow(request).to receive(:request_method).and_return('POST')
        allow(request).to receive(:params).and_return({})
        allow(web_server).to receive(:extract_headers).and_return({})

        # First read via build_request_context
        context1 = web_server.send(:build_request_context, request)
        expect(context1[:body]).to eq(body_content)

        # Second read should still work
        context2 = web_server.send(:build_request_context, request)
        expect(context2[:body]).to eq(body_content)

        # Manual read should also work
        manual_read = request_body.read
        expect(manual_read).to eq(body_content)
      end
    end

    context 'when request has no body' do
      it 'returns empty string for body' do
        request = instance_double('Rack::Request')
        allow(request).to receive(:body).and_return(nil)
        allow(request).to receive(:path).and_return('/webhook')
        allow(request).to receive(:request_method).and_return('GET')
        allow(request).to receive(:params).and_return({})
        allow(web_server).to receive(:extract_headers).and_return({})

        context = web_server.send(:build_request_context, request)

        expect(context[:body]).to eq('')
      end
    end

    context 'when request body is empty' do
      it 'handles empty body correctly' do
        request_body = StringIO.new('')

        request = instance_double('Rack::Request')
        allow(request).to receive(:body).and_return(request_body)
        allow(request).to receive(:path).and_return('/webhook')
        allow(request).to receive(:request_method).and_return('POST')
        allow(request).to receive(:params).and_return({})
        allow(web_server).to receive(:extract_headers).and_return({})

        context = web_server.send(:build_request_context, request)

        expect(context[:body]).to eq('')

        # Should still be able to read again
        subsequent_read = request_body.read
        expect(subsequent_read).to eq('')
      end
    end

    it 'includes all expected context fields' do
      body_content = '{"test": "data"}'
      request_body = StringIO.new(body_content)
      headers = { 'Content-Type' => 'application/json' }
      params = { 'param1' => 'value1' }

      request = instance_double('Rack::Request')
      allow(request).to receive(:body).and_return(request_body)
      allow(request).to receive(:path).and_return('/test/webhook')
      allow(request).to receive(:request_method).and_return('POST')
      allow(request).to receive(:params).and_return(params)
      allow(web_server).to receive(:extract_headers).and_return(headers)

      context = web_server.send(:build_request_context, request)

      expect(context).to include(
        path: '/test/webhook',
        method: 'POST',
        headers: headers,
        params: params,
        body: body_content
      )
    end
  end

  describe 'integration with webhook authentication' do
    let(:authenticator) { LanguageOperator::Agent::WebhookAuthenticator }

    context 'HMAC signature verification' do
      it 'can verify signatures after body is read by build_request_context' do
        # Setup HMAC signature verification scenario
        body_content = '{"event": "test"}'
        secret = 'webhook_secret'

        # Calculate expected signature
        expected_signature = OpenSSL::HMAC.hexdigest('sha256', secret, body_content)

        # Create request with HMAC signature header
        request_body = StringIO.new(body_content)
        headers = { 'X-Hub-Signature-256' => "sha256=#{expected_signature}" }

        request = instance_double('Rack::Request')
        allow(request).to receive(:body).and_return(request_body)
        allow(request).to receive(:path).and_return('/webhook')
        allow(request).to receive(:request_method).and_return('POST')
        allow(request).to receive(:params).and_return({})
        allow(web_server).to receive(:extract_headers).and_return(headers)

        # Build request context (this would previously consume the body)
        context = web_server.send(:build_request_context, request)

        # Create authentication config
        auth_config = {
          header: 'X-Hub-Signature-256',
          secret: secret,
          algorithm: :sha256,
          prefix: 'sha256='
        }

        # Verify that signature authentication works
        # (this would fail without the rewind fix)
        result = authenticator.send(:verify_signature, auth_config, context)
        expect(result).to be true
      end

      it 'fails signature verification with wrong secret' do
        body_content = '{"event": "test"}'
        correct_secret = 'correct_secret'
        wrong_secret = 'wrong_secret'

        # Calculate signature with wrong secret
        wrong_signature = OpenSSL::HMAC.hexdigest('sha256', wrong_secret, body_content)

        request_body = StringIO.new(body_content)
        headers = { 'X-Hub-Signature-256' => "sha256=#{wrong_signature}" }

        request = instance_double('Rack::Request')
        allow(request).to receive(:body).and_return(request_body)
        allow(request).to receive(:path).and_return('/webhook')
        allow(request).to receive(:request_method).and_return('POST')
        allow(request).to receive(:params).and_return({})
        allow(web_server).to receive(:extract_headers).and_return(headers)

        context = web_server.send(:build_request_context, request)

        auth_config = {
          header: 'X-Hub-Signature-256',
          secret: correct_secret, # Different secret
          algorithm: :sha256,
          prefix: 'sha256='
        }

        result = authenticator.send(:verify_signature, auth_config, context)
        expect(result).to be false
      end
    end

    context 'multiple middleware body access' do
      it 'allows multiple components to read the body' do
        body_content = '{"middleware": "test"}'
        request_body = StringIO.new(body_content)

        request = instance_double('Rack::Request')
        allow(request).to receive(:body).and_return(request_body)
        allow(request).to receive(:path).and_return('/webhook')
        allow(request).to receive(:request_method).and_return('POST')
        allow(request).to receive(:params).and_return({})
        allow(web_server).to receive(:extract_headers).and_return({})

        # Simulate multiple middleware components reading the body

        # First middleware (e.g., logging)
        context1 = web_server.send(:build_request_context, request)
        expect(context1[:body]).to eq(body_content)

        # Second middleware (e.g., authentication)
        context2 = web_server.send(:build_request_context, request)
        expect(context2[:body]).to eq(body_content)

        # Third middleware (e.g., validation)
        context3 = web_server.send(:build_request_context, request)
        expect(context3[:body]).to eq(body_content)

        # All should have access to the same body content
        expect([context1[:body], context2[:body], context3[:body]]).to all(eq(body_content))
      end
    end
  end
end
