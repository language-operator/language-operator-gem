# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/kubernetes/client'

RSpec.describe LanguageOperator::Kubernetes::Client do
  let(:kubeconfig_path) { '/tmp/test_kubeconfig' }
  let(:context) { 'test-context' }

  # Mock K8s client initialization to avoid real K8s dependencies
  let(:k8s_client) { double('K8s::Client') }
  let(:k8s_config) { double('K8s::Config') }
  before do
    allow(K8s::Client).to receive(:in_cluster_config).and_return(k8s_client)
    allow(K8s::Client).to receive(:config).and_return(k8s_client)
    allow(K8s::Config).to receive(:load_file).and_return(k8s_config)
    allow(k8s_config).to receive(:to_h).and_return({})
    allow(K8s::Config).to receive(:new).and_return(k8s_config)
  end

  describe '#current_namespace' do
    context 'when in cluster mode' do
      let(:client) { described_class.new(in_cluster: true) }
      let(:namespace_file_path) { '/var/run/secrets/kubernetes.io/serviceaccount/namespace' }

      context 'when namespace file exists and is readable' do
        before do
          allow(File).to receive(:read).with(namespace_file_path).and_return("  kube-system  \n")
        end

        it 'returns the namespace from the service account file, stripped of whitespace' do
          expect(client.current_namespace).to eq('kube-system')
        end
      end

      context 'when namespace file does not exist' do
        before do
          allow(File).to receive(:read).with(namespace_file_path).and_raise(Errno::ENOENT)
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end

      context 'when namespace file has permission denied' do
        before do
          allow(File).to receive(:read).with(namespace_file_path).and_raise(Errno::EACCES)
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end

      context 'when namespace file path is a directory' do
        before do
          allow(File).to receive(:read).with(namespace_file_path).and_raise(Errno::EISDIR)
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end

      context 'when namespace file path component is not a directory' do
        before do
          allow(File).to receive(:read).with(namespace_file_path).and_raise(Errno::ENOTDIR)
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end

      context 'when there is an I/O error reading the file' do
        before do
          allow(File).to receive(:read).with(namespace_file_path).and_raise(IOError, 'Device error')
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end

      context 'when there is a generic system call error' do
        before do
          allow(File).to receive(:read).with(namespace_file_path).and_raise(Errno::EIO, 'I/O error')
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end
    end

    context 'when not in cluster mode' do
      let(:client) { described_class.new(kubeconfig: kubeconfig_path, context: context) }
      let(:context_obj) { instance_double('ContextObject') }

      before do
        allow(k8s_config).to receive(:context).with(context).and_return(context_obj)
        allow(client).to receive(:current_context).and_return(context)
      end

      context 'when context has a namespace' do
        before do
          allow(context_obj).to receive(:namespace).and_return('production')
        end

        it 'returns the namespace from the context' do
          expect(client.current_namespace).to eq('production')
        end
      end

      context 'when context has no namespace' do
        before do
          allow(context_obj).to receive(:namespace).and_return(nil)
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end

      context 'when context does not exist' do
        before do
          allow(k8s_config).to receive(:context).with(context).and_return(nil)
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end

      context 'when kubeconfig loading fails' do
        before do
          allow(K8s::Config).to receive(:load_file).with(kubeconfig_path).and_raise(SystemCallError, 'Config error')
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end

      context 'when current_context method fails' do
        before do
          allow(client).to receive(:current_context).and_raise(IOError, 'Context error')
        end

        it 'returns nil' do
          expect(client.current_namespace).to be_nil
        end
      end
    end
  end
end
