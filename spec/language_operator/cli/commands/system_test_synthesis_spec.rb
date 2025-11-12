# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/commands/system'

RSpec.describe LanguageOperator::CLI::Commands::System do
  describe '#test_synthesis' do
    let(:command) { described_class.new }

    describe 'temporal intent detection' do
      it 'detects scheduled intent from "daily" keyword' do
        intent = command.send(:detect_temporal_intent, 'Send daily reports to Slack')
        expect(intent).to eq('scheduled')
      end

      it 'detects scheduled intent from "every hour" phrase' do
        intent = command.send(:detect_temporal_intent, 'Run every hour to check status')
        expect(intent).to eq('scheduled')
      end

      it 'detects autonomous intent from "monitor" keyword' do
        intent = command.send(:detect_temporal_intent, 'Monitor GitHub issues continuously')
        expect(intent).to eq('autonomous')
      end

      it 'defaults to autonomous for generic instructions' do
        intent = command.send(:detect_temporal_intent, 'Process webhooks from GitHub')
        expect(intent).to eq('autonomous')
      end
    end

    describe 'tools list formatting' do
      it 'formats single tool' do
        result = command.send(:format_tools_list, 'github')
        expect(result).to eq('- github')
      end

      it 'formats multiple tools' do
        result = command.send(:format_tools_list, 'github,slack,jira')
        expect(result).to eq("- github\n- slack\n- jira")
      end

      it 'handles nil tools' do
        result = command.send(:format_tools_list, nil)
        expect(result).to eq('No tools specified')
      end

      it 'handles empty string' do
        result = command.send(:format_tools_list, '')
        expect(result).to eq('No tools specified')
      end
    end

    describe 'models list formatting' do
      it 'formats single model' do
        result = command.send(:format_models_list, 'gpt-4')
        expect(result).to eq('- gpt-4')
      end

      it 'formats multiple models' do
        result = command.send(:format_models_list, 'gpt-4,claude-3-5-sonnet')
        expect(result).to eq("- gpt-4\n- claude-3-5-sonnet")
      end

      context 'when ANTHROPIC_API_KEY is set' do
        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
          allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return(nil)
        end

        it 'detects Claude model' do
          result = command.send(:format_models_list, nil)
          expect(result).to include('claude-3-5-sonnet')
        end
      end

      context 'when OPENAI_API_KEY is set' do
        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)
          allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-key')
        end

        it 'detects GPT model' do
          result = command.send(:format_models_list, nil)
          expect(result).to include('gpt-4-turbo')
        end
      end
    end

    describe 'Ruby code extraction' do
      it 'extracts code from ruby code block' do
        response = "Here's the code:\n```ruby\ncode here\n```\nDone!"
        result = command.send(:extract_ruby_code, response)
        expect(result).to eq('code here')
      end

      it 'extracts code from generic code block' do
        response = "```\ncode here\n```"
        result = command.send(:extract_ruby_code, response)
        expect(result).to eq('code here')
      end

      it 'handles multiline code' do
        response = "```ruby\nline 1\nline 2\nline 3\n```"
        result = command.send(:extract_ruby_code, response)
        expect(result).to eq("line 1\nline 2\nline 3")
      end

      it 'returns nil when no code blocks found' do
        response = 'Just plain text'
        result = command.send(:extract_ruby_code, response)
        expect(result).to be_nil
      end
    end

    describe 'Go template rendering' do
      it 'renders simple variable substitution' do
        template = 'Hello {{.Name}}'
        data = { 'Name' => 'World' }
        result = command.send(:render_go_template, template, data)
        expect(result).to eq('Hello World')
      end

      it 'renders multiple variables' do
        template = '{{.First}} {{.Second}}'
        data = { 'First' => 'Hello', 'Second' => 'World' }
        result = command.send(:render_go_template, template, data)
        expect(result).to eq('Hello World')
      end

      it 'removes ErrorContext conditional blocks' do
        template = '{{if .ErrorContext}}Error section{{else}}Normal section{{end}}'
        data = {}
        result = command.send(:render_go_template, template, data)
        expect(result).to eq('Normal section')
      end
    end
  end
end
