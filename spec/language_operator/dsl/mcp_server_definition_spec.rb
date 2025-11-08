# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/mcp_server_definition'

RSpec.describe LanguageOperator::Dsl::McpServerDefinition do
  let(:mcp_def) { described_class.new('test-agent') }

  describe '#initialize' do
    it 'sets agent name' do
      expect(mcp_def.instance_variable_get(:@agent_name)).to eq('test-agent')
    end

    it 'sets default server name' do
      expect(mcp_def.server_name).to eq('test-agent-mcp')
    end

    it 'initializes empty tools hash' do
      expect(mcp_def.tools).to be_empty
    end
  end

  describe '#name' do
    it 'returns current server name when called without arguments' do
      expect(mcp_def.name).to eq('test-agent-mcp')
    end

    it 'sets custom server name' do
      mcp_def.name('custom-server')
      expect(mcp_def.server_name).to eq('custom-server')
    end
  end

  describe '#tool' do
    it 'creates a tool definition' do
      tool = mcp_def.tool('test_tool') do
        description 'Test tool'
      end

      expect(tool).to be_a(LanguageOperator::Dsl::ToolDefinition)
      expect(tool.name).to eq('test_tool')
    end

    it 'adds tool to tools hash' do
      mcp_def.tool('tool1') { description 'Tool 1' }
      mcp_def.tool('tool2') { description 'Tool 2' }

      expect(mcp_def.tools.keys).to contain_exactly('tool1', 'tool2')
    end

    it 'configures tool with block' do
      tool = mcp_def.tool('greet') do
        description 'Greet a user'

        parameter :name do
          type :string
          required true
        end

        execute do |params|
          "Hello, #{params['name']}!"
        end
      end

      expect(tool.description).to eq('Greet a user')
      expect(tool.parameters.keys).to include('name')
      expect(tool.call('name' => 'Alice')).to eq('Hello, Alice!')
    end
  end

  describe '#all_tools' do
    it 'returns array of tool definitions' do
      mcp_def.tool('tool1') { description 'Tool 1' }
      mcp_def.tool('tool2') { description 'Tool 2' }

      tools = mcp_def.all_tools
      expect(tools).to be_an(Array)
      expect(tools.length).to eq(2)
      expect(tools.map(&:name)).to contain_exactly('tool1', 'tool2')
    end

    it 'returns empty array when no tools defined' do
      expect(mcp_def.all_tools).to eq([])
    end
  end

  describe '#tools?' do
    it 'returns false when no tools defined' do
      expect(mcp_def.tools?).to be false
    end

    it 'returns true when tools are defined' do
      mcp_def.tool('test') { description 'Test' }
      expect(mcp_def.tools?).to be true
    end
  end
end
