# Using Tools

Language Operator agents interact with external services through the Model Context Protocol (MCP). This guide shows how to configure and use tools in your agent definitions.

## How Tools Work

Tools in Language Operator are provided by MCP servers that expose specific capabilities to agents. When you define an agent that needs external access, you specify which MCP tools are available.

### Tool Examples

Common tools agents use:
- **Database tools**: Query databases, run SQL, manage data
- **API tools**: Call REST APIs, GraphQL endpoints, webhooks
- **File tools**: Read/write files, process documents
- **Communication tools**: Send emails, Slack messages, notifications  
- **Cloud tools**: AWS S3, Google Cloud, Azure services
- **Git tools**: GitHub, GitLab operations

## Using Tools in Agents

### Basic Tool Usage in Tasks

Tasks can use MCP tools during neural (AI-powered) execution:

```ruby
task :fetch_user_orders do |inputs|
  # Tool usage is handled by the AI synthesis process
  # The AI will determine appropriate tools to call based on:
  # - Available MCP servers
  # - Task requirements
  # - Input/output schemas
  
  user_id = inputs[:user_id]
  # AI will synthesize appropriate tool calls
  { orders: [] } # Placeholder - actual implementation synthesized
end
```

### MCP Tool Server Configuration

Tools are provided by MCP servers defined in your agent:

```ruby
agent "order-processor" do
  description "Process customer orders"
  
  mcp_server do
    # MCP server configuration would go here
    # See components/tool/ directory for examples
  end
  
  task :fetch_orders do |inputs|
    # AI synthesis will use available MCP tools
    { orders: [] }
  end
end
```

## Tool Categories

### MCP Tool Examples

Tools are provided by MCP servers. See `components/tool/examples/` for working examples:

```ruby
# Example calculator tool (from components/tool/examples/calculator.rb)
tool 'calculate' do
  description 'Perform basic mathematical calculations'
  
  parameter 'expression' do
    type :string
    required true
    description 'Mathematical expression to evaluate'
  end
  
  execute do |params|
    result = eval(params['expression']) # Note: Use safe evaluation in production
    { result: result }
  end
end
```

### HTTP/API Tools

Call external APIs and web services:

```ruby
# REST API calls
execute_tool('http', 'get', {
  url: 'https://api.example.com/users',
  headers: { 'Authorization': 'Bearer token123' }
})

# GraphQL queries
execute_tool('graphql', 'query', {
  endpoint: 'https://api.github.com/graphql',
  query: 'query { viewer { login } }'
})

# Webhook sending
execute_tool('webhook', 'post', {
  url: 'https://hooks.slack.com/webhook-url',
  payload: { text: 'Hello from agent!' }
})
```

### File System Tools

Read and write files:

```ruby
# Read files
execute_tool('file', 'read', {
  path: '/data/input.json'
})

# Write files
execute_tool('file', 'write', {
  path: '/output/report.txt',
  content: 'Generated report data...'
})

# List directories
execute_tool('file', 'list', {
  path: '/data',
  pattern: '*.csv'
})
```

### Communication Tools

Send notifications and messages:

```ruby
# Email
execute_tool('email', 'send', {
  to: 'team@company.com',
  subject: 'Daily Report',
  body: 'Report content...',
  attachments: ['/tmp/report.pdf']
})

# Slack
execute_tool('slack', 'post_message', {
  channel: '#alerts',
  text: 'System alert: High CPU usage detected'
})

# SMS
execute_tool('sms', 'send', {
  to: '+1234567890',
  message: 'Alert: System down'
})
```

### Cloud Services

Interact with cloud platforms:

```ruby
# AWS S3
execute_tool('aws_s3', 'upload', {
  bucket: 'my-bucket',
  key: 'reports/daily.pdf',
  file_path: '/tmp/report.pdf'
})

# Google Cloud Storage  
execute_tool('gcs', 'download', {
  bucket: 'data-bucket',
  key: 'inputs/data.json',
  destination: '/tmp/data.json'
})
```

### Development Tools

Git, CI/CD, and development workflows:

```ruby
# GitHub operations
execute_tool('github', 'create_issue', {
  repo: 'company/project',
  title: 'Bug detected by monitoring agent',
  body: 'Details of the issue...',
  labels: ['bug', 'automated']
})

# Docker
execute_tool('docker', 'run', {
  image: 'nginx:latest',
  ports: ['80:80'],
  environment: { ENV: 'production' }
})
```

## Tool Configuration

### Automatic Tool Discovery

When you create an agent, Language Operator automatically:
1. Analyzes your agent description
2. Identifies needed tools
3. Configures appropriate tool access
4. Sets up authentication and permissions

### Manual Tool Configuration

For advanced use cases, you can specify tool requirements:

```bash
# During agent creation
langop agent create my-agent \
  --tools database,slack,github \
  --database-url postgres://... \
  --slack-token xoxb-... \
  --github-token ghp-...
```

### Environment Variables

Tools often use environment variables for configuration:

