# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/tool_definition'
require 'language_operator/dsl/parameter_definition'

RSpec.describe LanguageOperator::Dsl::ToolDefinition, 'optional parameters' do
  describe 'tool with optional parameters' do
    let(:tool) do
      tool_def = described_class.new('email_tool')
      tool_def.description 'Send email'

      # Required parameter
      tool_def.parameter :to do |param|
        param.type :string
        param.required true
        param.description 'Recipient email'
      end

      # Optional parameter with required false
      tool_def.parameter :cc do |param|
        param.type :string
        param.required false
        param.description 'CC email'
      end

      # Optional parameter with default (implicitly optional)
      tool_def.parameter :subject do |param|
        param.type :string
        param.default 'No Subject'
        param.description 'Email subject'
      end

      tool_def.execute do |params|
        result = "To: #{params['to']}"
        result += ", CC: #{params['cc']}" if params['cc']
        result += ", Subject: #{params['subject']}"
        result
      end

      tool_def
    end

    it 'validates parameters correctly' do
      # Required parameter check
      params = tool.parameters
      expect(params['to'].required?).to be true
      expect(params['cc'].required?).to be false
      expect(params['subject'].required?).to be false
    end

    it 'generates correct schema with required array' do
      schema = tool.to_schema

      expect(schema['inputSchema']['required']).to eq(['to'])
      expect(schema['inputSchema']['required']).not_to include('cc')
      expect(schema['inputSchema']['required']).not_to include('subject')
    end

    it 'allows calling with only required parameters' do
      result = tool.call({ 'to' => 'alice@example.com' })
      expect(result).to include('To: alice@example.com')
      expect(result).to include('Subject: No Subject')
    end

    it 'allows calling with optional parameters' do
      result = tool.call({
                           'to' => 'alice@example.com',
                           'cc' => 'bob@example.com',
                           'subject' => 'Hello'
                         })

      expect(result).to include('To: alice@example.com')
      expect(result).to include('CC: bob@example.com')
      expect(result).to include('Subject: Hello')
    end

    it 'raises error when required parameter is missing' do
      expect do
        tool.call({ 'cc' => 'bob@example.com' })
      end.to raise_error(ArgumentError, /Missing required parameter: to/)
    end

    it 'does not raise error when optional parameter is missing' do
      expect do
        tool.call({ 'to' => 'alice@example.com' })
      end.not_to raise_error
    end

    it 'applies default values for missing optional parameters' do
      result = tool.call({ 'to' => 'alice@example.com' })
      expect(result).to include('Subject: No Subject')
    end

    # This test specifically verifies the bug fix:
    # Reading required? multiple times should not change the value
    it 'required? getter does not mutate state' do
      param = tool.parameters['cc']

      # Set to false explicitly
      param.required false

      # Read multiple times - should stay false
      expect(param.required?).to be false
      expect(param.required?).to be false
      expect(param.required?).to be false
      expect(param.required?).to be false

      # Verify in schema generation (which also reads required?)
      schema = tool.to_schema
      expect(schema['inputSchema']['required']).not_to include('cc')

      # Read again - still false
      expect(param.required?).to be false
    end
  end

  describe 'schema generation with mixed required parameters' do
    it 'correctly identifies required vs optional parameters' do
      tool_def = described_class.new('test_tool')

      tool_def.parameter :required1 do |param|
        param.required true
      end

      tool_def.parameter :optional1 do |param|
        param.required false
      end

      tool_def.parameter :required2 do |param|
        param.required true
      end

      tool_def.parameter :optional2 do |param|
        # Not setting required - should default to false
      end

      schema = tool_def.to_schema
      required_params = schema['inputSchema']['required']

      expect(required_params).to contain_exactly('required1', 'required2')
      expect(required_params).not_to include('optional1', 'optional2')
    end
  end
end
