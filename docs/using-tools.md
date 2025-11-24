# Using Tools

Language Operator agents can interact with external services, APIs, databases, and other tools. This guide shows how agents use tools and how to configure tool access.

## How Tools Work

When you describe an agent that needs to interact with external systems, Language Operator automatically configures tool access. Agents use tools through simple function calls.

### Tool Examples

Common tools agents use:
- **Database tools**: Query databases, run SQL, manage data
- **API tools**: Call REST APIs, GraphQL endpoints, webhooks
- **File tools**: Read/write files, process documents
- **Communication tools**: Send emails, Slack messages, notifications  
- **Cloud tools**: AWS S3, Google Cloud, Azure services
- **Git tools**: GitHub, GitLab operations

## Using Tools in Agents

### Neural Tasks (AI-Powered)

When you describe what an agent should do, Language Operator figures out which tools to use:

```ruby
task :fetch_user_orders,
  instructions: "get all orders for the user from the database",
  inputs: { user_id: 'integer' },
  outputs: { orders: 'array' }

# Language Operator will:
# 1. Identify that this needs database access
# 2. Use the appropriate database tool
# 3. Construct the right query
# 4. Return the results in the expected format
```

### Symbolic Tasks (Optimized)

After learning, tasks use tools directly:

```ruby
task :fetch_user_orders,
  inputs: { user_id: 'integer' },
  outputs: { orders: 'array' }
do |inputs|
  orders = execute_tool('database', 'query', {
    table: 'orders',
    where: { user_id: inputs[:user_id] },
    order: 'created_at DESC'
  })
  
  { orders: orders }
end
```

## Tool Categories

### Database Tools

Connect to SQL and NoSQL databases:

```ruby
# SQL databases
execute_tool('database', 'query', {
  sql: 'SELECT * FROM users WHERE active = ?',
  params: [true]
})

# MongoDB
execute_tool('mongodb', 'find', {
  collection: 'users',
  filter: { active: true }
})

# Redis
execute_tool('redis', 'get', {
  key: 'user:123'
})
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
aictl agent create my-agent \
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

See what tools are available to your agents:

```bash
# List all available tools
aictl tool list

# Search for specific tools
aictl tool search database

# Get tool documentation
aictl tool info database
```

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
aictl tool deploy ./my-custom-tools

# Register with Language Operator
aictl tool register my-custom-tools \
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
aictl agent logs my-agent --tools-only

# Audit specific tool usage
aictl tool audit database --agent my-agent --since 24h
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
aictl tool test database

# Check tool configuration
aictl tool config database

# View tool logs
aictl tool logs database --since 1h
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