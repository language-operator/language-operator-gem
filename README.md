# Ruby SDK for Language Operator

[![Gem Version](https://img.shields.io/gem/v/language-operator.svg)](https://rubygems.org/gems/language-operator)

This gem translates a high-level DSL into language operator components.

## Installation

Install the gem from RubyGems.org:

```bash
gem install language-operator
```

Or add it to your Gemfile:

```ruby
gem 'language-operator'
```

Then run:

```bash
bundle install
```

## Quick Start

### Deploy an Agent

```bash
# 1. Create a language cluster
aictl cluster create my-cluster

# 2. Create a language model
aictl model create gpt4 --provider openai --model gpt-4-turbo

# 3. Create a tool (if needed)
# Tools are typically installed from registries or created via custom MCP servers
# Example: aictl tool install filesystem

# 4. Create an agent
aictl agent create "Monitor my GitHub repos and summarize daily activity" \
  --models gpt4 \
  --name github-monitor
```

## Tools

```ruby
require 'langop'

tool "send_email" do
  description "Send an email via SMTP"

  parameter "to" do
    type :string
    required true
    description "Recipient email address (comma-separated for multiple recipients)"
  end

  parameter "subject" do
    type :string
    required true
    description "Email subject line"
  end

  parameter "body" do
    type :string
    required true
    description "Email body content (plain text or HTML)"
  end

  parameter "from" do
    type :string
    required false
    description "Sender email address (defaults to SMTP_FROM env variable)"
  end

  parameter "cc" do
    type :string
    required false
    description "CC email addresses (comma-separated)"
  end

  parameter "bcc" do
    type :string
    required false
    description "BCC email addresses (comma-separated)"
  end

  parameter "html" do
    type :boolean
    required false
    description "Send as HTML email (default: false)"
    default false
  end

  execute do |params|
    # ...implementation of tool
  end
end


## Agents

```ruby
require 'langop'

agent "demo" do
end
```

## Documentation

### Agent DSL Reference

Complete guides for the agent DSL:

- **[Agent Reference](docs/dsl/agent-reference.md)** - Complete agent DSL syntax, execution modes, schedules, objectives, personas
- **[Workflows](docs/dsl/workflows.md)** - Step-by-step workflow definition, dependencies, parameter passing, error handling
- **[Constraints](docs/dsl/constraints.md)** - Time limits, budgets, rate limiting, content filtering
- **[Webhooks](docs/dsl/webhooks.md)** - Webhook configuration, authentication methods, event handling
- **[MCP Integration](docs/dsl/mcp-integration.md)** - MCP server tools, parameter validation, tool execution
- **[Chat Endpoints](docs/dsl/chat-endpoints.md)** - OpenAI-compatible chat completion endpoints
- **[Best Practices](docs/dsl/best-practices.md)** - Production patterns, security, performance, cost optimization

### Architecture

- [Agent Runtime Architecture](docs/architecture/agent-runtime.md) - How synthesized code loads and executes in agent pods

### Examples

All examples include complete, runnable code with detailed comments:

- **[Examples Overview](examples/README.md)** - Guide to all example files with running instructions
- [Agent Example](examples/agent_example.rb) - Scheduled agent with workflow
- [Webhook Agent](examples/webhook_agent.rb) - Basic webhook handler
- [GitHub Webhook](examples/github_webhook_agent.rb) - GitHub PR reviewer with HMAC auth
- [Stripe Webhook](examples/stripe_webhook_agent.rb) - Payment event processor
- [MCP Agent](examples/mcp_agent.rb) - Agent exposing tools via MCP
- [Chat Endpoint](examples/chat_endpoint_agent.rb) - OpenAI-compatible chat API