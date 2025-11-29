# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/formatters/table_formatter'
require 'language_operator/cli/formatters/progress_formatter'

RSpec.describe LanguageOperator::CLI::Formatters::TableFormatter do
  describe '.clusters' do
    let(:sample_clusters) do
      [
        {
          name: 'prod-cluster *',
          namespace: 'production',
          status: 'Ready',
          agents: 3,
          tools: 2,
          models: 1,
          domain: 'agents.example.com'
        },
        {
          name: 'test-cluster',
          namespace: 'testing',
          status: 'Ready',
          agents: 1,
          tools: 1,
          models: 1,
          domain: nil
        },
        {
          name: 'error-cluster',
          namespace: 'error-ns',
          status: 'Error',
          agents: '?',
          tools: '?',
          models: '?',
          domain: '?'
        }
      ]
    end

    before do
      # Mock table output to capture what would be displayed
      allow(described_class).to receive(:table) do |headers, rows|
        @captured_headers = headers
        @captured_rows = rows
        'mocked table output'
      end
      allow($stdout).to receive(:puts)
    end

    context 'domain column display' do
      it 'includes domain header' do
        described_class.clusters(sample_clusters)

        expect(@captured_headers).to include('DOMAIN')
        expect(@captured_headers).to eq(['', 'NAME', 'NAMESPACE', 'STATUS', 'DOMAIN'])
      end

      it 'displays domain values correctly' do
        described_class.clusters(sample_clusters)

        # Check first row has domain
        expect(@captured_rows[0][4]).to eq('agents.example.com')

        # Check second row has empty domain (nil becomes empty string)
        expect(@captured_rows[1][4]).to eq('')

        # Check error row shows error indicator
        expect(@captured_rows[2][4]).to eq('?')
      end

      it 'handles current cluster formatting with domain' do
        described_class.clusters(sample_clusters)

        # First row should be current cluster (formatted with yellow/bold)
        first_row = @captured_rows[0]
        expect(first_row[1]).to be_a(String) # formatted name
        expect(first_row[4]).to eq('agents.example.com') # domain preserved
      end
    end

    context 'with empty clusters list' do
      it 'shows no clusters found message' do
        expect(LanguageOperator::CLI::Formatters::ProgressFormatter)
          .to receive(:info).with('No clusters found')

        described_class.clusters([])
      end
    end

    context 'edge cases' do
      it 'handles empty string domain' do
        clusters_with_empty_domain = [{
          name: 'empty-domain',
          namespace: 'test',
          status: 'Ready',
          domain: ''
        }]

        described_class.clusters(clusters_with_empty_domain)
        expect(@captured_rows[0][4]).to eq('')
      end

      it 'handles dash indicator domain' do
        clusters_with_dash = [{
          name: 'not-found',
          namespace: 'test',
          status: 'Not Found',
          domain: '-'
        }]

        described_class.clusters(clusters_with_dash)
        expect(@captured_rows[0][4]).to eq('-')
      end
    end
  end
end
