# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'language_operator/agent'
require 'language_operator/agent/web_server'
require 'language_operator/dsl/chat_endpoint_definition'

RSpec.describe LanguageOperator::Agent::WebServer, 'chat endpoint support' do
  include Rack::Test::Methods

  let(:agent_config) do
    {
      'agent' => {
        'name' => 'test-chat-agent',
        'instructions' => 'Answer questions'
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

  let(:chat_endpoint_def) do
    chat_def = LanguageOperator::Dsl::ChatEndpointDefinition.new('test-chat-agent')
    chat_def.instance_eval do
      system_prompt "You are a helpful assistant"
      model "test-model-v1"
      temperature 0.7
      max_tokens 2000
    end
    chat_def
  end

  describe '#register_chat_endpoint' do
    it 'registers chat endpoint' do
      expect { web_server.register_chat_endpoint(chat_endpoint_def, agent) }.not_to raise_error
    end

    it 'creates /v1/chat/completions route' do
      web_server.register_chat_endpoint(chat_endpoint_def, agent)
      expect(web_server.route_exists?('/v1/chat/completions', :post)).to be true
    end

    it 'creates /v1/models route' do
      web_server.register_chat_endpoint(chat_endpoint_def, agent)
      expect(web_server.route_exists?('/v1/models', :get)).to be true
    end

    it 'outputs registration message' do
      expect do
        web_server.register_chat_endpoint(chat_endpoint_def, agent)
      end.to output(/Registered chat completion endpoint/).to_stdout
    end

    it 'stores chat endpoint definition' do
      web_server.register_chat_endpoint(chat_endpoint_def, agent)
      expect(web_server.instance_variable_get(:@chat_endpoint)).to eq(chat_endpoint_def)
    end

    it 'stores chat agent' do
      web_server.register_chat_endpoint(chat_endpoint_def, agent)
      expect(web_server.instance_variable_get(:@chat_agent)).to eq(agent)
    end
  end

  describe 'GET /v1/models' do
    before do
      web_server.register_chat_endpoint(chat_endpoint_def, agent)
    end

    it 'responds to GET /v1/models' do
      get '/v1/models'
      expect(last_response.status).to eq(200)
    end

    it 'returns JSON response' do
      get '/v1/models'
      expect(last_response.content_type).to include('application/json')
    end

    it 'returns OpenAI-compatible format' do
      get '/v1/models'
      data = JSON.parse(last_response.body)

      expect(data['object']).to eq('list')
      expect(data['data']).to be_an(Array)
      expect(data['data'].size).to eq(1)
    end

    it 'includes model information' do
      get '/v1/models'
      data = JSON.parse(last_response.body)
      model = data['data'].first

      expect(model['id']).to eq('test-model-v1')
      expect(model['object']).to eq('model')
      expect(model['owned_by']).to eq('language-operator')
      expect(model['created']).to be_a(Integer)
    end
  end

  describe 'POST /v1/chat/completions' do
    before do
      web_server.register_chat_endpoint(chat_endpoint_def, agent)

      # Mock agent.execute to return a predictable response
      allow(agent).to receive(:execute).and_return("This is a test response")
    end

    describe 'non-streaming mode' do
      it 'responds to POST /v1/chat/completions' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }]
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(200)
      end

      it 'returns JSON response' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }]
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.content_type).to include('application/json')
      end

      it 'returns OpenAI-compatible format' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }]
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        data = JSON.parse(last_response.body)

        expect(data['id']).to start_with('chatcmpl-')
        expect(data['object']).to eq('chat.completion')
        expect(data['created']).to be_a(Integer)
        expect(data['model']).to eq('test-model-v1')
        expect(data['choices']).to be_an(Array)
        expect(data['usage']).to be_a(Hash)
      end

      it 'includes message in choices' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }]
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        data = JSON.parse(last_response.body)
        choice = data['choices'].first

        expect(choice['index']).to eq(0)
        expect(choice['message']['role']).to eq('assistant')
        expect(choice['message']['content']).to eq("This is a test response")
        expect(choice['finish_reason']).to eq('stop')
      end

      it 'includes usage statistics' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }]
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        data = JSON.parse(last_response.body)
        usage = data['usage']

        expect(usage['prompt_tokens']).to be_a(Integer)
        expect(usage['completion_tokens']).to be_a(Integer)
        expect(usage['total_tokens']).to be_a(Integer)
        expect(usage['total_tokens']).to eq(usage['prompt_tokens'] + usage['completion_tokens'])
      end

      it 'handles system messages' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [
            { role: 'system', content: 'You are helpful' },
            { role: 'user', content: 'Hello' }
          ]
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(200)
        expect(agent).to have_received(:execute).with(/You are helpful.*Hello/m)
      end

      it 'handles conversation history' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [
            { role: 'user', content: 'First message' },
            { role: 'assistant', content: 'First response' },
            { role: 'user', content: 'Second message' }
          ]
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(200)
        expect(agent).to have_received(:execute)
      end

      it 'prepends system prompt if configured' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [
            { role: 'user', content: 'Hello' }
          ]
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(agent).to have_received(:execute).with(/You are a helpful assistant.*Hello/m)
      end

      it 'handles empty messages array' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: []
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(200)
      end
    end

    describe 'streaming mode' do
      # Helper to consume streaming body
      def consume_streaming_body(body)
        return body.to_s unless body.respond_to?(:call)

        buffer = StringIO.new
        stream = StreamCollector.new(buffer)
        body.call(stream)
        buffer.string
      end

      # Mock stream collector for tests
      class StreamCollector
        def initialize(buffer)
          @buffer = buffer
        end

        def write(data)
          @buffer.write(data)
        end

        def close
          # No-op for testing
        end
      end

      it 'returns SSE response for stream=true' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }],
          stream: true
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to include('text/event-stream')
      end

      it 'returns streaming body' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }],
          stream: true
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        # Consume the streaming body
        body_content = consume_streaming_body(last_response.body)

        expect(body_content).to include('data:')
        expect(body_content).to include('[DONE]')
      end

      it 'includes chat completion chunks' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }],
          stream: true
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        # Consume the streaming body
        body_content = consume_streaming_body(last_response.body)

        # Extract JSON chunks (lines starting with "data: " and not "[DONE]")
        chunks = body_content.split("\n\n").select { |line| line.start_with?('data:') && !line.include?('[DONE]') }

        expect(chunks).not_to be_empty

        # Parse first chunk
        first_chunk_json = chunks.first.sub('data: ', '')
        first_chunk = JSON.parse(first_chunk_json)

        expect(first_chunk['object']).to eq('chat.completion.chunk')
        expect(first_chunk['model']).to eq('test-model-v1')
        expect(first_chunk['choices']).to be_an(Array)
      end

      it 'includes finish_reason in final chunk' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }],
          stream: true
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        # Consume the streaming body
        body_content = consume_streaming_body(last_response.body)
        chunks = body_content.split("\n\n").select { |line| line.start_with?('data:') && !line.include?('[DONE]') }

        # Parse last chunk before [DONE]
        last_chunk_json = chunks.last.sub('data: ', '')
        last_chunk = JSON.parse(last_chunk_json)

        expect(last_chunk['choices'].first['finish_reason']).to eq('stop')
      end

      it 'ends with [DONE] marker' do
        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }],
          stream: true
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        # Consume the streaming body
        body_content = consume_streaming_body(last_response.body)

        expect(body_content).to end_with("data: [DONE]\n\n")
      end
    end

    describe 'error handling' do
      it 'handles missing messages parameter' do
        post '/v1/chat/completions', {
          model: 'test-model-v1'
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(200)
      end

      it 'handles invalid JSON' do
        post '/v1/chat/completions', 'invalid json', 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(500)
        data = JSON.parse(last_response.body)
        expect(data['error']).to include('Error')
        expect(data['message']).to include('Invalid JSON')
      end

      it 'handles agent execution errors gracefully' do
        allow(agent).to receive(:execute).and_raise(StandardError, "Execution failed")

        post '/v1/chat/completions', {
          model: 'test-model-v1',
          messages: [{ role: 'user', content: 'Hello' }]
        }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(500)
        data = JSON.parse(last_response.body)
        expect(data['error']).to eq('StandardError')
        expect(data['message']).to eq('Execution failed')
      end
    end
  end

  describe 'message format conversion' do
    before do
      web_server.register_chat_endpoint(chat_endpoint_def, agent)
      allow(agent).to receive(:execute).and_return("Response")
    end

    it 'converts user messages correctly' do
      post '/v1/chat/completions', {
        model: 'test-model-v1',
        messages: [{ role: 'user', content: 'Hello' }]
      }.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(agent).to have_received(:execute) do |prompt|
        expect(prompt).to include('User: Hello')
      end
    end

    it 'converts assistant messages correctly' do
      post '/v1/chat/completions', {
        model: 'test-model-v1',
        messages: [
          { role: 'user', content: 'Hello' },
          { role: 'assistant', content: 'Hi there' },
          { role: 'user', content: 'How are you?' }
        ]
      }.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(agent).to have_received(:execute) do |prompt|
        expect(prompt).to include('User: Hello')
        expect(prompt).to include('Assistant: Hi there')
        expect(prompt).to include('User: How are you?')
      end
    end

    it 'handles multi-turn conversations' do
      post '/v1/chat/completions', {
        model: 'test-model-v1',
        messages: [
          { role: 'user', content: 'First' },
          { role: 'assistant', content: 'Response 1' },
          { role: 'user', content: 'Second' },
          { role: 'assistant', content: 'Response 2' },
          { role: 'user', content: 'Third' }
        ]
      }.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      expect(agent).to have_received(:execute)
    end
  end

  describe 'token estimation' do
    before do
      web_server.register_chat_endpoint(chat_endpoint_def, agent)
      allow(agent).to receive(:execute).and_return("This is a test response")
    end

    it 'estimates tokens for prompt and completion' do
      post '/v1/chat/completions', {
        model: 'test-model-v1',
        messages: [{ role: 'user', content: 'Hello' }]
      }.to_json, 'CONTENT_TYPE' => 'application/json'

      data = JSON.parse(last_response.body)
      usage = data['usage']

      expect(usage['prompt_tokens']).to be > 0
      expect(usage['completion_tokens']).to be > 0
    end

    it 'calculates total tokens correctly' do
      post '/v1/chat/completions', {
        model: 'test-model-v1',
        messages: [{ role: 'user', content: 'Hello' }]
      }.to_json, 'CONTENT_TYPE' => 'application/json'

      data = JSON.parse(last_response.body)
      usage = data['usage']

      expect(usage['total_tokens']).to eq(usage['prompt_tokens'] + usage['completion_tokens'])
    end
  end
end
