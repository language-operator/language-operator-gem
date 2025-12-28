# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/kubernetes/resource_builder'

RSpec.describe LanguageOperator::Kubernetes::ResourceBuilder do
  describe '.language_cluster' do
    context 'basic cluster creation' do
      it 'creates cluster resource without domain' do
        resource = described_class.language_cluster('test-cluster', namespace: 'test-ns')

        expect(resource).to include(
          'apiVersion' => 'langop.io/v1alpha1',
          'kind' => 'LanguageCluster'
        )
        expect(resource.dig('metadata', 'name')).to eq('test-cluster')
        expect(resource.dig('metadata', 'namespace')).to eq('test-ns')
        expect(resource.dig('spec', 'domain')).to be_nil
        expect(resource.dig('spec', 'namespace')).to eq('test-ns')
      end

      it 'defaults namespace to cluster name when not provided' do
        resource = described_class.language_cluster('test-cluster')

        expect(resource.dig('spec', 'namespace')).to eq('test-cluster')
        expect(resource.dig('metadata', 'namespace')).to eq('default')
      end
    end

    context 'with domain option' do
      it 'includes domain in spec when provided' do
        resource = described_class.language_cluster(
          'test-cluster',
          namespace: 'test-ns',
          domain: 'example.com'
        )

        expect(resource.dig('spec', 'domain')).to eq('example.com')
        expect(resource.dig('spec', 'namespace')).to eq('test-ns')
        expect(resource.dig('spec', 'resourceQuota')).to be_a(Hash)
        expect(resource.dig('spec', 'networkPolicy')).to be_a(Hash)
      end

      it 'omits domain from spec when nil' do
        resource = described_class.language_cluster(
          'test-cluster',
          namespace: 'test-ns',
          domain: nil
        )

        expect(resource.dig('spec', 'domain')).to be_nil
        expect(resource['spec'].keys).not_to include('domain')
      end

      it 'omits domain from spec when empty string' do
        resource = described_class.language_cluster(
          'test-cluster',
          namespace: 'test-ns',
          domain: ''
        )

        expect(resource.dig('spec', 'domain')).to be_nil
        expect(resource['spec'].keys).not_to include('domain')
      end
    end

    context 'with labels' do
      it 'includes custom labels in metadata' do
        labels = { 'app' => 'test', 'env' => 'staging' }
        resource = described_class.language_cluster(
          'test-cluster',
          namespace: 'test-ns',
          domain: 'example.com',
          labels: labels
        )

        expect(resource.dig('metadata', 'labels')).to include(labels)
      end
    end

    context 'resource structure validation' do
      let(:resource) do
        described_class.language_cluster(
          'full-test',
          namespace: 'test-namespace',
          domain: 'webhooks.example.com'
        )
      end

      it 'has correct apiVersion and kind' do
        expect(resource['apiVersion']).to eq('langop.io/v1alpha1')
        expect(resource['kind']).to eq('LanguageCluster')
      end

      it 'has properly structured metadata' do
        metadata = resource['metadata']
        expect(metadata['name']).to eq('full-test')
        expect(metadata['namespace']).to eq('test-namespace')
        expect(metadata).to have_key('labels')
      end

      it 'has complete spec with all required fields' do
        spec = resource['spec']
        expect(spec['domain']).to eq('webhooks.example.com')
        expect(spec['namespace']).to eq('test-namespace')
        expect(spec['resourceQuota']).to be_a(Hash)
        expect(spec['networkPolicy']).to be_a(Hash)
      end
    end
  end

  describe '.language_agent' do
    it 'creates agent resource without clusterRef when not provided' do
      resource = described_class.language_agent(
        'test-agent',
        instructions: 'Test instructions'
      )

      expect(resource).to include(
        'apiVersion' => 'langop.io/v1alpha1',
        'kind' => 'LanguageAgent'
      )
      expect(resource.dig('metadata', 'name')).to eq('test-agent')
      expect(resource.dig('spec', 'instructions')).to eq('Test instructions')
      expect(resource.dig('spec', 'clusterRef')).to be_nil
    end

    it 'includes clusterRef in spec when provided' do
      resource = described_class.language_agent(
        'test-agent',
        instructions: 'Test instructions',
        cluster_ref: 'test-cluster'
      )

      expect(resource.dig('spec', 'clusterRef')).to eq('test-cluster')
      expect(resource.dig('spec', 'instructions')).to eq('Test instructions')
    end
  end

  describe '.language_model' do
    it 'creates model resource without clusterRef when not provided' do
      resource = described_class.language_model(
        'test-model',
        provider: 'openai',
        model: 'gpt-4'
      )

      expect(resource).to include(
        'apiVersion' => 'langop.io/v1alpha1',
        'kind' => 'LanguageModel'
      )
      expect(resource.dig('metadata', 'name')).to eq('test-model')
      expect(resource.dig('spec', 'provider')).to eq('openai')
      expect(resource.dig('spec', 'modelName')).to eq('gpt-4')
      expect(resource.dig('spec', 'clusterRef')).to be_nil
    end

    it 'includes clusterRef in spec when provided' do
      resource = described_class.language_model(
        'test-model',
        provider: 'openai',
        model: 'gpt-4',
        cluster_ref: 'test-cluster'
      )

      expect(resource.dig('spec', 'clusterRef')).to eq('test-cluster')
      expect(resource.dig('spec', 'provider')).to eq('openai')
      expect(resource.dig('spec', 'modelName')).to eq('gpt-4')
    end
  end

  describe '.language_tool' do
    it 'creates tool resource without clusterRef when not provided' do
      resource = described_class.language_tool(
        'test-tool',
        type: 'mcp',
        config: { 'key' => 'value' }
      )

      expect(resource).to include(
        'apiVersion' => 'langop.io/v1alpha1',
        'kind' => 'LanguageTool'
      )
      expect(resource.dig('metadata', 'name')).to eq('test-tool')
      expect(resource.dig('spec', 'type')).to eq('mcp')
      expect(resource.dig('spec', 'config')).to eq({ 'key' => 'value' })
      expect(resource.dig('spec', 'clusterRef')).to be_nil
    end

    it 'includes clusterRef in spec when provided' do
      resource = described_class.language_tool(
        'test-tool',
        type: 'mcp',
        config: { 'key' => 'value' },
        cluster_ref: 'test-cluster'
      )

      expect(resource.dig('spec', 'clusterRef')).to eq('test-cluster')
      expect(resource.dig('spec', 'type')).to eq('mcp')
      expect(resource.dig('spec', 'config')).to eq({ 'key' => 'value' })
    end
  end

  describe '.language_persona' do
    it 'creates persona resource without clusterRef when not provided' do
      resource = described_class.language_persona(
        'test-persona',
        description: 'A test persona',
        tone: 'friendly',
        system_prompt: 'You are a helpful assistant',
        cluster: 'test-cluster'
      )

      expect(resource).to include(
        'apiVersion' => 'langop.io/v1alpha1',
        'kind' => 'LanguagePersona'
      )
      expect(resource.dig('metadata', 'name')).to eq('test-persona')
      expect(resource.dig('metadata', 'namespace')).to eq('test-cluster')
      expect(resource.dig('spec', 'description')).to eq('A test persona')
      expect(resource.dig('spec', 'tone')).to eq('friendly')
      expect(resource.dig('spec', 'systemPrompt')).to eq('You are a helpful assistant')
      expect(resource.dig('spec', 'displayName')).to eq('Test Persona')
      expect(resource.dig('spec', 'clusterRef')).to be_nil
    end

    it 'includes clusterRef in spec when provided' do
      resource = described_class.language_persona(
        'test-persona',
        description: 'A test persona',
        tone: 'friendly',
        system_prompt: 'You are a helpful assistant',
        cluster: 'test-cluster',
        cluster_ref: 'test-cluster-ref'
      )

      expect(resource.dig('spec', 'clusterRef')).to eq('test-cluster-ref')
      expect(resource.dig('spec', 'description')).to eq('A test persona')
      expect(resource.dig('spec', 'tone')).to eq('friendly')
      expect(resource.dig('spec', 'systemPrompt')).to eq('You are a helpful assistant')
    end
  end

  describe '.build_persona' do
    it 'creates persona resource without clusterRef when not provided' do
      spec = {
        'displayName' => 'Test Persona',
        'description' => 'A test persona',
        'tone' => 'friendly',
        'systemPrompt' => 'You are a helpful assistant'
      }
      
      resource = described_class.build_persona(
        name: 'test-persona',
        spec: spec,
        namespace: 'test-cluster'
      )

      expect(resource).to include(
        'apiVersion' => 'langop.io/v1alpha1',
        'kind' => 'LanguagePersona'
      )
      expect(resource.dig('metadata', 'name')).to eq('test-persona')
      expect(resource.dig('metadata', 'namespace')).to eq('test-cluster')
      expect(resource.dig('spec', 'clusterRef')).to be_nil
    end

    it 'includes clusterRef in spec when provided' do
      spec = {
        'displayName' => 'Test Persona',
        'description' => 'A test persona',
        'tone' => 'friendly',
        'systemPrompt' => 'You are a helpful assistant'
      }
      
      resource = described_class.build_persona(
        name: 'test-persona',
        spec: spec,
        namespace: 'test-cluster',
        cluster_ref: 'test-cluster-ref'
      )

      expect(resource.dig('spec', 'clusterRef')).to eq('test-cluster-ref')
      expect(resource.dig('spec', 'description')).to eq('A test persona')
    end
  end
end
