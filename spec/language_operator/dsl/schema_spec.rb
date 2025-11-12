# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Dsl::Schema do
  describe '.version' do
    it 'returns the gem version' do
      expect(described_class.version).to eq(LanguageOperator::VERSION)
    end

    it 'returns a string' do
      expect(described_class.version).to be_a(String)
    end

    it 'returns a valid semantic version format' do
      expect(described_class.version).to match(/^\d+\.\d+\.\d+/)
    end

    it 'matches version in to_json_schema output' do
      schema = described_class.to_json_schema
      expect(described_class.version).to eq(schema[:version])
    end

    it 'is accessible for version compatibility checks' do
      version = described_class.version
      # Should be parseable by Gem::Version
      expect { Gem::Version.new(version) }.not_to raise_error
    end
  end

  describe '.to_json_schema' do
    let(:schema) { described_class.to_json_schema }

    it 'returns a Hash' do
      expect(schema).to be_a(Hash)
    end

    it 'conforms to JSON Schema draft-07' do
      expect(schema[:$schema]).to eq('http://json-schema.org/draft-07/schema#')
    end

    it 'includes schema metadata' do
      expect(schema[:title]).to eq('Language Operator Agent DSL')
      expect(schema[:description]).to include('autonomous AI agents')
      expect(schema[:$id]).to include('agent-dsl.json')
    end

    it 'includes gem version' do
      expect(schema[:version]).to eq(LanguageOperator::VERSION)
    end

    it 'has type object' do
      expect(schema[:type]).to eq('object')
    end

    it 'marks name as required' do
      expect(schema[:required]).to include('name')
    end

    describe 'agent properties' do
      let(:properties) { schema[:properties] }

      it 'includes name property' do
        expect(properties[:name]).to be_a(Hash)
        expect(properties[:name][:type]).to eq('string')
        expect(properties[:name][:pattern]).to eq('^[a-z0-9-]+$')
        expect(properties[:name][:minLength]).to eq(1)
        expect(properties[:name][:maxLength]).to eq(63)
      end

      it 'includes description property' do
        expect(properties[:description]).to be_a(Hash)
        expect(properties[:description][:type]).to eq('string')
      end

      it 'includes persona property' do
        expect(properties[:persona]).to be_a(Hash)
        expect(properties[:persona][:type]).to eq('string')
      end

      it 'includes schedule property with cron pattern' do
        expect(properties[:schedule]).to be_a(Hash)
        expect(properties[:schedule][:type]).to eq('string')
        expect(properties[:schedule][:pattern]).to eq('^\s*(\S+\s+){4}\S+\s*$')
      end

      it 'includes mode property with enum' do
        expect(properties[:mode]).to be_a(Hash)
        expect(properties[:mode][:type]).to eq('string')
        expect(properties[:mode][:enum]).to match_array(%w[autonomous scheduled reactive])
      end

      it 'includes objectives property' do
        expect(properties[:objectives]).to be_a(Hash)
        expect(properties[:objectives][:type]).to eq('array')
        expect(properties[:objectives][:items][:type]).to eq('string')
      end

      it 'includes workflow property with reference' do
        expect(properties[:workflow]).to be_a(Hash)
        expect(properties[:workflow][:$ref]).to eq('#/definitions/WorkflowDefinition')
      end

      it 'includes constraints property with reference' do
        expect(properties[:constraints]).to be_a(Hash)
        expect(properties[:constraints][:$ref]).to eq('#/definitions/ConstraintsDefinition')
      end

      it 'includes output property with reference' do
        expect(properties[:output]).to be_a(Hash)
        expect(properties[:output][:$ref]).to eq('#/definitions/OutputDefinition')
      end

      it 'includes webhooks property as array' do
        expect(properties[:webhooks]).to be_a(Hash)
        expect(properties[:webhooks][:type]).to eq('array')
        expect(properties[:webhooks][:items][:$ref]).to eq('#/definitions/WebhookDefinition')
      end

      it 'includes mcp_server property with reference' do
        expect(properties[:mcp_server]).to be_a(Hash)
        expect(properties[:mcp_server][:$ref]).to eq('#/definitions/McpServerDefinition')
      end

      it 'includes chat_endpoint property with reference' do
        expect(properties[:chat_endpoint]).to be_a(Hash)
        expect(properties[:chat_endpoint][:$ref]).to eq('#/definitions/ChatEndpointDefinition')
      end
    end

    describe 'definitions' do
      let(:definitions) { schema[:definitions] }

      it 'includes all expected definitions' do
        expected_definitions = %i[
          WorkflowDefinition
          StepDefinition
          ConstraintsDefinition
          OutputDefinition
          WebhookDefinition
          WebhookAuthentication
          McpServerDefinition
          ChatEndpointDefinition
          ToolDefinition
          ParameterDefinition
        ]

        expected_definitions.each do |def_name|
          expect(definitions).to have_key(def_name), "Missing definition: #{def_name}"
        end
      end

      describe 'WorkflowDefinition' do
        let(:workflow_def) { definitions[:WorkflowDefinition] }

        it 'is an object with steps array' do
          expect(workflow_def[:type]).to eq('object')
          expect(workflow_def[:properties][:steps][:type]).to eq('array')
          expect(workflow_def[:properties][:steps][:items][:$ref]).to eq('#/definitions/StepDefinition')
        end
      end

      describe 'StepDefinition' do
        let(:step_def) { definitions[:StepDefinition] }

        it 'includes required properties' do
          expect(step_def[:type]).to eq('object')
          expect(step_def[:required]).to include('name')
        end

        it 'includes step properties' do
          expect(step_def[:properties][:name]).to be_a(Hash)
          expect(step_def[:properties][:tool]).to be_a(Hash)
          expect(step_def[:properties][:params]).to be_a(Hash)
          expect(step_def[:properties][:depends_on]).to be_a(Hash)
          expect(step_def[:properties][:prompt]).to be_a(Hash)
        end

        it 'allows depends_on as string or array' do
          depends_on = step_def[:properties][:depends_on]
          expect(depends_on[:oneOf]).to be_a(Array)
          expect(depends_on[:oneOf].length).to eq(2)
          expect(depends_on[:oneOf][0][:type]).to eq('string')
          expect(depends_on[:oneOf][1][:type]).to eq('array')
        end
      end

      describe 'ConstraintsDefinition' do
        let(:constraints_def) { definitions[:ConstraintsDefinition] }

        it 'includes constraint properties' do
          expect(constraints_def[:type]).to eq('object')
          expect(constraints_def[:properties][:max_iterations]).to be_a(Hash)
          expect(constraints_def[:properties][:timeout]).to be_a(Hash)
          expect(constraints_def[:properties][:daily_budget]).to be_a(Hash)
          expect(constraints_def[:properties][:hourly_budget]).to be_a(Hash)
          expect(constraints_def[:properties][:token_budget]).to be_a(Hash)
          expect(constraints_def[:properties][:requests_per_minute]).to be_a(Hash)
          expect(constraints_def[:properties][:requests_per_hour]).to be_a(Hash)
          expect(constraints_def[:properties][:requests_per_day]).to be_a(Hash)
        end

        it 'includes timeout pattern for duration format' do
          expect(constraints_def[:properties][:timeout][:pattern]).to eq('^\d+[smh]$')
        end

        it 'includes budget constraints' do
          expect(constraints_def[:properties][:daily_budget][:type]).to eq('number')
          expect(constraints_def[:properties][:daily_budget][:minimum]).to eq(0)
          expect(constraints_def[:properties][:hourly_budget][:type]).to eq('number')
          expect(constraints_def[:properties][:token_budget][:type]).to eq('integer')
        end

        it 'includes rate limiting properties' do
          expect(constraints_def[:properties][:requests_per_minute][:type]).to eq('integer')
          expect(constraints_def[:properties][:requests_per_hour][:type]).to eq('integer')
          expect(constraints_def[:properties][:requests_per_day][:type]).to eq('integer')
        end

        it 'includes content filtering properties' do
          expect(constraints_def[:properties][:blocked_patterns][:type]).to eq('array')
          expect(constraints_def[:properties][:blocked_topics][:type]).to eq('array')
        end
      end

      describe 'OutputDefinition' do
        let(:output_def) { definitions[:OutputDefinition] }

        it 'includes output destinations' do
          expect(output_def[:type]).to eq('object')
          expect(output_def[:properties][:workspace]).to be_a(Hash)
          expect(output_def[:properties][:slack]).to be_a(Hash)
          expect(output_def[:properties][:email]).to be_a(Hash)
        end

        it 'includes slack channel requirement' do
          slack = output_def[:properties][:slack]
          expect(slack[:properties][:channel]).to be_a(Hash)
          expect(slack[:required]).to include('channel')
        end

        it 'includes email configuration' do
          email = output_def[:properties][:email]
          expect(email[:properties][:to]).to be_a(Hash)
          expect(email[:properties][:to][:format]).to eq('email')
          expect(email[:required]).to include('to')
        end
      end

      describe 'WebhookDefinition' do
        let(:webhook_def) { definitions[:WebhookDefinition] }

        it 'includes webhook properties' do
          expect(webhook_def[:type]).to eq('object')
          expect(webhook_def[:properties][:path]).to be_a(Hash)
          expect(webhook_def[:properties][:method]).to be_a(Hash)
          expect(webhook_def[:properties][:authentication]).to be_a(Hash)
        end

        it 'requires path' do
          expect(webhook_def[:required]).to include('path')
        end

        it 'validates path starts with /' do
          expect(webhook_def[:properties][:path][:pattern]).to eq('^/')
        end

        it 'includes HTTP method enum' do
          method = webhook_def[:properties][:method]
          expect(method[:enum]).to match_array(%w[get post put delete patch])
          expect(method[:default]).to eq('post')
        end

        it 'references WebhookAuthentication' do
          expect(webhook_def[:properties][:authentication][:$ref]).to eq('#/definitions/WebhookAuthentication')
        end
      end

      describe 'WebhookAuthentication' do
        let(:auth_def) { definitions[:WebhookAuthentication] }

        it 'includes authentication properties' do
          expect(auth_def[:type]).to eq('object')
          expect(auth_def[:properties][:type]).to be_a(Hash)
          expect(auth_def[:properties][:secret]).to be_a(Hash)
          expect(auth_def[:properties][:header]).to be_a(Hash)
          expect(auth_def[:properties][:algorithm]).to be_a(Hash)
        end

        it 'includes authentication type enum' do
          expect(auth_def[:properties][:type][:enum]).to match_array(%w[hmac api_key bearer custom])
        end

        it 'includes HMAC algorithm enum' do
          expect(auth_def[:properties][:algorithm][:enum]).to match_array(%w[sha1 sha256 sha512])
        end
      end

      describe 'McpServerDefinition' do
        let(:mcp_def) { definitions[:McpServerDefinition] }

        it 'includes MCP server properties' do
          expect(mcp_def[:type]).to eq('object')
          expect(mcp_def[:properties][:name]).to be_a(Hash)
          expect(mcp_def[:properties][:tools]).to be_a(Hash)
        end

        it 'references ToolDefinition for tools' do
          tools = mcp_def[:properties][:tools]
          expect(tools[:type]).to eq('object')
          expect(tools[:additionalProperties][:$ref]).to eq('#/definitions/ToolDefinition')
        end
      end

      describe 'ChatEndpointDefinition' do
        let(:chat_def) { definitions[:ChatEndpointDefinition] }

        it 'includes chat configuration properties' do
          expect(chat_def[:type]).to eq('object')
          expect(chat_def[:properties][:system_prompt]).to be_a(Hash)
          expect(chat_def[:properties][:temperature]).to be_a(Hash)
          expect(chat_def[:properties][:max_tokens]).to be_a(Hash)
          expect(chat_def[:properties][:model_name]).to be_a(Hash)
        end

        it 'includes temperature constraints' do
          temp = chat_def[:properties][:temperature]
          expect(temp[:type]).to eq('number')
          expect(temp[:minimum]).to eq(0.0)
          expect(temp[:maximum]).to eq(2.0)
          expect(temp[:default]).to eq(0.7)
        end

        it 'includes LLM parameters' do
          expect(chat_def[:properties][:top_p]).to be_a(Hash)
          expect(chat_def[:properties][:frequency_penalty]).to be_a(Hash)
          expect(chat_def[:properties][:presence_penalty]).to be_a(Hash)
          expect(chat_def[:properties][:stop_sequences]).to be_a(Hash)
        end

        it 'validates parameter ranges' do
          expect(chat_def[:properties][:top_p][:minimum]).to eq(0.0)
          expect(chat_def[:properties][:top_p][:maximum]).to eq(1.0)
          expect(chat_def[:properties][:frequency_penalty][:minimum]).to eq(-2.0)
          expect(chat_def[:properties][:frequency_penalty][:maximum]).to eq(2.0)
        end
      end

      describe 'ToolDefinition' do
        let(:tool_def) { definitions[:ToolDefinition] }

        it 'includes tool properties' do
          expect(tool_def[:type]).to eq('object')
          expect(tool_def[:properties][:name]).to be_a(Hash)
          expect(tool_def[:properties][:description]).to be_a(Hash)
          expect(tool_def[:properties][:parameters]).to be_a(Hash)
        end

        it 'requires name and description' do
          expect(tool_def[:required]).to match_array(%w[name description])
        end

        it 'validates tool name pattern' do
          expect(tool_def[:properties][:name][:pattern]).to eq('^[a-z0-9_]+$')
        end

        it 'references ParameterDefinition for parameters' do
          params = tool_def[:properties][:parameters]
          expect(params[:type]).to eq('object')
          expect(params[:additionalProperties][:$ref]).to eq('#/definitions/ParameterDefinition')
        end
      end

      describe 'ParameterDefinition' do
        let(:param_def) { definitions[:ParameterDefinition] }

        it 'includes parameter properties' do
          expect(param_def[:type]).to eq('object')
          expect(param_def[:properties][:type]).to be_a(Hash)
          expect(param_def[:properties][:description]).to be_a(Hash)
          expect(param_def[:properties][:required]).to be_a(Hash)
          expect(param_def[:properties][:default]).to be_a(Hash)
          expect(param_def[:properties][:enum]).to be_a(Hash)
        end

        it 'requires type' do
          expect(param_def[:required]).to include('type')
        end

        it 'includes parameter type enum' do
          expect(param_def[:properties][:type][:enum]).to match_array(%w[string number integer boolean array object])
        end

        it 'has required default false' do
          expect(param_def[:properties][:required][:type]).to eq('boolean')
          expect(param_def[:properties][:required][:default]).to eq(false)
        end
      end
    end
  end

  describe 'schema structure' do
    let(:schema) { described_class.to_json_schema }

    it 'can be serialized to JSON' do
      require 'json'
      expect { JSON.generate(schema) }.not_to raise_error
    end

    it 'produces valid JSON output' do
      require 'json'
      json_str = JSON.generate(schema)
      parsed = JSON.parse(json_str)
      expect(parsed).to be_a(Hash)
    end
  end

  describe 'pattern validation' do
    let(:schema) { described_class.to_json_schema }

    it 'name pattern matches valid agent names' do
      pattern = Regexp.new(schema[:properties][:name][:pattern])
      expect('my-agent').to match(pattern)
      expect('agent-123').to match(pattern)
      expect('test-agent-v2').to match(pattern)
    end

    it 'name pattern rejects invalid agent names' do
      pattern = Regexp.new(schema[:properties][:name][:pattern])
      expect('My-Agent').not_to match(pattern) # uppercase
      expect('my_agent').not_to match(pattern) # underscore
      expect('my agent').not_to match(pattern) # space
    end

    it 'schedule pattern matches valid cron expressions' do
      pattern = Regexp.new(schema[:properties][:schedule][:pattern])
      expect('0 12 * * *').to match(pattern) # daily at noon
      expect('*/5 * * * *').to match(pattern) # every 5 minutes
      expect('0 0 1 * *').to match(pattern) # first day of month
    end

    it 'timeout pattern matches valid duration formats' do
      constraints = schema[:definitions][:ConstraintsDefinition]
      pattern = Regexp.new(constraints[:properties][:timeout][:pattern])
      expect('30s').to match(pattern)
      expect('5m').to match(pattern)
      expect('1h').to match(pattern)
      expect('120s').to match(pattern)
    end

    it 'timeout pattern rejects invalid formats' do
      constraints = schema[:definitions][:ConstraintsDefinition]
      pattern = Regexp.new(constraints[:properties][:timeout][:pattern])
      expect('30').not_to match(pattern) # missing unit
      expect('30ms').not_to match(pattern) # invalid unit
      expect('s30').not_to match(pattern) # wrong order
    end

    it 'webhook path pattern matches valid paths' do
      webhook = schema[:definitions][:WebhookDefinition]
      pattern = Regexp.new(webhook[:properties][:path][:pattern])
      expect('/webhook').to match(pattern)
      expect('/api/v1/webhook').to match(pattern)
      expect('/github/pr-opened').to match(pattern)
    end

    it 'tool name pattern matches valid tool names' do
      tool = schema[:definitions][:ToolDefinition]
      pattern = Regexp.new(tool[:properties][:name][:pattern])
      expect('process_csv').to match(pattern)
      expect('fetch_data').to match(pattern)
      expect('tool123').to match(pattern)
    end
  end

  describe 'safe methods extraction' do
    describe '.safe_agent_methods' do
      it 'returns an array' do
        expect(described_class.safe_agent_methods).to be_an(Array)
      end

      it 'returns an array of strings' do
        expect(described_class.safe_agent_methods).to all(be_a(String))
      end

      it 'returns sorted array' do
        methods = described_class.safe_agent_methods
        expect(methods).to eq(methods.sort)
      end

      it 'is not empty' do
        expect(described_class.safe_agent_methods).not_to be_empty
      end

      it 'matches constants from ASTValidator' do
        require_relative '../../../lib/language_operator/agent/safety/ast_validator'
        expected = LanguageOperator::Agent::Safety::ASTValidator::SAFE_AGENT_METHODS.sort
        expect(described_class.safe_agent_methods).to eq(expected)
      end

      it 'includes agent DSL methods' do
        methods = described_class.safe_agent_methods
        expect(methods).to include('agent', 'description', 'persona', 'objectives')
      end

      it 'includes workflow methods' do
        methods = described_class.safe_agent_methods
        expect(methods).to include('workflow', 'step', 'depends_on', 'prompt')
      end

      it 'includes constraint methods' do
        methods = described_class.safe_agent_methods
        expect(methods).to include('budget', 'constraints', 'max_requests', 'rate_limit')
      end

      it 'includes endpoint methods' do
        methods = described_class.safe_agent_methods
        expect(methods).to include('webhook', 'as_mcp_server', 'as_chat_endpoint')
      end
    end

    describe '.safe_tool_methods' do
      it 'returns an array' do
        expect(described_class.safe_tool_methods).to be_an(Array)
      end

      it 'returns an array of strings' do
        expect(described_class.safe_tool_methods).to all(be_a(String))
      end

      it 'returns sorted array' do
        methods = described_class.safe_tool_methods
        expect(methods).to eq(methods.sort)
      end

      it 'is not empty' do
        expect(described_class.safe_tool_methods).not_to be_empty
      end

      it 'matches constants from ASTValidator' do
        require_relative '../../../lib/language_operator/agent/safety/ast_validator'
        expected = LanguageOperator::Agent::Safety::ASTValidator::SAFE_TOOL_METHODS.sort
        expect(described_class.safe_tool_methods).to eq(expected)
      end

      it 'includes tool definition methods' do
        methods = described_class.safe_tool_methods
        expect(methods).to include('tool', 'description', 'parameter')
      end

      it 'includes parameter methods' do
        methods = described_class.safe_tool_methods
        expect(methods).to include('type', 'required', 'default')
      end

      it 'includes execution method' do
        methods = described_class.safe_tool_methods
        expect(methods).to include('execute')
      end
    end

    describe '.safe_helper_methods' do
      it 'returns an array' do
        expect(described_class.safe_helper_methods).to be_an(Array)
      end

      it 'returns an array of strings' do
        expect(described_class.safe_helper_methods).to all(be_a(String))
      end

      it 'returns sorted array' do
        methods = described_class.safe_helper_methods
        expect(methods).to eq(methods.sort)
      end

      it 'is not empty' do
        expect(described_class.safe_helper_methods).not_to be_empty
      end

      it 'matches constants from ASTValidator' do
        require_relative '../../../lib/language_operator/agent/safety/ast_validator'
        expected = LanguageOperator::Agent::Safety::ASTValidator::SAFE_HELPER_METHODS.sort
        expect(described_class.safe_helper_methods).to eq(expected)
      end

      it 'includes HTTP helper' do
        methods = described_class.safe_helper_methods
        expect(methods).to include('HTTP')
      end

      it 'includes Shell helper' do
        methods = described_class.safe_helper_methods
        expect(methods).to include('Shell')
      end

      it 'includes validation helpers' do
        methods = described_class.safe_helper_methods
        expect(methods).to include('validate_url', 'validate_phone', 'validate_email')
      end

      it 'includes environment helpers' do
        methods = described_class.safe_helper_methods
        expect(methods).to include('env_required', 'env_get')
      end

      it 'includes utility helpers' do
        methods = described_class.safe_helper_methods
        expect(methods).to include('truncate', 'parse_csv')
      end

      it 'includes response helpers' do
        methods = described_class.safe_helper_methods
        expect(methods).to include('error', 'success')
      end
    end
  end

  describe '.to_openapi' do
    let(:spec) { described_class.to_openapi }

    it 'returns a Hash' do
      expect(spec).to be_a(Hash)
    end

    describe 'OpenAPI metadata' do
      it 'specifies OpenAPI 3.0.3' do
        expect(spec[:openapi]).to eq('3.0.3')
      end

      it 'includes info section' do
        expect(spec[:info]).to be_a(Hash)
        expect(spec[:info][:title]).to eq('Language Operator Agent API')
        expect(spec[:info][:version]).to eq(LanguageOperator::VERSION)
        expect(spec[:info][:description]).to include('HTTP API endpoints')
      end

      it 'includes contact information' do
        expect(spec[:info][:contact]).to be_a(Hash)
        expect(spec[:info][:contact][:name]).to eq('Language Operator')
        expect(spec[:info][:contact][:url]).to include('github.com')
      end

      it 'includes license information' do
        expect(spec[:info][:license]).to be_a(Hash)
        expect(spec[:info][:license][:name]).to eq('FSL-1.1-Apache-2.0')
        expect(spec[:info][:license][:url]).to include('LICENSE')
      end
    end

    describe 'servers' do
      it 'includes servers array' do
        expect(spec[:servers]).to be_an(Array)
        expect(spec[:servers].length).to be > 0
      end

      it 'includes localhost server for development' do
        localhost = spec[:servers].find { |s| s[:url].include?('localhost') }
        expect(localhost).not_to be_nil
        expect(localhost[:description]).to include('development')
      end
    end

    describe 'paths' do
      let(:paths) { spec[:paths] }

      it 'includes paths section' do
        expect(paths).to be_a(Hash)
        expect(paths).not_to be_empty
      end

      it 'includes health endpoint' do
        expect(paths['/health']).to be_a(Hash)
        expect(paths['/health'][:get]).to be_a(Hash)
        expect(paths['/health'][:get][:summary]).to eq('Health check')
        expect(paths['/health'][:get][:tags]).to include('Health')
      end

      it 'includes readiness endpoint' do
        expect(paths['/ready']).to be_a(Hash)
        expect(paths['/ready'][:get]).to be_a(Hash)
        expect(paths['/ready'][:get][:summary]).to eq('Readiness check')
      end

      it 'includes chat completions endpoint' do
        expect(paths['/v1/chat/completions']).to be_a(Hash)
        expect(paths['/v1/chat/completions'][:post]).to be_a(Hash)
        expect(paths['/v1/chat/completions'][:post][:summary]).to include('chat completion')
      end

      it 'includes models endpoint' do
        expect(paths['/v1/models']).to be_a(Hash)
        expect(paths['/v1/models'][:get]).to be_a(Hash)
        expect(paths['/v1/models'][:get][:summary]).to include('models')
      end

      describe 'health endpoint specification' do
        let(:health) { paths['/health'][:get] }

        it 'has operation ID' do
          expect(health[:operationId]).to eq('getHealth')
        end

        it 'has 200 response' do
          expect(health[:responses][:'200']).to be_a(Hash)
          expect(health[:responses][:'200'][:description]).to include('healthy')
        end

        it 'references HealthResponse schema' do
          schema_ref = health[:responses][:'200'][:content][:'application/json'][:schema][:$ref]
          expect(schema_ref).to eq('#/components/schemas/HealthResponse')
        end
      end

      describe 'ready endpoint specification' do
        let(:ready) { paths['/ready'][:get] }

        it 'has operation ID' do
          expect(ready[:operationId]).to eq('getReady')
        end

        it 'has 200 and 503 responses' do
          expect(ready[:responses][:'200']).to be_a(Hash)
          expect(ready[:responses][:'503']).to be_a(Hash)
        end

        it 'references appropriate schemas' do
          success_ref = ready[:responses][:'200'][:content][:'application/json'][:schema][:$ref]
          error_ref = ready[:responses][:'503'][:content][:'application/json'][:schema][:$ref]

          expect(success_ref).to eq('#/components/schemas/HealthResponse')
          expect(error_ref).to eq('#/components/schemas/ErrorResponse')
        end
      end

      describe 'chat completions endpoint specification' do
        let(:chat) { paths['/v1/chat/completions'][:post] }

        it 'has operation ID' do
          expect(chat[:operationId]).to eq('createChatCompletion')
        end

        it 'has Chat tag' do
          expect(chat[:tags]).to include('Chat')
        end

        it 'requires request body' do
          expect(chat[:requestBody]).to be_a(Hash)
          expect(chat[:requestBody][:required]).to be true
        end

        it 'references ChatCompletionRequest schema for request' do
          schema_ref = chat[:requestBody][:content][:'application/json'][:schema][:$ref]
          expect(schema_ref).to eq('#/components/schemas/ChatCompletionRequest')
        end

        it 'has 200 and 400 responses' do
          expect(chat[:responses][:'200']).to be_a(Hash)
          expect(chat[:responses][:'400']).to be_a(Hash)
        end

        it 'supports both JSON and streaming responses' do
          response_content = chat[:responses][:'200'][:content]
          expect(response_content[:'application/json']).to be_a(Hash)
          expect(response_content[:'text/event-stream']).to be_a(Hash)
        end

        it 'references ChatCompletionResponse schema for response' do
          schema_ref = chat[:responses][:'200'][:content][:'application/json'][:schema][:$ref]
          expect(schema_ref).to eq('#/components/schemas/ChatCompletionResponse')
        end
      end

      describe 'models endpoint specification' do
        let(:models) { paths['/v1/models'][:get] }

        it 'has operation ID' do
          expect(models[:operationId]).to eq('listModels')
        end

        it 'has Models tag' do
          expect(models[:tags]).to include('Models')
        end

        it 'has 200 response' do
          expect(models[:responses][:'200']).to be_a(Hash)
        end

        it 'references ModelList schema' do
          schema_ref = models[:responses][:'200'][:content][:'application/json'][:schema][:$ref]
          expect(schema_ref).to eq('#/components/schemas/ModelList')
        end
      end
    end

    describe 'components' do
      let(:components) { spec[:components] }

      it 'includes components section' do
        expect(components).to be_a(Hash)
      end

      it 'includes schemas' do
        expect(components[:schemas]).to be_a(Hash)
        expect(components[:schemas]).not_to be_empty
      end

      it 'includes all required schemas' do
        expected_schemas = %i[
          ChatCompletionRequest
          ChatCompletionResponse
          ChatMessage
          ChatChoice
          ChatUsage
          ModelList
          Model
          HealthResponse
          ErrorResponse
        ]

        expected_schemas.each do |schema_name|
          expect(components[:schemas]).to have_key(schema_name), "Missing schema: #{schema_name}"
        end
      end

      describe 'ChatCompletionRequest schema' do
        let(:schema) { components[:schemas][:ChatCompletionRequest] }

        it 'is an object type' do
          expect(schema[:type]).to eq('object')
        end

        it 'requires model and messages' do
          expect(schema[:required]).to include('model', 'messages')
        end

        it 'includes standard OpenAI parameters' do
          expect(schema[:properties][:model]).to be_a(Hash)
          expect(schema[:properties][:messages]).to be_a(Hash)
          expect(schema[:properties][:temperature]).to be_a(Hash)
          expect(schema[:properties][:max_tokens]).to be_a(Hash)
          expect(schema[:properties][:stream]).to be_a(Hash)
        end

        it 'includes advanced parameters' do
          expect(schema[:properties][:top_p]).to be_a(Hash)
          expect(schema[:properties][:frequency_penalty]).to be_a(Hash)
          expect(schema[:properties][:presence_penalty]).to be_a(Hash)
          expect(schema[:properties][:stop]).to be_a(Hash)
        end

        it 'validates temperature range' do
          temp = schema[:properties][:temperature]
          expect(temp[:minimum]).to eq(0.0)
          expect(temp[:maximum]).to eq(2.0)
          expect(temp[:default]).to eq(0.7)
        end

        it 'validates penalty ranges' do
          freq = schema[:properties][:frequency_penalty]
          pres = schema[:properties][:presence_penalty]

          expect(freq[:minimum]).to eq(-2.0)
          expect(freq[:maximum]).to eq(2.0)
          expect(pres[:minimum]).to eq(-2.0)
          expect(pres[:maximum]).to eq(2.0)
        end

        it 'allows stop as string or array' do
          stop = schema[:properties][:stop]
          expect(stop[:oneOf]).to be_an(Array)
          expect(stop[:oneOf].length).to eq(2)
        end
      end

      describe 'ChatCompletionResponse schema' do
        let(:schema) { components[:schemas][:ChatCompletionResponse] }

        it 'requires standard fields' do
          expect(schema[:required]).to include('id', 'object', 'created', 'model', 'choices')
        end

        it 'includes all response properties' do
          expect(schema[:properties][:id]).to be_a(Hash)
          expect(schema[:properties][:object]).to be_a(Hash)
          expect(schema[:properties][:created]).to be_a(Hash)
          expect(schema[:properties][:model]).to be_a(Hash)
          expect(schema[:properties][:choices]).to be_a(Hash)
          expect(schema[:properties][:usage]).to be_a(Hash)
        end

        it 'validates object type as chat.completion' do
          expect(schema[:properties][:object][:enum]).to eq(['chat.completion'])
        end

        it 'references ChatChoice for choices' do
          choices = schema[:properties][:choices]
          expect(choices[:type]).to eq('array')
          expect(choices[:items][:$ref]).to eq('#/components/schemas/ChatChoice')
        end

        it 'references ChatUsage for usage' do
          expect(schema[:properties][:usage][:$ref]).to eq('#/components/schemas/ChatUsage')
        end
      end

      describe 'ChatMessage schema' do
        let(:schema) { components[:schemas][:ChatMessage] }

        it 'requires role and content' do
          expect(schema[:required]).to include('role', 'content')
        end

        it 'validates role enum' do
          expect(schema[:properties][:role][:enum]).to match_array(%w[system user assistant])
        end

        it 'includes optional name field' do
          expect(schema[:properties][:name]).to be_a(Hash)
        end
      end

      describe 'ChatChoice schema' do
        let(:schema) { components[:schemas][:ChatChoice] }

        it 'requires index, message, and finish_reason' do
          expect(schema[:required]).to include('index', 'message', 'finish_reason')
        end

        it 'references ChatMessage' do
          expect(schema[:properties][:message][:$ref]).to eq('#/components/schemas/ChatMessage')
        end

        it 'validates finish_reason enum' do
          expect(schema[:properties][:finish_reason][:enum]).to include('stop', 'length')
        end
      end

      describe 'ChatUsage schema' do
        let(:schema) { components[:schemas][:ChatUsage] }

        it 'requires token counts' do
          expect(schema[:required]).to include('prompt_tokens', 'completion_tokens', 'total_tokens')
        end

        it 'defines all token fields as integers' do
          expect(schema[:properties][:prompt_tokens][:type]).to eq('integer')
          expect(schema[:properties][:completion_tokens][:type]).to eq('integer')
          expect(schema[:properties][:total_tokens][:type]).to eq('integer')
        end
      end

      describe 'ModelList schema' do
        let(:schema) { components[:schemas][:ModelList] }

        it 'requires object and data' do
          expect(schema[:required]).to include('object', 'data')
        end

        it 'validates object type as list' do
          expect(schema[:properties][:object][:enum]).to eq(['list'])
        end

        it 'references Model for data items' do
          data = schema[:properties][:data]
          expect(data[:type]).to eq('array')
          expect(data[:items][:$ref]).to eq('#/components/schemas/Model')
        end
      end

      describe 'Model schema' do
        let(:schema) { components[:schemas][:Model] }

        it 'requires id and object' do
          expect(schema[:required]).to include('id', 'object')
        end

        it 'validates object type as model' do
          expect(schema[:properties][:object][:enum]).to eq(['model'])
        end

        it 'includes optional fields' do
          expect(schema[:properties][:created]).to be_a(Hash)
          expect(schema[:properties][:owned_by]).to be_a(Hash)
        end
      end

      describe 'HealthResponse schema' do
        let(:schema) { components[:schemas][:HealthResponse] }

        it 'requires status' do
          expect(schema[:required]).to include('status')
        end

        it 'validates status enum' do
          expect(schema[:properties][:status][:enum]).to match_array(%w[ok ready])
        end

        it 'includes optional timestamp with date-time format' do
          timestamp = schema[:properties][:timestamp]
          expect(timestamp[:type]).to eq('string')
          expect(timestamp[:format]).to eq('date-time')
        end
      end

      describe 'ErrorResponse schema' do
        let(:schema) { components[:schemas][:ErrorResponse] }

        it 'requires error field' do
          expect(schema[:required]).to include('error')
        end

        it 'defines nested error object' do
          error = schema[:properties][:error]
          expect(error[:type]).to eq('object')
          expect(error[:required]).to include('message', 'type')
        end

        it 'includes error properties' do
          error_props = schema[:properties][:error][:properties]
          expect(error_props[:message]).to be_a(Hash)
          expect(error_props[:type]).to be_a(Hash)
          expect(error_props[:code]).to be_a(Hash)
        end
      end
    end

    describe 'spec structure' do
      it 'can be serialized to JSON' do
        require 'json'
        expect { JSON.generate(spec) }.not_to raise_error
      end

      it 'produces valid JSON output' do
        require 'json'
        json_str = JSON.generate(spec)
        parsed = JSON.parse(json_str)
        expect(parsed).to be_a(Hash)
        expect(parsed['openapi']).to eq('3.0.3')
      end

      it 'maintains structure after JSON round-trip' do
        require 'json'
        json_str = JSON.generate(spec)
        parsed = JSON.parse(json_str, symbolize_names: true)

        expect(parsed[:openapi]).to eq('3.0.3')
        expect(parsed[:info][:title]).to eq('Language Operator Agent API')
        expect(parsed[:paths]).to have_key(:'/health')
        expect(parsed[:components][:schemas]).to have_key(:ChatCompletionRequest)
      end
    end

    describe 'OpenAPI 3.0 compliance' do
      it 'includes all required top-level fields' do
        expect(spec).to have_key(:openapi)
        expect(spec).to have_key(:info)
        expect(spec).to have_key(:paths)
      end

      it 'info section includes required fields' do
        expect(spec[:info]).to have_key(:title)
        expect(spec[:info]).to have_key(:version)
      end

      it 'paths is a non-empty object' do
        expect(spec[:paths]).to be_a(Hash)
        expect(spec[:paths]).not_to be_empty
      end

      it 'each path item contains valid HTTP methods' do
        spec[:paths].each_value do |operations|
          expect(operations).to be_a(Hash)
          operations.each_key do |method|
            expect(%i[get post put delete patch options head trace]).to include(method)
          end
        end
      end

      it 'each operation has responses' do
        spec[:paths].each_value do |operations|
          operations.each do |method, operation|
            next if method == :parameters

            expect(operation[:responses]).to be_a(Hash),
                                             "Missing responses for #{method}"
            expect(operation[:responses]).not_to be_empty
          end
        end
      end
    end
  end
end
