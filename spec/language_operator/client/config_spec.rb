# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'language_operator/client/config'

RSpec.describe LanguageOperator::Client::Config do
  describe '.load' do
    context 'when loading a YAML file without mcp_servers key' do
      let(:yaml_content) do
        <<~YAML
          llm:
            provider: openai
            model: gpt-4
            api_key: test-key
        YAML
      end

      it 'adds an empty mcp_servers array' do
        Tempfile.create(['config', '.yml']) do |file|
          file.write(yaml_content)
          file.rewind

          config = described_class.load(file.path)
          expect(config).to have_key('mcp_servers')
          expect(config['mcp_servers']).to eq([])
        end
      end
    end

    context 'when loading a YAML file with mcp_servers key' do
      let(:yaml_content) do
        <<~YAML
          llm:
            provider: openai
            model: gpt-4
          mcp_servers:
            - name: test-server
              url: http://example.com
              enabled: true
        YAML
      end

      it 'preserves the existing mcp_servers' do
        Tempfile.create(['config', '.yml']) do |file|
          file.write(yaml_content)
          file.rewind

          config = described_class.load(file.path)
          expect(config['mcp_servers']).to be_an(Array)
          expect(config['mcp_servers'].length).to eq(1)
          expect(config['mcp_servers'][0]['name']).to eq('test-server')
        end
      end
    end

    context 'when loading a YAML file with empty mcp_servers' do
      let(:yaml_content) do
        <<~YAML
          llm:
            provider: openai
            model: gpt-4
          mcp_servers: []
        YAML
      end

      it 'keeps the empty array' do
        Tempfile.create(['config', '.yml']) do |file|
          file.write(yaml_content)
          file.rewind

          config = described_class.load(file.path)
          expect(config['mcp_servers']).to eq([])
        end
      end
    end
  end

  describe '.from_env' do
    it 'always includes mcp_servers key' do
      # Set minimal required env vars
      ENV['OPENAI_API_KEY'] = 'test-key'

      config = described_class.from_env
      expect(config).to have_key('mcp_servers')
      expect(config['mcp_servers']).to be_an(Array)

      ENV.delete('OPENAI_API_KEY')
    end

    context 'when MCP_SERVERS env var is set' do
      it 'parses comma-separated URLs' do
        ENV['OPENAI_API_KEY'] = 'test-key'
        ENV['MCP_SERVERS'] = 'http://server1.com,http://server2.com'

        config = described_class.from_env
        expect(config['mcp_servers'].length).to eq(2)
        expect(config['mcp_servers'][0]['url']).to eq('http://server1.com')
        expect(config['mcp_servers'][1]['url']).to eq('http://server2.com')

        ENV.delete('OPENAI_API_KEY')
        ENV.delete('MCP_SERVERS')
      end
    end

    context 'when MCP_URL env var is set' do
      it 'creates a single server entry' do
        ENV['OPENAI_API_KEY'] = 'test-key'
        ENV['MCP_URL'] = 'http://legacy.com'

        config = described_class.from_env
        expect(config['mcp_servers'].length).to eq(1)
        expect(config['mcp_servers'][0]['url']).to eq('http://legacy.com')
        expect(config['mcp_servers'][0]['name']).to eq('default-tools')

        ENV.delete('OPENAI_API_KEY')
        ENV.delete('MCP_URL')
      end
    end

    context 'when no MCP env vars are set' do
      it 'returns empty mcp_servers array' do
        ENV['OPENAI_API_KEY'] = 'test-key'

        config = described_class.from_env
        expect(config['mcp_servers']).to eq([])

        ENV.delete('OPENAI_API_KEY')
      end
    end
  end

  describe '.load_with_fallback' do
    context 'when file exists and is valid' do
      let(:yaml_content) do
        <<~YAML
          llm:
            provider: openai
            model: gpt-4
        YAML
      end

      it 'loads from file and ensures mcp_servers exists' do
        Tempfile.create(['config', '.yml']) do |file|
          file.write(yaml_content)
          file.rewind

          config = described_class.load_with_fallback(file.path)
          expect(config['llm']['model']).to eq('gpt-4')
          expect(config['mcp_servers']).to eq([])
        end
      end
    end

    context 'when file does not exist' do
      it 'falls back to environment variables' do
        ENV['OPENAI_API_KEY'] = 'test-key'

        config = described_class.load_with_fallback('/nonexistent/path.yml')
        expect(config['llm']['provider']).to eq('openai')
        expect(config['mcp_servers']).to be_an(Array)

        ENV.delete('OPENAI_API_KEY')
      end
    end

    context 'when file contains invalid YAML' do
      it 'falls back to environment variables and warns user' do
        Tempfile.create(['config', '.yml']) do |file|
          file.write('invalid: yaml: content:')
          file.rewind

          ENV['OPENAI_API_KEY'] = 'test-key'

          expect do
            config = described_class.load_with_fallback(file.path)
            expect(config['llm']['provider']).to eq('openai')
            expect(config['mcp_servers']).to be_an(Array)
          end.to output(/Error loading config/).to_stderr

          ENV.delete('OPENAI_API_KEY')
        end
      end
    end
  end
end
