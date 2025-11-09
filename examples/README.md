# Agent DSL Examples

This directory contains complete, runnable examples demonstrating the Language Operator agent DSL.

## Table of Contents

- [Quick Start](#quick-start)
- [Example Files](#example-files)
- [Running Examples](#running-examples)
- [Example Categories](#example-categories)

## Quick Start

The fastest way to understand the agent DSL is to review these examples in order:

1. **[agent_example.rb](agent_example.rb)** - Basic scheduled agent
2. **[webhook_agent.rb](webhook_agent.rb)** - Simple webhook handler
3. **[mcp_agent.rb](mcp_agent.rb)** - MCP server with tools
4. **[chat_endpoint_agent.rb](chat_endpoint_agent.rb)** - Chat completion endpoint

## Example Files

### Basic Agents

#### [agent_example.rb](agent_example.rb)
**Type:** Scheduled agent
**Features:**
- Cron-based scheduling (`"0 9 * * *"` - daily at 9 AM)
- Persona definition
- Objectives list
- Simple workflow with tool usage
- Budget and timeout constraints

**Use case:** Daily reporting or scheduled maintenance tasks

```ruby
agent "daily-report-generator" do
  mode :scheduled
  schedule "0 9 * * *"

  workflow do
    step :generate_report do
      tool 'report_generator'
    end
  end
end
```

### Webhook Agents

#### [webhook_agent.rb](webhook_agent.rb)
**Type:** Reactive webhook handler
**Features:**
- Basic webhook endpoint configuration
- POST method handling
- Event processing
- Workflow triggered by webhook events

**Use case:** Simple webhook integrations

#### [github_webhook_agent.rb](github_webhook_agent.rb)
**Type:** GitHub webhook integration
**Features:**
- HMAC signature verification (GitHub style)
- X-Hub-Signature-256 authentication
- Pull request event filtering
- Multi-step workflow (fetch, analyze, comment)
- GitHub API integration

**Use case:** Automated code review, PR automation

**Key configuration:**
```ruby
webhook "/github/pull-request" do
  method :post
  authenticate do
    verify_signature(
      header: 'X-Hub-Signature-256',
      secret: ENV['GITHUB_WEBHOOK_SECRET'],
      algorithm: :sha256
    )
  end
end
```

#### [stripe_webhook_agent.rb](stripe_webhook_agent.rb)
**Type:** Stripe payment webhook handler
**Features:**
- Stripe-Signature verification
- Payment event processing
- Customer subscription handling
- Database integration
- Email notifications

**Use case:** Payment processing, subscription management

**Key configuration:**
```ruby
webhook "/stripe/events" do
  method :post
  authenticate do
    verify_signature(
      header: 'Stripe-Signature',
      secret: ENV['STRIPE_WEBHOOK_SECRET'],
      algorithm: :sha256
    )
  end
end
```

### MCP Integration

#### [mcp_agent.rb](mcp_agent.rb)
**Type:** MCP server (agent exposing tools)
**Features:**
- Tool definition DSL
- Parameter types (string, number, boolean)
- Parameter validation (required, regex, custom)
- Tool execution logic
- Error handling

**Use case:** Creating reusable tools for other agents

**Key features:**
```ruby
as_mcp_server do
  tool "process_data" do
    description "Process CSV data"

    parameter :csv_url do
      type :string
      required true
      validates :url
    end

    execute do |params|
      # Tool logic here
    end
  end
end
```

### Chat Endpoints

#### [chat_endpoint_agent.rb](chat_endpoint_agent.rb)
**Type:** OpenAI-compatible chat endpoint
**Features:**
- OpenAI SDK compatibility
- System prompt configuration
- Model parameters (temperature, max_tokens)
- Streaming support
- Chat completion API

**Use case:** Custom LLM endpoints, agent-as-service

**Key features:**
```ruby
as_chat_endpoint do
  system_prompt "You are a helpful technical expert"
  model 'my-agent-v1'
  temperature 0.7
  max_tokens 2000
end
```

**API usage:**
```bash
curl -X POST https://<agent-uuid>.webhooks.your-domain.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": false
  }'
```

## Running Examples

### Prerequisites

1. **Environment variables** - Ensure LLM credentials are set:
   ```bash
   export ANTHROPIC_API_KEY="your-key-here"
   export LLM_PROVIDER="anthropic"
   export LLM_MODEL="claude-3-5-sonnet-20241022"
   ```

2. **For webhook examples** - Set webhook secrets:
   ```bash
   export GITHUB_WEBHOOK_SECRET="your-github-secret"
   export STRIPE_WEBHOOK_SECRET="your-stripe-secret"
   ```

### Running Locally

#### Method 1: Direct Ruby Execution

```bash
# Set environment variables
export AGENT_CODE_PATH="examples/agent_example.rb"
export AGENT_NAME="daily-report-generator"
export AGENT_MODE="scheduled"

# Run the agent
ruby -Ilib -e "require 'language_operator'; LanguageOperator::Agent.run"
```

#### Method 2: Using aictl (via Kubernetes)

```bash
# Deploy to cluster
kubectl apply -f - <<EOF
apiVersion: language-operator.io/v1alpha1
kind: LanguageAgent
metadata:
  name: example-agent
spec:
  code: |
$(cat examples/agent_example.rb | sed 's/^/    /')
  models:
    - name: claude
EOF

# Check status
kubectl get languageagent example-agent

# View logs
kubectl logs -f deployment/example-agent
```

### Testing Webhook Examples

#### Test GitHub webhook locally:

```bash
# Start the agent (webhook receiver runs automatically)
bundle exec ruby -Ilib examples/github_webhook_agent.rb

# In another terminal, send test webhook
curl -X POST http://localhost:9393/github/pull-request \
  -H "X-Hub-Signature-256: sha256=<computed-signature>" \
  -H "X-GitHub-Event: pull_request" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "opened",
    "pull_request": {
      "number": 123,
      "title": "Test PR",
      "diff_url": "https://github.com/..."
    }
  }'
```

#### Computing HMAC signature for testing:

```ruby
require 'openssl'

secret = ENV['GITHUB_WEBHOOK_SECRET']
payload = '{"action":"opened",...}'
signature = 'sha256=' + OpenSSL::HMAC.hexdigest('SHA256', secret, payload)
puts signature
```

### Testing MCP Tools

```bash
# Start MCP server agent
bundle exec ruby -Ilib examples/mcp_agent.rb

# List available tools
curl -X POST http://localhost:9393/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'

# Call a tool
curl -X POST http://localhost:9393/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "process_data",
      "arguments": {"csv_url": "https://example.com/data.csv"}
    },
    "id": 2
  }'
```

### Testing Chat Endpoints

```bash
# Start chat endpoint agent
bundle exec ruby -Ilib examples/chat_endpoint_agent.rb

# Send chat completion request
curl -X POST http://localhost:9393/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "What is Kubernetes?"}
    ],
    "stream": false
  }'

# Test streaming
curl -X POST http://localhost:9393/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Explain containers"}
    ],
    "stream": true
  }'
```

## Example Categories

### By Execution Mode

**Autonomous Agents:**
- None currently (autonomous mode agents run continuously)

**Scheduled Agents:**
- [agent_example.rb](agent_example.rb) - Daily report generator

**Reactive Agents:**
- [webhook_agent.rb](webhook_agent.rb) - Basic webhook
- [github_webhook_agent.rb](github_webhook_agent.rb) - GitHub integration
- [stripe_webhook_agent.rb](stripe_webhook_agent.rb) - Stripe integration

### By Integration Type

**Webhooks:**
- [webhook_agent.rb](webhook_agent.rb)
- [github_webhook_agent.rb](github_webhook_agent.rb)
- [stripe_webhook_agent.rb](stripe_webhook_agent.rb)

**MCP Servers:**
- [mcp_agent.rb](mcp_agent.rb)

**Chat Endpoints:**
- [chat_endpoint_agent.rb](chat_endpoint_agent.rb)

### By Complexity

**Beginner:**
1. [agent_example.rb](agent_example.rb) - Start here
2. [webhook_agent.rb](webhook_agent.rb) - Basic webhook

**Intermediate:**
3. [mcp_agent.rb](mcp_agent.rb) - Tool definitions
4. [chat_endpoint_agent.rb](chat_endpoint_agent.rb) - Chat API

**Advanced:**
5. [github_webhook_agent.rb](github_webhook_agent.rb) - Full GitHub integration
6. [stripe_webhook_agent.rb](stripe_webhook_agent.rb) - Payment processing

## Common Patterns

### Pattern: Scheduled Report Generator

**When to use:** Daily/weekly reporting, batch processing

**Example:** [agent_example.rb](agent_example.rb)

**Key features:**
```ruby
mode :scheduled
schedule "0 9 * * *"  # Cron expression

workflow do
  step :gather_data do
    tool 'database_query'
  end

  step :analyze do
    depends_on :gather_data
    prompt "Analyze: {gather_data.output}"
  end

  step :distribute do
    depends_on :analyze
    tool 'send_email'
  end
end
```

### Pattern: Webhook Event Handler

**When to use:** External service integrations (GitHub, Stripe, Slack)

**Example:** [github_webhook_agent.rb](github_webhook_agent.rb)

**Key features:**
```ruby
mode :reactive

webhook "/events" do
  method :post
  authenticate { verify_signature(...) }
end

on_webhook_event do |event|
  # Process event
end
```

### Pattern: Tool Provider (MCP Server)

**When to use:** Reusable tools for multiple agents

**Example:** [mcp_agent.rb](mcp_agent.rb)

**Key features:**
```ruby
as_mcp_server do
  tool "my_tool" do
    parameter :input do
      type :string
      required true
    end

    execute do |params|
      # Tool logic
    end
  end
end
```

### Pattern: LLM Endpoint (Chat Completion)

**When to use:** Exposing agents as OpenAI-compatible APIs

**Example:** [chat_endpoint_agent.rb](chat_endpoint_agent.rb)

**Key features:**
```ruby
as_chat_endpoint do
  system_prompt "You are an expert..."
  temperature 0.7
  max_tokens 2000
end
```

## Customizing Examples

### Modify Schedules

Change cron expressions to adjust timing:

```ruby
schedule "0 9 * * *"     # Daily at 9 AM
schedule "0 */4 * * *"   # Every 4 hours
schedule "0 9 * * 1"     # Every Monday at 9 AM
schedule "*/15 * * * *"  # Every 15 minutes
```

### Add Constraints

Control costs and resource usage:

```ruby
constraints do
  timeout '30m'
  daily_budget 1000        # $10/day
  requests_per_minute 10
  blocked_topics ['spam']
end
```

### Customize Personas

Adjust agent behavior and expertise:

```ruby
persona <<~PERSONA
  You are a [role] specializing in [domain].

  Your expertise includes:
  - [skill 1]
  - [skill 2]

  When responding:
  - [guideline 1]
  - [guideline 2]
PERSONA
```

## Next Steps

After reviewing these examples:

1. **Read the comprehensive guides:**
   - [Agent Reference](../docs/dsl/agent-reference.md) - Complete DSL syntax
   - [Workflows](../docs/dsl/workflows.md) - Workflow patterns
   - [Constraints](../docs/dsl/constraints.md) - Resource limits
   - [Webhooks](../docs/dsl/webhooks.md) - Webhook configuration
   - [MCP Integration](../docs/dsl/mcp-integration.md) - Tool definitions
   - [Chat Endpoints](../docs/dsl/chat-endpoints.md) - Chat APIs
   - [Best Practices](../docs/dsl/best-practices.md) - Production patterns

2. **Create your own agent:**
   - Copy an example that matches your use case
   - Customize persona, schedule, and workflow
   - Test locally first
   - Deploy to Kubernetes when ready

3. **Join the community:**
   - Report issues on GitHub
   - Share your agent examples
   - Contribute improvements

## Troubleshooting

### Agent won't start

Check environment variables:
```bash
echo $ANTHROPIC_API_KEY
echo $LLM_PROVIDER
echo $LLM_MODEL
```

### Webhook authentication fails

Verify secret matches:
```bash
echo $GITHUB_WEBHOOK_SECRET
```

Compute expected signature manually to debug.

### Tool execution errors

Check tool implementation:
- Parameters match schema
- Execute block returns valid data
- Error handling is present

### Chat endpoint not responding

Verify endpoint is accessible:
```bash
curl http://localhost:9393/v1/models
```

## Additional Resources

- **Documentation:** [/docs/dsl/](../docs/dsl/)
- **Main README:** [../README.md](../README.md)
- **Spec Files:** [/spec/langop/dsl/](../spec/langop/dsl/) - More usage examples
- **CLI Wizard:** `aictl agent wizard` - Interactive agent creation

## Contributing Examples

Have a useful agent pattern? Contribute it!

1. Create a new example file
2. Follow the existing format
3. Add comprehensive comments
4. Update this README
5. Submit a pull request

Good examples to contribute:
- Slack bot integrations
- Data pipeline agents
- Monitoring and alerting agents
- Custom MCP tools
- Domain-specific agents (legal, financial, medical, etc.)
