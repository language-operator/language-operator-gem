# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/kubernetes/client'

RSpec.describe LanguageOperator::Kubernetes::Client do
  let(:client) { described_class.new(in_cluster: false) }
  let(:mock_k8s_client) { instance_double(K8s::Client) }
  let(:mock_resource_client) { instance_double(K8s::ResourceClient) }

  before do
    allow(K8s::Config).to receive(:load_file).and_return(double(current_context: 'test'))
    allow(K8s::Client).to receive(:config).and_return(mock_k8s_client)
    allow(client).to receive(:build_client).and_return(mock_k8s_client)
    
    # Mock the API client structure for events
    api_client = instance_double(K8s::APIClient)
    allow(mock_k8s_client).to receive(:api).with('v1').and_return(api_client)
    allow(api_client).to receive(:resource).with('events').and_return(mock_resource_client)
    allow(api_client).to receive(:resource).with('events', namespace: anything).and_return(mock_resource_client)
    
    allow(mock_resource_client).to receive(:create_resource).and_return(instance_double(K8s::Resource))
  end

  after do
    # Clean up environment variables
    ENV.delete('KUBERNETES_SERVICE_HOST')
    ENV.delete('DISABLE_K8S_EVENTS')
    ENV.delete('AGENT_NAME')
    ENV.delete('AGENT_NAMESPACE')
  end

  describe '#create_event' do
    let(:event_hash) do
      {
        'metadata' => { 'name' => 'test-event' },
        'message' => 'Test event'
      }
    end

    it 'creates a Kubernetes event with proper apiVersion and kind' do
      mock_k8s_resource = instance_double(K8s::Resource)
      expect(K8s::Resource).to receive(:new) do |resource|
        expect(resource['apiVersion']).to eq('v1')
        expect(resource['kind']).to eq('Event')
        mock_k8s_resource
      end
      expect(mock_resource_client).to receive(:create_resource).with(mock_k8s_resource)

      client.create_event(event_hash)
    end
  end

  describe '#emit_execution_event' do
    context 'when in Kubernetes environment' do
      before do
        ENV['KUBERNETES_SERVICE_HOST'] = 'kubernetes.default.svc'
        ENV['AGENT_NAME'] = 'test-agent'
        ENV['AGENT_NAMESPACE'] = 'test-namespace'
        allow(client).to receive(:current_namespace).and_return('test-namespace')
      end

      it 'emits a successful task execution event' do
        expect(client).to receive(:create_event) do |event|
          expect(event['metadata']['name']).to match(/test-agent-task-fetch_data-\d+/)
          expect(event['metadata']['namespace']).to eq('test-namespace')
          expect(event['metadata']['labels']['langop.io/agent-name']).to eq('test-agent')
          expect(event['metadata']['labels']['langop.io/task-name']).to eq('fetch_data')
          expect(event['involvedObject']['kind']).to eq('LanguageAgent')
          expect(event['involvedObject']['name']).to eq('test-agent')
          expect(event['reason']).to eq('TaskCompleted')
          expect(event['type']).to eq('Normal')
          expect(event['message']).to include('Task \'fetch_data\' completed successfully')
        end

        client.emit_execution_event('fetch_data', success: true, duration_ms: 150.5)
      end

      it 'emits a failed task execution event' do
        expect(client).to receive(:create_event) do |event|
          expect(event['reason']).to eq('TaskFailed')
          expect(event['type']).to eq('Warning')
          expect(event['message']).to include('Task \'fetch_data\' failed')
        end

        client.emit_execution_event('fetch_data', success: false, duration_ms: 75.2)
      end

      it 'includes metadata in the event message' do
        metadata = { 'retry_count' => 2, 'error_type' => 'NetworkError' }
        
        expect(client).to receive(:create_event) do |event|
          expect(event['message']).to include('retry_count: 2, error_type: NetworkError')
        end

        client.emit_execution_event('fetch_data', success: false, duration_ms: 75.2, metadata: metadata)
      end

      it 'includes proper labels for filtering and identification' do
        expect(client).to receive(:create_event) do |event|
          labels = event['metadata']['labels']
          expect(labels['app.kubernetes.io/name']).to eq('language-operator')
          expect(labels['app.kubernetes.io/component']).to eq('agent')
          expect(labels['langop.io/agent-name']).to eq('test-agent')
          expect(labels['langop.io/task-name']).to eq('fetch_data')
        end

        client.emit_execution_event('fetch_data', success: true, duration_ms: 150.5)
      end
    end

    context 'when not in Kubernetes environment' do
      before do
        ENV.delete('KUBERNETES_SERVICE_HOST')
      end

      it 'returns nil without creating event' do
        expect(client).not_to receive(:create_event)
        result = client.emit_execution_event('fetch_data', success: true, duration_ms: 150.5)
        expect(result).to be_nil
      end
    end

    context 'when events are disabled' do
      before do
        ENV['KUBERNETES_SERVICE_HOST'] = 'kubernetes.default.svc'
        ENV['DISABLE_K8S_EVENTS'] = 'true'
        ENV['AGENT_NAME'] = 'test-agent'
        ENV['AGENT_NAMESPACE'] = 'test-namespace'
      end

      it 'returns nil without creating event' do
        expect(client).not_to receive(:create_event)
        result = client.emit_execution_event('fetch_data', success: true, duration_ms: 150.5)
        expect(result).to be_nil
      end
    end

    context 'when required environment variables are missing' do
      before do
        ENV['KUBERNETES_SERVICE_HOST'] = 'kubernetes.default.svc'
        ENV.delete('AGENT_NAME')
        ENV.delete('AGENT_NAMESPACE')
        allow(client).to receive(:current_namespace).and_return(nil)
      end

      it 'returns nil without creating event when AGENT_NAME is missing' do
        expect(client).not_to receive(:create_event)
        result = client.emit_execution_event('fetch_data', success: true, duration_ms: 150.5)
        expect(result).to be_nil
      end
    end

    context 'when event creation fails' do
      before do
        ENV['KUBERNETES_SERVICE_HOST'] = 'kubernetes.default.svc'
        ENV['AGENT_NAME'] = 'test-agent'
        ENV['AGENT_NAMESPACE'] = 'test-namespace'
        allow(client).to receive(:current_namespace).and_return('test-namespace')
        allow(client).to receive(:create_event).and_raise(StandardError.new('K8s API error'))
      end

      it 'handles errors gracefully and returns nil' do
        expect { client.emit_execution_event('fetch_data', success: true, duration_ms: 150.5) }
          .not_to raise_error
      end

      it 'warns about the error' do
        expect(client).to receive(:warn).with(/Failed to emit execution event/)
        client.emit_execution_event('fetch_data', success: true, duration_ms: 150.5)
      end
    end
  end

  describe '#build_event_message' do
    it 'builds a success message without metadata' do
      message = client.send(:build_event_message, 'fetch_data', true, 150.5)
      expect(message).to eq("Task 'fetch_data' completed successfully in 150.5ms")
    end

    it 'builds a failure message without metadata' do
      message = client.send(:build_event_message, 'fetch_data', false, 75.2)
      expect(message).to eq("Task 'fetch_data' failed in 75.2ms")
    end

    it 'includes metadata in the message' do
      metadata = { 'retry_count' => 2, 'error_type' => 'NetworkError' }
      message = client.send(:build_event_message, 'fetch_data', false, 75.2, metadata)
      expect(message).to eq("Task 'fetch_data' failed in 75.2ms (retry_count: 2, error_type: NetworkError)")
    end

    it 'handles empty metadata' do
      message = client.send(:build_event_message, 'fetch_data', true, 150.5, {})
      expect(message).to eq("Task 'fetch_data' completed successfully in 150.5ms")
    end
  end
end