# Ruby SDK for Language Operator

This gem translates a high-level DSL into language operator components.

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