```bash
# Database connections
export DATABASE_URL="postgresql://user:pass@host:5432/db"
export REDIS_URL="redis://localhost:6379"

# API tokens  
export SLACK_TOKEN="xoxb-your-slack-token"
export GITHUB_TOKEN="ghp_your-github-token"
export OPENAI_API_KEY="sk-your-openai-key"

# AWS credentials
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
```

### Tool Discovery

Language Operator provides basic tool management commands:

```bash
# Deploy a tool server to your cluster
langop tool deploy ./path/to/tool

# Test tool connectivity
langop tool test my-tool

# View tool logs
langop tool logs my-tool
```

For available tools, check the `components/tool/examples/` directory in the repository.

## Error Handling

### Tool Failures

Agents handle tool failures gracefully:

```ruby
task :fetch_data_with_retry,
  inputs: { source: 'string' },
  outputs: { data: 'array' }
do |inputs|
  retries = 3
  
  begin
    data = execute_tool('api', 'fetch', { url: inputs[:source] })
    { data: data }
  rescue => e
    retries -= 1
    if retries > 0
      sleep(2)
      retry
    else
      { data: [], error: "Failed after 3 attempts: #{e.message}" }
    end
  end
end
```

### Validation

Tools validate parameters automatically:

```ruby
# This will fail validation if email format is invalid
execute_tool('email', 'send', {
  to: 'invalid-email',  # ❌ Will raise validation error
  subject: 'Test',
  body: 'Hello'
})
```

## Custom Tools

### Creating Tool Servers

You can create custom tool servers for specialized functionality:

```ruby
# In your custom tool server (see components/tool/examples/)
tool 'custom_analyzer' do
  description 'Analyzes custom data format'
  
  parameter 'data' do
    type :string
    required true
    description 'Raw data to analyze'
  end
  
  execute do |params|
    # Your custom analysis logic
    result = analyze_custom_format(params['data'])
    { analysis: result }
  end
end
```

### Registering Custom Tools

```bash
# Deploy your custom tool server
langop tool deploy ./my-custom-tools

# Register with Language Operator
langop tool register my-custom-tools \
  --endpoint https://my-tools.company.com
```

## Security and Permissions

### Tool Access Control

Language Operator provides fine-grained access control:

```yaml
# Agent tool permissions
apiVersion: languageoperator.io/v1alpha1
kind: Agent
metadata:
  name: my-agent
spec:
  tools:
    database:
      permissions: [read]
      tables: [users, orders]
    slack:
      permissions: [post_message]
      channels: [alerts, notifications]
    github:
      permissions: [read_issues, create_comments]
      repositories: [company/main-repo]
```

### Credential Management

Sensitive credentials are managed securely:
- Stored as Kubernetes secrets
- Automatically injected as environment variables
- Never logged or exposed in agent code
- Rotated automatically when possible

### Audit Logging

All tool usage is logged for security and debugging:

```bash
# View tool usage logs
langop agent logs my-agent --tools-only

# Audit specific tool usage
langop tool audit database --agent my-agent --since 24h
```

## Performance Optimization

### Tool Caching

Language Operator automatically caches tool results when appropriate:

```ruby
# This result may be cached for 5 minutes
execute_tool('external_api', 'fetch_static_data', {
  cache_ttl: 300
})
```

### Parallel Tool Execution

Execute multiple tools in parallel for better performance:

```ruby
main do |inputs|
  # Run multiple tool calls in parallel
  results = execute_parallel([
    { tool: 'database', action: 'fetch_users' },
    { tool: 'api', action: 'fetch_external_data' },
    { tool: 'redis', action: 'get_cache', params: { key: 'stats' } }
  ])
  
  # Process combined results
  process_combined_data(results)
end
```

## Best Practices

### Tool Selection
- Use specific tools rather than generic HTTP calls when available
- Prefer official tool implementations over custom ones
- Choose tools with good error handling and retry logic

### Error Handling
- Always handle tool failures gracefully
- Implement appropriate retry logic for transient failures
- Provide meaningful error messages for debugging

### Performance
- Cache expensive tool results when appropriate
- Use parallel execution for independent tool calls
- Monitor tool response times and optimize slow operations

### Security
- Use environment variables for sensitive configuration
- Follow principle of least privilege for tool permissions
- Regularly audit tool usage and access patterns

## Troubleshooting

### Tool Connection Issues

```bash
# Test tool connectivity
langop tool test database

# Check tool configuration
langop tool config database

# View tool logs
langop tool logs database --since 1h
```

### Common Issues

**Tool not found**: Check tool registration and spelling
**Authentication failed**: Verify credentials and permissions
**Timeout errors**: Check network connectivity and tool server status
**Validation errors**: Review parameter types and required fields

## Next Steps

- **[Agent Configuration](agent-configuration.md)** - Configure tool access and permissions
- **[Best Practices](best-practices.md)** - Patterns for reliable tool usage
- **[Custom Tools](custom-tools.md)** - Creating your own tool servers