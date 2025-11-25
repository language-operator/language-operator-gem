# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/helpers/ux_helper'

RSpec.describe LanguageOperator::CLI::Helpers::UxHelper do
  let(:test_class) do
    Class.new do
      include LanguageOperator::CLI::Helpers::UxHelper
    end
  end
  let(:helper_instance) { test_class.new }

  describe '#format_cluster_details' do
    before do
      # Mock the highlighted_box method to capture its arguments
      allow(helper_instance).to receive(:highlighted_box)
    end

    context 'with domain provided' do
      it 'includes domain in the display rows' do
        expect(helper_instance).to receive(:highlighted_box) do |args|
          expect(args[:title]).to eq('LanguageCluster')
          expect(args[:rows]['Domain']).to eq('agents.example.com')
          expect(args[:rows]['Name']).to be_a(String)
          expect(args[:rows]['Namespace']).to eq('test-ns')
        end

        helper_instance.send(:format_cluster_details,
                             name: 'test-cluster',
                             namespace: 'test-ns',
                             context: 'test-context',
                             domain: 'agents.example.com',
                             status: 'Ready',
                             created: '2025-11-25T12:00:00Z')
      end
    end

    context 'without domain' do
      it 'excludes domain from display rows using compact' do
        expect(helper_instance).to receive(:highlighted_box) do |args|
          expect(args[:rows]).not_to have_key('Domain')
          expect(args[:rows]['Name']).to be_a(String)
          expect(args[:rows]['Namespace']).to eq('test-ns')
        end

        helper_instance.send(:format_cluster_details,
                             name: 'test-cluster',
                             namespace: 'test-ns',
                             context: 'test-context',
                             status: 'Ready',
                             created: '2025-11-25T12:00:00Z')
      end
    end

    context 'with empty domain' do
      it 'excludes empty domain from display rows using compact' do
        expect(helper_instance).to receive(:highlighted_box) do |args|
          expect(args[:rows]).not_to have_key('Domain')
        end

        helper_instance.send(:format_cluster_details,
                             name: 'test-cluster',
                             namespace: 'test-ns',
                             context: 'test-context',
                             domain: '',
                             status: 'Ready')
      end
    end

    it 'maintains proper row ordering with domain in correct position' do
      expect(helper_instance).to receive(:highlighted_box) do |args|
        row_keys = args[:rows].keys
        context_index = row_keys.index('Context')
        domain_index = row_keys.index('Domain')

        # Domain should appear between Context and Status
        expect(domain_index).to be > context_index
        expect(domain_index).to be < row_keys.length - 2 # Before Status and Created
      end

      helper_instance.send(:format_cluster_details,
                           name: 'test',
                           namespace: 'ns',
                           context: 'ctx',
                           domain: 'example.com',
                           status: 'Ready',
                           created: '2025-11-25T12:00:00Z')
    end
  end
end
