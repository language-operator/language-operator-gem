# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'language_operator/agent'
require 'language_operator/agent/web_server'
require 'language_operator/dsl/mcp_server_definition'

RSpec.describe LanguageOperator::Agent::WebServer, 'MCP support' do
  include Rack::Test::Methods

  let(:agent_config) do
    {
      'agent' => {
        'name' => 'test-mcp-agent',
        'instructions' => 'Process requests'
      },
      'llm' => {
        'provider' => 'anthropic',
        'model' => 'claude-3-5-sonnet-20241022',
        'api_key' => 'test-key'
      },
      'mcp' => { 'servers' => {} }
    }
  end

  let(:agent) { LanguageOperator::Agent::Base.new(agent_config) }
  let(:web_server) { described_class.new(agent, port: 8080) }
  let(:app) { web_server.send(:rack_app) }

  describe '#register_mcp_tools' do
    let(:mcp_server_def) do
      mcp_def = LanguageOperator::Dsl::McpServerDefinition.new('test-agent')
      mcp_def.tool('greet') do
        description 'Greet a user'
        parameter :name do
          type :string
          required true
          description 'The name to greet'
        end
        execute do |params|
          "Hello, #{params['name']}!"
        end
      end
      mcp_def
    end

    it 'registers MCP tools' do
      expect { web_server.register_mcp_tools(mcp_server_def) }.not_to raise_error
    end

    it 'creates MCP route' do
      web_server.register_mcp_tools(mcp_server_def)
      expect(web_server.route_exists?('/mcp', :post)).to be true
    end

    it 'outputs tool count' do
      expect { web_server.register_mcp_tools(mcp_server_def) }.to output(/Registered 1 MCP tools/).to_stdout
    end
  end

  describe 'MCP endpoint' do
    before do
      mcp_def = LanguageOperator::Dsl::McpServerDefinition.new('test-agent')
      mcp_def.tool('add') do
        description 'Add two numbers'
        parameter :a do
          type :number
          required true
          description 'First number'
        end
        parameter :b do
          type :number
          required true
          description 'Second number'
        end
        execute do |params|
          params['a'] + params['b']
        end
      end
      web_server.register_mcp_tools(mcp_def)
    end

    it 'responds to POST /mcp' do
      # MCP tools/list request
      post '/mcp', {
        jsonrpc: '2.0',
        method: 'tools/list',
        id: 1
      }.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to be < 500
    end

    it 'handles MCP protocol requests' do
      # The exact response format depends on the MCP gem implementation
      # This test verifies the endpoint exists and handles requests
      post '/mcp', {
        jsonrpc: '2.0',
        method: 'tools/list',
        id: 1
      }.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(last_response).not_to be_nil
      expect(last_response.body).not_to be_empty
    end
  end

  describe 'agent with multiple tools' do
    it 'registers multiple MCP tools' do
      mcp_def = LanguageOperator::Dsl::McpServerDefinition.new('multi-tool-agent')

      mcp_def.tool('tool1') do
        description 'First tool'
        execute { |_params| 'result1' }
      end

      mcp_def.tool('tool2') do
        description 'Second tool'
        execute { |_params| 'result2' }
      end

      mcp_def.tool('tool3') do
        description 'Third tool'
        execute { |_params| 'result3' }
      end

      expect { web_server.register_mcp_tools(mcp_def) }.to output(/Registered 3 MCP tools/).to_stdout
    end
  end
end
