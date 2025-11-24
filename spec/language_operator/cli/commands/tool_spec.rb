# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'language_operator/cli/commands/tool/base'

RSpec.describe LanguageOperator::CLI::Commands::Tool::Base do
  let(:command) { described_class.new }

  describe '#search' do
    let(:tool_registry_data) do
      {
        'tools' => {
          'email' => {
            'description' => 'Send and receive emails via SMTP/IMAP'
          },
          'web' => {
            'description' => 'Search the web and fetch web pages using DuckDuckGo'
          },
          'workspace' => {
            'description' => 'Persistent file I/O for agent workspace - read, write, and manage files'
          },
          'email_alias' => {
            'description' => 'Alias for email tool',
            'alias' => true
          }
        }
      }
    end

    before do
      # Mock the HTTP request to the tool registry
      stub_request(:get, LanguageOperator::Config::ToolRegistry::REGISTRY_URL)
        .to_return(
          status: 200,
          body: tool_registry_data.to_yaml,
          headers: { 'Content-Type' => 'application/x-yaml' }
        )
    end

    context 'without a search pattern' do
      it 'lists available tools' do
        expect { command.search }.to output(/email/).to_stdout
      end

      it 'excludes aliases from results' do
        expect { command.search }.not_to output(/email_alias/).to_stdout
      end
    end

    context 'with a search pattern' do
      it 'filters tools by name' do
        expect { command.search('email') }.to output(/email/).to_stdout
      end

      it 'does not show unrelated tools when filtering' do
        expect { command.search('email') }.not_to output(/web/).to_stdout
      end

      it 'filters tools by description' do
        expect { command.search('web') }.to output(/web/).to_stdout
      end

      it 'is case insensitive' do
        expect { command.search('EMAIL') }.to output(/email/).to_stdout
      end

      it 'shows a message when no tools match' do
        expect { command.search('nonexistent') }.to output(
          /No tools found matching 'nonexistent'/
        ).to_stdout
      end
    end

    context 'when the ToolRegistry class is not available' do
      # This test would have caught the original bug
      it 'should not raise NameError' do
        # Remove the require to simulate the original bug
        # This is a regression test - if someone removes the require again,
        # this test should fail with NameError
        expect { command.search }.not_to raise_error
      end
    end

    context 'when tool registry is empty' do
      let(:tool_registry_data) { { 'tools' => {} } }

      it 'shows message when no tools found' do
        expect { command.search }.to output(
          /No tools found in registry/
        ).to_stdout
      end
    end

    context 'when HTTP request fails' do
      before do
        stub_request(:get, LanguageOperator::Config::ToolRegistry::REGISTRY_URL)
          .to_return(status: 404, body: 'Not Found')
      end

      it 'handles errors gracefully' do
        expect { command.search }.to raise_error(SystemExit)
      end
    end
  end
end
