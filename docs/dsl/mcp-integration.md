# MCP Integration Guide

Complete guide to using the Model Context Protocol (MCP) with Language Operator agents.

## Table of Contents

- [Overview](#overview)
- [MCP Server: Exposing Tools](#mcp-server-exposing-tools)
- [Tool Definition](#tool-definition)
- [Parameter Definition](#parameter-definition)
- [Tool Execution](#tool-execution)
- [MCP Protocol Endpoints](#mcp-protocol-endpoints)
- [Complete Examples](#complete-examples)
- [Testing MCP Tools](#testing-mcp-tools)
- [Best Practices](#best-practices)

## Overview

The Model Context Protocol (MCP) enables agents to expose and consume tools in a standardized way. Language Operator provides two key MCP capabilities:

1. **MCP Server**: Agents can expose their own tools that other agents or MCP clients can call
2. **MCP Client**: Agents can connect to external MCP servers and use their tools (via configuration)

### What is MCP?

MCP is a standardized protocol for tool discovery and execution in LLM applications. It enables:
- Tool discovery via JSON-RPC protocol
- Type-safe parameter definitions with validation
- Remote tool execution
- Tool composition across different agents

### Key Concepts

- **MCP Server**: An agent that exposes tools via the MCP protocol
- **Tool**: A function that can be called with parameters and returns results
- **Parameter**: A typed input to a tool with validation rules
- **JSON-RPC**: The protocol used for MCP communication

## MCP Server: Exposing Tools

Any agent can act as an MCP server by defining tools in an `as_mcp_server` block.

### Basic MCP Server

```ruby
agent "data-processor" do
  description "Data processing agent"
  mode :reactive

  as_mcp_server do
    tool "process_csv" do
      description "Process CSV data and return statistics"

      parameter :csv_data do
        type :string
        required true
        description "CSV data as string"
      end

      execute do |params|
        # Tool implementation
        lines = params['csv_data'].split("\n")
        { total_rows: lines.length }.to_json
      end
    end
  end
end
```

**Key points:**
- Use `as_mcp_server` block to define MCP capabilities
- Agent automatically runs in `:reactive` mode when MCP server is defined
- MCP endpoint is automatically created at `/mcp`
- Tools are automatically registered and discoverable

### Custom Server Name

By default, the server name is `{agent-name}-mcp`. You can customize it:

```ruby
as_mcp_server do
  name "custom-processor-server"

  tool "my_tool" do
    # Tool definition...
  end
end
```

### Multiple Tools

Define multiple tools in one server:

```ruby
as_mcp_server do
  tool "process_csv" do
    description "Process CSV data"
    # ...
  end

  tool "calculate_stats" do
    description "Calculate statistics"
    # ...
  end

  tool "format_json" do
    description "Format and validate JSON"
    # ...
  end
end
```

## Tool Definition

Tools are the core of MCP integration. Each tool has a name, description, parameters, and execution logic.

### Basic Tool Structure

```ruby
tool "tool_name" do
  description "What this tool does"

  parameter :param_name do
    type :string
    required true
    description "What this parameter is for"
  end

  execute do |params|
    # Tool logic here
    # Return value (string, hash, array, etc.)
  end
end
```

### Tool Components

**Name** (String)
- Unique identifier for the tool
- Used in MCP protocol and API calls
- Convention: lowercase with underscores

**Description** (String)
- Human-readable description of tool functionality
- Should explain what the tool does and when to use it
- Helps LLMs decide when to call the tool

**Parameters** (Block)
- Define inputs the tool accepts
- Each parameter has type, validation, and metadata
- See [Parameter Definition](#parameter-definition) below

**Execute Block** (Proc)
- Contains the tool's implementation logic
- Receives `params` hash with validated parameters
- Should return a value (string, hash, array, etc.)

### Tool Examples

**Simple calculation tool:**
```ruby
tool "add" do
  description "Add two numbers together"

  parameter :a do
    type :number
    required true
    description "First number"
  end

  parameter :b do
    type :number
    required true
    description "Second number"
  end

  execute do |params|
    (params['a'] + params['b']).to_s
  end
end
```

**Data transformation tool:**
```ruby
tool "transform_json" do
  description "Transform JSON data according to mapping rules"

  parameter :data do
    type :object
    required true
    description "Input JSON data"
  end

  parameter :mapping do
    type :object
    required true
    description "Transformation mapping rules"
  end

  execute do |params|
    data = params['data']
    mapping = params['mapping']

    result = {}
    mapping.each do |source_key, target_key|
      result[target_key] = data[source_key] if data.key?(source_key)
    end

    result.to_json
  end
end
```

**HTTP API tool:**
```ruby
tool "fetch_user" do
  description "Fetch user data from API by ID"

  parameter :user_id do
    type :string
    required true
    description "User ID to fetch"
  end

  parameter :include_profile do
    type :boolean
    required false
    description "Include full profile data"
  end

  execute do |params|
    require 'net/http'
    require 'json'

    url = "https://api.example.com/users/#{params['user_id']}"
    url += "?include_profile=true" if params['include_profile']

    response = Net::HTTP.get(URI(url))
    JSON.parse(response).to_json
  rescue StandardError => e
    { error: e.message }.to_json
  end
end
```

## Parameter Definition

Parameters define the inputs a tool accepts, with type safety and validation.

### Parameter Types

Language Operator supports the following parameter types:

```ruby
parameter :string_param do
  type :string  # Text values
end

parameter :number_param do
  type :number  # Numeric values (integers or floats)
end

parameter :integer_param do
  type :integer  # Integer values only
end

parameter :boolean_param do
  type :boolean  # true/false values
end

parameter :array_param do
  type :array  # Array/list values
end

parameter :object_param do
  type :object  # Hash/object values
end
```

### Required vs Optional

```ruby
parameter :required_param do
  type :string
  required true  # Must be provided
end

parameter :optional_param do
  type :string
  required false  # Can be omitted
end
```

**Behavior:**
- Required parameters: Tool execution fails if not provided
- Optional parameters: Can be omitted, defaults to `nil` unless default set

### Default Values

```ruby
parameter :timeout do
  type :number
  required false
  default 30  # Used if parameter not provided
  description "Timeout in seconds (default: 30)"
end

parameter :format do
  type :string
  required false
  default "json"
  description "Output format: json, xml, or csv"
end
```

### Enum Values

Restrict parameter to specific allowed values:

```ruby
parameter :status do
  type :string
  required true
  enum ["active", "inactive", "pending"]
  description "User status"
end

parameter :log_level do
  type :string
  required false
  default "info"
  enum ["debug", "info", "warn", "error"]
  description "Log level for output"
end
```

**Behavior:**
- Parameter value must match one of the enum values
- Validation error raised if value not in enum

### Parameter Validation

**Built-in validators:**

```ruby
# URL format validation
parameter :website do
  type :string
  required true
  url_format  # Validates http:// or https:// URLs
end

# Email format validation
parameter :email do
  type :string
  required true
  email_format  # Validates email address format
end

# Phone format validation
parameter :phone do
  type :string
  required true
  phone_format  # Validates +1234567890 format
end
```

**Regex validators:**

```ruby
parameter :zip_code do
  type :string
  required true
  validate /^\d{5}(-\d{4})?$/  # US ZIP code format
  description "US ZIP code (5 or 9 digits)"
end

parameter :product_code do
  type :string
  required true
  validate /^[A-Z]{3}-\d{4}$/  # Custom format
  description "Product code (e.g., ABC-1234)"
end
```

**Custom validators (Proc):**

```ruby
parameter :age do
  type :number
  required true
  validate ->(value) {
    if value < 0 || value > 150
      "Age must be between 0 and 150"
    else
      true
    end
  }
  description "Person's age"
end

parameter :username do
  type :string
  required true
  validate ->(value) {
    return "Username too short" if value.length < 3
    return "Username too long" if value.length > 20
    return "Username must be alphanumeric" unless value.match?(/^[a-zA-Z0-9_]+$/)
    true
  }
  description "Username (3-20 alphanumeric characters)"
end
```

**Validation behavior:**
- Validators run before tool execution
- If validation fails, tool execution is prevented
- Error message is returned to caller
- Custom validators can return `String` (error message) or `Boolean`

### Complete Parameter Examples

**Simple required parameter:**
```ruby
parameter :message do
  type :string
  required true
  description "Message to send"
end
```

**Optional parameter with default:**
```ruby
parameter :retries do
  type :number
  required false
  default 3
  description "Number of retry attempts (default: 3)"
end
```

**Enum with default:**
```ruby
parameter :environment do
  type :string
  required false
  default "production"
  enum ["development", "staging", "production"]
  description "Deployment environment"
end
```

**Validated parameter:**
```ruby
parameter :api_key do
  type :string
  required true
  validate /^[A-Za-z0-9_-]{32,}$/  # At least 32 alphanumeric chars
  description "API authentication key"
end
```

## Tool Execution

The `execute` block contains the tool's implementation logic.

### Execute Block Basics

```ruby
execute do |params|
  # Access parameters
  input = params['input_param']

  # Perform logic
  result = process(input)

  # Return result (any JSON-serializable value)
  result
end
```

**Key points:**
- Receives `params` hash with validated parameter values
- Parameter names are strings (not symbols)
- Should return a value (string, number, hash, array, etc.)
- Exceptions are caught and returned as errors

### Accessing Parameters

Parameters are passed as a hash with string keys:

```ruby
tool "greet" do
  parameter :name do
    type :string
    required true
  end

  parameter :greeting do
    type :string
    required false
    default "Hello"
  end

  execute do |params|
    name = params['name']
    greeting = params['greeting']
    "#{greeting}, #{name}!"
  end
end
```

### Return Values

Tools can return various types:

**String:**
```ruby
execute do |params|
  "Result: #{params['value']}"
end
```

**Number:**
```ruby
execute do |params|
  params['a'] + params['b']
end
```

**Hash (returned as JSON):**
```ruby
execute do |params|
  {
    success: true,
    result: "processed",
    timestamp: Time.now.iso8601
  }.to_json
end
```

**Array:**
```ruby
execute do |params|
  [1, 2, 3, 4, 5].to_json
end
```

### Error Handling

Handle errors gracefully in execute blocks:

```ruby
execute do |params|
  begin
    # Risky operation
    result = external_api_call(params['data'])
    { success: true, result: result }.to_json
  rescue StandardError => e
    {
      success: false,
      error: e.message,
      error_type: e.class.name
    }.to_json
  end
end
```

**Best practices:**
- Always rescue exceptions in execute blocks
- Return error information in a consistent format
- Include error type and message for debugging
- Log errors for monitoring

### External Dependencies

Tools can use external libraries and services:

```ruby
tool "send_email" do
  parameter :to do
    type :string
    required true
    email_format
  end

  parameter :subject do
    type :string
    required true
  end

  parameter :body do
    type :string
    required true
  end

  execute do |params|
    require 'mail'

    Mail.deliver do
      to      params['to']
      from    ENV['SMTP_FROM']
      subject params['subject']
      body    params['body']
    end

    { success: true, sent_at: Time.now.iso8601 }.to_json
  rescue StandardError => e
    { success: false, error: e.message }.to_json
  end
end
```

## MCP Protocol Endpoints

When an agent acts as an MCP server, it automatically exposes MCP protocol endpoints.

### Automatic Endpoints

**MCP Protocol** - `POST /mcp`
- JSON-RPC 2.0 endpoint for tool discovery and execution
- Supports standard MCP methods: `tools/list`, `tools/call`

**Webhook** - `POST /webhook`
- Standard webhook endpoint (if defined)
- Can coexist with MCP server functionality

**Health Check** - `GET /health`
- Returns server health status
- Always available

**Readiness Check** - `GET /ready`
- Returns readiness status
- Always available

### MCP Protocol Methods

**List Tools** - `tools/list`

Request:
```json
{
  "jsonrpc": "2.0",
  "method": "tools/list",
  "id": 1
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "process_csv",
        "description": "Process CSV data and return statistics",
        "inputSchema": {
          "type": "object",
          "properties": {
            "csv_data": {
              "type": "string",
              "description": "CSV data as string"
            }
          },
          "required": ["csv_data"]
        }
      }
    ]
  }
}
```

**Call Tool** - `tools/call`

Request:
```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "process_csv",
    "arguments": {
      "csv_data": "name,age\nAlice,30\nBob,25"
    }
  },
  "id": 2
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"total_rows\":2}"
      }
    ]
  }
}
```

## Complete Examples

### Data Processing MCP Server

```ruby
agent "data-processor-mcp" do
  description "Data processing agent with MCP tools"
  mode :reactive

  as_mcp_server do
    # Tool 1: Process CSV
    tool "process_csv" do
      description "Process CSV data and return summary statistics"

      parameter :csv_data do
        type :string
        required true
        description "CSV data as string"
      end

      execute do |params|
        lines = params['csv_data'].split("\n")
        headers = lines.first&.split(',') || []
        data_rows = lines[1..]

        {
          total_rows: data_rows&.length || 0,
          total_columns: headers.length,
          headers: headers,
          sample: data_rows&.first || ''
        }.to_json
      end
    end

    # Tool 2: Calculate statistics
    tool "calculate_stats" do
      description "Calculate basic statistics for a list of numbers"

      parameter :numbers do
        type :array
        required true
        description "Array of numbers"
      end

      execute do |params|
        nums = params['numbers']
        return { error: 'Empty array' }.to_json if nums.empty?

        sum = nums.sum
        mean = sum.to_f / nums.length
        sorted = nums.sort
        median = if nums.length.odd?
                   sorted[nums.length / 2]
                 else
                   (sorted[(nums.length / 2) - 1] + sorted[nums.length / 2]) / 2.0
                 end

        {
          count: nums.length,
          sum: sum,
          mean: mean,
          median: median,
          min: nums.min,
          max: nums.max
        }.to_json
      end
    end

    # Tool 3: Format JSON
    tool "format_json" do
      description "Format and validate JSON data"

      parameter :json_string do
        type :string
        required true
        description "JSON string to format"
      end

      parameter :indent do
        type :number
        required false
        default 2
        description "Indentation spaces (default: 2)"
      end

      execute do |params|
        indent = params['indent'] || 2
        parsed = JSON.parse(params['json_string'])
        JSON.pretty_generate(parsed, indent: ' ' * indent.to_i)
      rescue JSON::ParserError => e
        { error: "Invalid JSON: #{e.message}" }.to_json
      end
    end
  end

  # Optional: Also expose webhook endpoint
  webhook "/process" do
    method :post
    on_request do |_context|
      {
        status: 'processed',
        tools_available: 3,
        mcp_endpoint: '/mcp'
      }
    end
  end
end
```

### Text Processing MCP Server

```ruby
agent "text-processor" do
  description "Text processing and transformation tools"
  mode :reactive

  as_mcp_server do
    name "text-tools-server"

    tool "word_count" do
      description "Count words, characters, and lines in text"

      parameter :text do
        type :string
        required true
        description "Text to analyze"
      end

      execute do |params|
        text = params['text']
        {
          characters: text.length,
          words: text.split.length,
          lines: text.lines.count,
          paragraphs: text.split("\n\n").length
        }.to_json
      end
    end

    tool "case_transform" do
      description "Transform text case"

      parameter :text do
        type :string
        required true
        description "Text to transform"
      end

      parameter :format do
        type :string
        required true
        enum ["uppercase", "lowercase", "titlecase", "capitalize"]
        description "Target format"
      end

      execute do |params|
        text = params['text']
        case params['format']
        when "uppercase"
          text.upcase
        when "lowercase"
          text.downcase
        when "titlecase"
          text.split.map(&:capitalize).join(' ')
        when "capitalize"
          text.capitalize
        else
          text
        end
      end
    end

    tool "extract_emails" do
      description "Extract email addresses from text"

      parameter :text do
        type :string
        required true
        description "Text to scan for emails"
      end

      execute do |params|
        email_regex = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
        emails = params['text'].scan(email_regex).uniq
        { emails: emails, count: emails.length }.to_json
      end
    end
  end

  constraints do
    timeout '30s'
    requests_per_minute 60
  end
end
```

### API Integration MCP Server

```ruby
agent "weather-api-server" do
  description "Weather data API integration"
  mode :reactive

  as_mcp_server do
    tool "get_current_weather" do
      description "Get current weather for a location"

      parameter :location do
        type :string
        required true
        description "City name or ZIP code"
      end

      parameter :units do
        type :string
        required false
        default "metric"
        enum ["metric", "imperial"]
        description "Temperature units"
      end

      execute do |params|
        require 'net/http'
        require 'json'

        api_key = ENV['WEATHER_API_KEY']
        location = params['location']
        units = params['units'] || 'metric'

        url = "https://api.openweathermap.org/data/2.5/weather?q=#{location}&units=#{units}&appid=#{api_key}"
        response = Net::HTTP.get(URI(url))
        data = JSON.parse(response)

        {
          location: data['name'],
          temperature: data['main']['temp'],
          feels_like: data['main']['feels_like'],
          humidity: data['main']['humidity'],
          description: data['weather'].first['description'],
          units: units
        }.to_json
      rescue StandardError => e
        { error: e.message }.to_json
      end
    end

    tool "get_forecast" do
      description "Get 5-day weather forecast"

      parameter :location do
        type :string
        required true
        description "City name or ZIP code"
      end

      execute do |params|
        require 'net/http'
        require 'json'

        api_key = ENV['WEATHER_API_KEY']
        url = "https://api.openweathermap.org/data/2.5/forecast?q=#{params['location']}&appid=#{api_key}"
        response = Net::HTTP.get(URI(url))
        data = JSON.parse(response)

        forecast = data['list'].map do |item|
          {
            datetime: item['dt_txt'],
            temperature: item['main']['temp'],
            description: item['weather'].first['description']
          }
        end

        { location: data['city']['name'], forecast: forecast }.to_json
      rescue StandardError => e
        { error: e.message }.to_json
      end
    end
  end

  constraints do
    timeout '10s'
    requests_per_minute 30  # Respect API rate limits
    daily_budget 500  # $5/day
  end
end
```

## Testing MCP Tools

### Using curl

**List available tools:**
```bash
curl -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/list",
    "id": 1
  }'
```

**Call a tool:**
```bash
curl -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "process_csv",
      "arguments": {
        "csv_data": "name,age\nAlice,30\nBob,25"
      }
    },
    "id": 2
  }'
```

### Using RSpec

```ruby
require 'spec_helper'

RSpec.describe 'MCP Tools' do
  let(:mcp_def) { LanguageOperator::Dsl::McpServerDefinition.new('test-agent') }

  before do
    mcp_def.tool('greet') do
      description 'Greet a user'
      parameter :name do
        type :string
        required true
      end
      execute do |params|
        "Hello, #{params['name']}!"
      end
    end
  end

  it 'executes tool successfully' do
    tool = mcp_def.tools['greet']
    result = tool.call('name' => 'Alice')
    expect(result).to eq('Hello, Alice!')
  end

  it 'validates required parameters' do
    tool = mcp_def.tools['greet']
    expect {
      tool.call({})  # Missing required 'name' parameter
    }.to raise_error(ArgumentError, /Missing required parameter/)
  end
end
```

### Integration Testing

```ruby
# Test full MCP server
agent_def = LanguageOperator::Dsl.agent_registry.get('data-processor-mcp')

# Start server in test mode
# Make HTTP requests to /mcp endpoint
# Verify responses match MCP protocol
```

## Best Practices

### Tool Design

1. **Keep tools focused** - Each tool should do one thing well
2. **Use clear names** - Tool names should describe what they do
3. **Write good descriptions** - Help LLMs understand when to use the tool
4. **Validate inputs** - Use parameter validation to prevent errors
5. **Handle errors gracefully** - Return error information, don't crash

### Parameter Design

1. **Use required for critical params** - Make essential parameters required
2. **Provide defaults** - Set sensible defaults for optional parameters
3. **Use enums for choices** - Restrict to valid values when applicable
4. **Validate formats** - Use built-in or custom validators
5. **Document clearly** - Write clear parameter descriptions

### Error Handling

1. **Always rescue exceptions** - Prevent tools from crashing
2. **Return structured errors** - Use consistent error format
3. **Include error details** - Return error type and message
4. **Log errors** - Enable debugging with proper logging

```ruby
execute do |params|
  begin
    result = risky_operation(params)
    { success: true, result: result }.to_json
  rescue StandardError => e
    logger.error("Tool execution failed: #{e.message}")
    {
      success: false,
      error: e.message,
      error_type: e.class.name
    }.to_json
  end
end
```

### Performance

1. **Set timeouts** - Prevent tools from hanging
2. **Limit rate** - Use constraints to control usage
3. **Cache results** - Cache expensive operations when appropriate
4. **Monitor usage** - Track tool execution metrics

```ruby
agent "mcp-server" do
  as_mcp_server do
    # Tools...
  end

  constraints do
    timeout '30s'  # Per-request timeout
    requests_per_minute 60
    daily_budget 1000
  end
end
```

### Security

1. **Validate all inputs** - Never trust user input
2. **Sanitize parameters** - Prevent injection attacks
3. **Limit access** - Use authentication on MCP endpoints
4. **Avoid secrets in responses** - Don't leak sensitive data
5. **Log security events** - Monitor for abuse

```ruby
parameter :sql_query do
  type :string
  required true
  validate ->(value) {
    # Prevent SQL injection
    return "Invalid query" if value.match?(/;\s*(DROP|DELETE|UPDATE)/i)
    true
  }
end
```

### Testing

1. **Test tool execution** - Verify tools work correctly
2. **Test validation** - Ensure parameter validation works
3. **Test error cases** - Verify error handling
4. **Test edge cases** - Test boundary conditions
5. **Integration test** - Test full MCP protocol

### Documentation

1. **Document each tool** - Explain purpose and usage
2. **Document parameters** - Describe each parameter clearly
3. **Provide examples** - Show example calls and responses
4. **Document errors** - Explain possible error conditions
5. **Keep docs updated** - Update when tools change

## See Also

- [Agent Reference](agent-reference.md) - Complete agent DSL reference
- [Chat Endpoints](chat-endpoints.md) - OpenAI-compatible endpoint guide
- [Webhooks](webhooks.md) - Reactive agent configuration
- [Best Practices](best-practices.md) - Production deployment patterns
