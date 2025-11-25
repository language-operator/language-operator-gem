# Quickstart Guide

Get your first Language Operator agent running in 5 minutes.

## Before You Begin

- Install aictl: `gem install language-operator`
- Have Kubernetes cluster access
- Set up API keys for your preferred LLM provider

## Step 1: Initial Setup

Run the interactive setup wizard:

```bash
aictl quickstart
```

The wizard will guide you through:
1. Cluster configuration
2. Language Operator installation
3. Model setup (OpenAI, Anthropic, or local)
4. Creating your first agent

## Step 2: Manual Setup (Alternative)

If you prefer step-by-step setup:

### Configure Your Cluster

```bash
# Create cluster configuration
aictl cluster create my-cluster

# Switch to it
aictl use my-cluster

# Check connectivity
aictl status
```

### Install Language Operator

```bash
aictl install
```

Wait for installation to complete, then verify:

```bash
aictl status
```

### Create a Model

```bash
# For OpenAI (set OPENAI_API_KEY first)
aictl model create gpt4 --provider openai --model gpt-4-turbo

# For Anthropic (set ANTHROPIC_API_KEY first)  
aictl model create claude --provider anthropic --model claude-3-sonnet

# Verify model
aictl model list
```

## Step 3: Create Your First Agent

### Simple Scheduled Agent

Create an agent that runs daily:

```bash
aictl agent create daily-reporter
```

You'll be prompted to describe what the agent should do. Try:
> "Generate a daily summary of system status and send it via email"

### Check Agent Status

```bash
# List all agents
aictl agent list

# Get detailed info
aictl agent inspect daily-reporter

# View logs
aictl agent logs daily-reporter -f
```

## Step 4: Understanding What Was Created

### View Generated Code

```bash
# Open agent workspace
aictl agent workspace daily-reporter
```

This shows the synthesized agent definition that Language Operator created from your description.

### Example Generated Agent

```ruby
agent "daily-reporter" do
  description "Generate a daily summary of system status and send it via email"
  
  mode :scheduled
  schedule "0 8 * * *"  # 8 AM daily
  
  task :collect_system_status do |inputs|
    # AI-synthesized task to gather system information
    { status: "healthy", uptime: "99.9%", alerts: [] }
  end
  
  task :generate_report do |inputs|
    # AI-synthesized task to create report
    status = inputs[:status]
    { report: "Daily Status: #{status}" }
  end
  
  main do |inputs|
    status = collect_system_status
    report = generate_report(status)
    report
  end
  
  output do |outputs|
    # AI-synthesized output handling
    puts "Report generated: #{outputs[:report]}"
  end
  
  constraints do
    timeout "10m"
    daily_budget 100  # $1.00 max per day
  end
end
```

## Step 5: Experiment with Different Agent Types

### Webhook Agent

Create an agent that responds to GitHub webhooks:

```bash
aictl agent create github-responder
```

Description: "Respond to GitHub pull request webhooks with automated code reviews"

### Chat Agent  

Create a conversational agent:

```bash
aictl agent create support-bot
```

Description: "Provide customer support through a chat interface"

### Autonomous Agent

Create an agent that runs continuously:

```bash
aictl agent create system-monitor
```

Description: "Continuously monitor system health and alert on issues"

## Step 6: Monitor and Manage

### View All Agents

```bash
aictl agent list
```

### Check Agent Logs

```bash
# Follow logs in real-time
aictl agent logs daily-reporter -f

# View recent logs
aictl agent logs daily-reporter --since 1h
```

### Monitoring Agents

Monitor your agent's execution and performance:

```bash
# View detailed agent information
aictl agent inspect daily-reporter

# Check recent execution logs
aictl agent logs daily-reporter --since 1h
```

## Common Patterns

### Scheduled Reporting

```ruby
agent "weekly-metrics" do
  description "Generate weekly performance metrics"
  schedule "0 9 * * 1"  # Mondays at 9 AM
  
  # Tasks will be synthesized based on description
end
```

### Event Response

```ruby
agent "incident-responder" do  
  description "Respond to system incidents"
  mode :reactive
  
  webhook "/alerts/critical" do
    method :post
  end
end
```

### Continuous Monitoring

```ruby
agent "health-monitor" do
  description "Monitor application health continuously"
  mode :autonomous
  
  constraints do
    requests_per_minute 2
    daily_budget 500  # $5 max per day
  end
end
```

## Troubleshooting

### Agent Not Starting

```bash
# Check agent status
aictl agent inspect my-agent

# View detailed logs
aictl agent logs my-agent

# Check cluster status
aictl status
```

### High Costs

Agents use LLM APIs which have costs. Monitor usage:

```bash
# Check agent configuration
aictl agent inspect my-agent

# Look for budget constraints
# Adjust constraints if needed
```

### Connection Issues

```bash
# Test cluster connectivity
kubectl get nodes

# Check Language Operator status
kubectl get pods -n language-operator

# Verify model connectivity
aictl model test my-model
```

## Next Steps

Now that you have a working agent:

1. **[How Agents Work](how-agents-work.md)** - Understand the synthesis process
2. **[Understanding Generated Code](understanding-generated-code.md)** - Learn to read agent definitions
3. **[Using Tools](using-tools.md)** - Connect agents to external services
4. **[Constraints](constraints.md)** - Control costs and behavior
5. **[Best Practices](best-practices.md)** - Production deployment patterns

## Getting Help

- View command help: `aictl --help`
- Check specific commands: `aictl agent --help`
- Report issues: [GitHub Issues](https://github.com/language-operator/language-operator-gem/issues)
- Join discussions: [GitHub Discussions](https://github.com/language-operator/language-operator/discussions)