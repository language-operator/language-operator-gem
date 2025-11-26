# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/language_operator/cli/helpers/label_utils'

RSpec.describe LanguageOperator::CLI::Helpers::LabelUtils do
  describe '.normalize_agent_name' do
    it 'converts to lowercase' do
      expect(described_class.normalize_agent_name('MyAgent')).to eq('myagent')
    end

    it 'preserves hyphens' do
      expect(described_class.normalize_agent_name('my-agent')).to eq('my-agent')
    end

    it 'preserves underscores (for normalization only)' do
      expect(described_class.normalize_agent_name('my_agent')).to eq('my_agent')
    end

    it 'preserves dots' do
      expect(described_class.normalize_agent_name('my.agent')).to eq('my.agent')
    end

    it 'handles numeric characters' do
      expect(described_class.normalize_agent_name('agent-v2')).to eq('agent-v2')
    end

    it 'handles nil input' do
      expect(described_class.normalize_agent_name(nil)).to eq('')
    end

    it 'handles empty string' do
      expect(described_class.normalize_agent_name('')).to eq('')
    end
  end

  describe '.agent_pod_selector' do
    it 'creates proper label selector' do
      result = described_class.agent_pod_selector('my-agent')
      expect(result).to eq('app.kubernetes.io/name=my-agent')
    end

    it 'normalizes agent name in selector' do
      result = described_class.agent_pod_selector('MyAgent')
      expect(result).to eq('app.kubernetes.io/name=myagent')
    end

    it 'handles special characters' do
      result = described_class.agent_pod_selector('data-processor-v2')
      expect(result).to eq('app.kubernetes.io/name=data-processor-v2')
    end

    it 'handles underscores (normalized)' do
      result = described_class.agent_pod_selector('email_handler')
      expect(result).to eq('app.kubernetes.io/name=email_handler')
    end
  end

  describe '.valid_label_value?' do
    context 'valid cases' do
      it 'accepts simple lowercase names' do
        expect(described_class.valid_label_value?('agent')).to be true
      end

      it 'accepts names with hyphens' do
        expect(described_class.valid_label_value?('my-agent')).to be true
      end

      it 'accepts names with dots' do
        expect(described_class.valid_label_value?('my.agent')).to be true
      end

      it 'accepts names with numbers' do
        expect(described_class.valid_label_value?('agent1')).to be true
        expect(described_class.valid_label_value?('1agent')).to be true
        expect(described_class.valid_label_value?('agent-v2')).to be true
      end

      it 'accepts mixed alphanumeric with separators' do
        expect(described_class.valid_label_value?('data-processor-v2')).to be true
        expect(described_class.valid_label_value?('api.service.v1')).to be true
      end

      it 'accepts single character names' do
        expect(described_class.valid_label_value?('a')).to be true
        expect(described_class.valid_label_value?('1')).to be true
      end

      it 'accepts maximum length (63 chars)' do
        long_name = 'a' * 63
        expect(described_class.valid_label_value?(long_name)).to be true
      end
    end

    context 'invalid cases' do
      it 'rejects nil' do
        expect(described_class.valid_label_value?(nil)).to be false
      end

      it 'rejects empty string' do
        expect(described_class.valid_label_value?('')).to be false
      end

      it 'rejects names longer than 63 characters' do
        long_name = 'a' * 64
        expect(described_class.valid_label_value?(long_name)).to be false
      end

      it 'rejects names starting with hyphen' do
        expect(described_class.valid_label_value?('-agent')).to be false
      end

      it 'rejects names ending with hyphen' do
        expect(described_class.valid_label_value?('agent-')).to be false
      end

      it 'rejects names starting with dot' do
        expect(described_class.valid_label_value?('.agent')).to be false
      end

      it 'rejects names ending with dot' do
        expect(described_class.valid_label_value?('agent.')).to be false
      end

      it 'rejects uppercase letters' do
        expect(described_class.valid_label_value?('MyAgent')).to be false
      end

      it 'rejects special characters' do
        expect(described_class.valid_label_value?('my_agent')).to be false # underscore not allowed
        expect(described_class.valid_label_value?('my@agent')).to be false
        expect(described_class.valid_label_value?('my agent')).to be false # space
        expect(described_class.valid_label_value?('my/agent')).to be false
      end

      it 'rejects only hyphens/dots' do
        expect(described_class.valid_label_value?('-')).to be false
        expect(described_class.valid_label_value?('.')).to be false
        expect(described_class.valid_label_value?('--')).to be false
      end
    end
  end

  describe '.debug_pod_search' do
    let(:mock_ctx) do
      double('ClusterContext').tap do |ctx|
        allow(ctx).to receive(:namespace).and_return('test-namespace')
      end
    end

    it 'returns comprehensive debug information' do
      result = described_class.debug_pod_search(mock_ctx, 'MyAgent-v2')
      
      expect(result).to match({
        agent_name: 'MyAgent-v2',
        normalized_name: 'myagent-v2',
        label_selector: 'app.kubernetes.io/name=myagent-v2',
        namespace: 'test-namespace',
        valid_label_value: false  # uppercase letters make it invalid
      })
    end

    it 'shows valid status for proper names' do
      result = described_class.debug_pod_search(mock_ctx, 'data-processor')
      
      expect(result[:valid_label_value]).to be true
      expect(result[:normalized_name]).to eq('data-processor')
    end

    it 'shows invalid status for problematic names' do
      result = described_class.debug_pod_search(mock_ctx, '-invalid-')
      
      expect(result[:valid_label_value]).to be false
      expect(result[:normalized_name]).to eq('-invalid-')
    end
  end

  describe 'edge cases and real-world scenarios' do
    it 'handles common agent naming patterns' do
      patterns = [
        'github-webhook',
        'slack-bot',
        'data-processor-v2',
        'api-gateway',
        'notification-service',
        'backup-manager',
        'log-analyzer',
        'health-check'
      ]

      patterns.each do |pattern|
        expect(described_class.valid_label_value?(pattern)).to be(true), 
          "Expected '#{pattern}' to be valid but was invalid"
        
        selector = described_class.agent_pod_selector(pattern)
        expect(selector).to eq("app.kubernetes.io/name=#{pattern}")
      end
    end

    it 'handles problematic user inputs gracefully' do
      problematic_inputs = [
        'My-Agent',  # uppercase
        'agent_with_underscores',  # underscores (common mistake)
        'agent with spaces',  # spaces
        'agent@company.com',  # email-like
        '.hidden-agent',  # starts with dot
        'agent-',  # ends with hyphen
        '',  # empty
        nil  # nil
      ]

      problematic_inputs.each do |input|
        expect { described_class.normalize_agent_name(input) }.not_to raise_error
        expect { described_class.agent_pod_selector(input) }.not_to raise_error
        expect { described_class.valid_label_value?(input) }.not_to raise_error
      end
    end

    it 'produces consistent results for same input' do
      agent_name = 'data-processor-v2'
      
      # Call multiple times to ensure consistency
      results = 5.times.map { described_class.agent_pod_selector(agent_name) }
      expect(results.uniq.length).to eq(1)
      
      validations = 5.times.map { described_class.valid_label_value?(agent_name) }
      expect(validations.uniq).to eq([true])
    end
  end
end