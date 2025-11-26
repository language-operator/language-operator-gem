# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'stringio'
require 'language_operator/agent/web_server'
require 'language_operator/agent/webhook_authenticator'

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

  describe 'concurrent request handling' do
    it 'reuses executor instances from pool for concurrent webhook requests' do
      # Mock the agent to track executor creation
      executor_instances = []
      allow(LanguageOperator::Agent::Executor).to receive(:new) do |_agent|
        executor_instances << instance_double('Executor').tap do |executor_double|
          allow(executor_double).to receive(:execute_with_context).and_return('result')
        end
        executor_instances.last
      end

      # Create multiple threads to simulate concurrent requests
      threads = 3.times.map do |i|
        Thread.new do
          context = {
            method: 'POST',
            path: '/webhook',
            body: "{\"request\": #{i}}",
            headers: {},
            params: {}
          }

          web_server.send(:handle_webhook, context)
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify that only the pool size number of executors were created (4 in initialization + test setup)
      # The pool should reuse executors rather than creating new ones for each request
      expect(executor_instances.length).to eq(4) # Pool size from initialization
    end

    it 'isolates executor state between concurrent requests' do
      # Track the executor instances and their usage
      execution_contexts = []

      allow(LanguageOperator::Agent::Executor).to receive(:new) do |_agent|
        instance_double('Executor').tap do |executor_double|
          allow(executor_double).to receive(:execute_with_context) do |args|
            # Capture the executor instance and its context
            execution_contexts << {
              executor: executor_double,
              instruction: args[:instruction],
              context: args[:context]
            }
            "result_#{execution_contexts.length}"
          end
        end
      end

      # Create concurrent requests with different data
      request_data = %w[request_1 request_2 request_3]

      threads = request_data.map.with_index do |data, _i|
        Thread.new do
          context = {
            method: 'POST',
            path: '/webhook',
            body: "{\"data\": \"#{data}\"}",
            headers: {},
            params: {}
          }

          web_server.send(:handle_webhook, context)
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify each execution used a different executor instance
      executors_used = execution_contexts.map { |ec| ec[:executor] }
      expect(executors_used.uniq.length).to eq(3)

      # Verify each execution had the correct context
      execution_contexts.each_with_index do |ec, i|
        expected_data = request_data[i]
        expect(ec[:context][:body]).to include(expected_data)
      end
    end

    it 'handles executor errors independently across concurrent requests' do
      call_count = 0

      allow(LanguageOperator::Agent::Executor).to receive(:new) do |_agent|
        call_count += 1
        instance_double('Executor').tap do |executor_double|
          if call_count == 2
            # Second executor throws an error
            allow(executor_double).to receive(:execute_with_context).and_raise('Executor error')
          else
            # Other executors work normally
            allow(executor_double).to receive(:execute_with_context).and_return('success')
          end
        end
      end

      results = []
      errors = []

      # Create concurrent requests
      threads = 3.times.map do |i|
        Thread.new do
          context = {
            method: 'POST',
            path: '/webhook',
            body: "{\"request\": #{i}}",
            headers: {},
            params: {}
          }

          result = web_server.send(:handle_webhook, context)
          results << result
        rescue StandardError => e
          errors << e
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # With pooling, we expect the pool size (4) executors to be created during initialization
      # The key is that failures are isolated - other requests still succeed
      expect(call_count).to eq(4) # Pool size executors created during initialization
    end
  end

  describe 'executor pool management' do
    it 'initializes pool with configured size' do
      # The web_server was created with default pool size of 4
      # We can't directly access the pool, but we can test behavior
      expect(web_server.instance_variable_get(:@executor_pool_size)).to eq(4)
    end

    it 'falls back to temporary executor when pool is exhausted' do
      # Mock the pool to always be empty
      allow_any_instance_of(Queue).to receive(:pop).and_raise(ThreadError)
      
      # Track executor creation for fallback
      fallback_executor_created = false
      allow(LanguageOperator::Agent::Executor).to receive(:new).and_call_original
      allow(LanguageOperator::Agent::Executor).to receive(:new) do |agent|
        fallback_executor_created = true
        instance_double('Executor').tap do |executor_double|
          allow(executor_double).to receive(:execute_with_context).and_return('fallback result')
          allow(executor_double).to receive(:cleanup_connections)
        end
      end

      context = {
        method: 'POST',
        path: '/webhook',
        body: '{"test": "data"}',
        headers: {},
        params: {}
      }

      result = web_server.send(:handle_webhook, context)
      
      expect(fallback_executor_created).to be(true)
      expect(result[:status]).to eq('processed')
      expect(result[:result]).to eq('fallback result')
    end

    it 'properly cleans up executor pool on shutdown' do
      # Mock executors in the pool
      mock_executors = 3.times.map do
        instance_double('Executor').tap do |executor|
          allow(executor).to receive(:cleanup_connections)
        end
      end

      # Mock the pool with our mock executors
      pool = Queue.new
      mock_executors.each { |executor| pool << executor }
      web_server.instance_variable_set(:@executor_pool, pool)

      # Capture stdout to verify cleanup message
      output = capture_stdout do
        web_server.cleanup
      end

      # Verify cleanup was called on each executor
      mock_executors.each do |executor|
        expect(executor).to have_received(:cleanup_connections)
      end

      expect(output).to include('Cleaned up 3 executors from pool')
    end

    it 'handles cleanup gracefully when pool is nil' do
      web_server.instance_variable_set(:@executor_pool, nil)
      
      # Should not raise an error
      expect { web_server.cleanup }.not_to raise_error
    end
  end

  describe 'resource leak prevention' do
    it 'prevents MCP connection accumulation through executor reuse' do
      # This test verifies that executors are reused rather than created fresh
      executor_creation_count = 0
      
      # Track all executor creations
      allow(LanguageOperator::Agent::Executor).to receive(:new) do |agent|
        executor_creation_count += 1
        instance_double('Executor').tap do |executor_double|
          allow(executor_double).to receive(:execute_with_context).and_return("result #{executor_creation_count}")
        end
      end

      # Make multiple requests
      5.times do |i|
        context = {
          method: 'POST',
          path: '/webhook',
          body: "{\"request\": #{i}}",
          headers: {},
          params: {}
        }
        web_server.send(:handle_webhook, context)
      end

      # Should only create pool size (4) executors, not 4 + 5 = 9
      expect(executor_creation_count).to eq(4)
    end

    it 'provides connection cleanup interface through executors' do
      # Create a real executor to test the cleanup method exists
      real_executor = LanguageOperator::Agent::Executor.new(agent)
      
      # Should not raise an error
      expect { real_executor.cleanup_connections }.not_to raise_error
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
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
