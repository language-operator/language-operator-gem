# Agent DSL Reference

Complete reference guide for the Language Operator agent DSL.

## Table of Contents

- [Schema Version](#schema-version)
- [Agent Definition](#agent-definition)
- [Execution Modes](#execution-modes)
- [Schedule Configuration](#schedule-configuration)
- [Objectives](#objectives)
- [Persona](#persona)
- [Workflows](#workflows)
- [Constraints](#constraints)
- [Output Configuration](#output-configuration)
- [Complete Examples](#complete-examples)

## Schema Version

The Language Operator DSL schema is versioned using semantic versioning. The schema version is identical to the gem version.

**Access schema version:**

```ruby
LanguageOperator::Dsl::Schema.version  # => "0.1.30"
```

For detailed information about schema versioning policy, version semantics, and compatibility, see [Schema Versioning Policy](./SCHEMA_VERSION.md).

## Agent Definition

The basic structure of an agent definition:

```ruby
agent "agent-name" do
  description "What this agent does"

  mode :autonomous  # or :scheduled, :reactive

  # Additional configuration...
end
```

### Required Fields

- **name** (String): Unique identifier for the agent (passed as argument to `agent`)
- **description** (String): Human-readable description of the agent's purpose

### Optional Fields

- **mode** (Symbol): Execution mode (`:autonomous`, `:scheduled`, `:reactive`) - defaults to `:autonomous`
- **persona** (String): System prompt defining the agent's behavior and expertise
- **schedule** (String): Cron expression for scheduled execution (only used when `mode: :scheduled`)
- **objectives** (Array): List of goals the agent should accomplish
- **workflow** (Block): Step-by-step workflow definition
- **constraints** (Block): Resource and behavior limits
- **output** (Block): Output formatting and delivery configuration

## Execution Modes

Agents support three execution modes:

### Autonomous Mode

Continuous execution with objectives-based behavior.

```ruby
agent "autonomous-researcher" do
  description "Continuously researches and reports on tech trends"

  mode :autonomous

  objectives [
    "Monitor technology news sources",
    "Identify emerging trends",
    "Generate weekly summaries"
  ]

  # Agent runs continuously, guided by objectives
end
```

**Use cases:**
- Monitoring and alerting
- Continuous data processing
- Real-time analysis

### Scheduled Mode

Executes on a defined schedule using cron expressions.

```ruby
agent "daily-reporter" do
  description "Generate daily reports"

  mode :scheduled
  schedule "0 9 * * *"  # 9 AM every day

  workflow do
    # Define workflow steps
  end
end
```

**Cron Expression Format:**
```
┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of month (1 - 31)
│ │ │ ┌───────────── month (1 - 12)
│ │ │ │ ┌───────────── day of week (0 - 6) (Sunday to Saturday)
│ │ │ │ │
* * * * *
```

**Common Examples:**
- `"0 9 * * *"` - Daily at 9 AM
- `"0 */4 * * *"` - Every 4 hours
- `"0 9 * * 1"` - Every Monday at 9 AM
- `"0 0 1 * *"` - First day of every month at midnight
- `"*/15 * * * *"` - Every 15 minutes

**Use cases:**
- Daily/weekly reporting
- Scheduled maintenance tasks
- Periodic data synchronization

### Reactive Mode

Responds to external events (webhooks, triggers).

```ruby
agent "github-pr-reviewer" do
  description "Reviews pull requests when opened"

  mode :reactive

  # Webhook configuration required (see webhooks.md)
  webhook "/github/pr-opened" do
    method :post
    # Authentication and handling...
  end

  on_webhook_event do |event|
    # Process the webhook event
  end
end
```

**Use cases:**
- Webhook handlers (GitHub, Stripe, etc.)
- Event-driven workflows
- Integration with external systems

## Schedule Configuration

For scheduled agents, you can configure execution timing.

### Cron Expressions

```ruby
agent "scheduled-agent" do
  mode :scheduled
  schedule "0 */2 * * *"  # Every 2 hours
end
```

### Natural Language Helpers

While the DSL accepts cron expressions directly, the CLI includes helpers for natural language time parsing:

```bash
# CLI supports natural language (converts to cron internally)
aictl agent wizard
# Prompts: "What time should this run?"
# Input: "4pm daily"
# Converts to: "0 16 * * *"
```

### Future: Event-Based Triggers

Event-based scheduling is planned but not yet implemented:

```ruby
# FUTURE FEATURE - Not yet available
agent "event-driven" do
  mode :scheduled

  trigger :on_event do
    source "kubernetes"
    event_type "pod.failed"
  end
end
```

## Objectives

Objectives guide the agent's behavior, especially in autonomous mode.

### Single Objective

```ruby
agent "simple-agent" do
  objective "Monitor system health and alert on issues"
end
```

### Multiple Objectives

```ruby
agent "multi-objective-agent" do
  objectives [
    "Collect daily metrics from all services",
    "Analyze metrics for anomalies",
    "Generate summary reports",
    "Alert on critical issues"
  ]
end
```

### Best Practices

**Good Objectives:**
- Specific and actionable
- Measurable outcomes
- Clear success criteria

```ruby
objectives [
  "Fetch sales data from Salesforce API every hour",
  "Calculate conversion rates by product category",
  "Email report to team@company.com if conversion drops below 5%"
]
```

**Poor Objectives:**
- Too vague
- Unmeasurable
- No clear completion criteria

```ruby
# Avoid this:
objectives [
  "Be helpful",
  "Do good work",
  "Monitor things"
]
```

## Persona

The persona defines the agent's system prompt, expertise, and behavioral characteristics.

### Basic Persona

```ruby
agent "support-agent" do
  persona "You are a helpful customer support agent specializing in technical troubleshooting"
end
```

### Detailed Persona

```ruby
agent "kubernetes-expert" do
  persona <<~PERSONA
    You are a Kubernetes expert with deep knowledge of:
    - Cluster administration and troubleshooting
    - Workload optimization and best practices
    - Security and RBAC configuration
    - Monitoring and observability

    When helping users:
    - Provide clear, step-by-step guidance
    - Include relevant kubectl commands
    - Explain the reasoning behind recommendations
    - Always consider security implications

    Your responses should be concise but complete.
  PERSONA
end
```

### Persona with Role and Constraints

```ruby
agent "financial-analyst" do
  persona <<~PERSONA
    You are a financial analyst specializing in quarterly earnings analysis.

    Your expertise includes:
    - Reading and interpreting 10-Q and 10-K filings
    - Calculating key financial ratios
    - Identifying trends and anomalies

    Guidelines:
    - Base all analysis on factual data from SEC filings
    - Clearly distinguish between facts and interpretations
    - Use industry-standard financial terminology
    - Never provide investment advice
  PERSONA
end
```

### Best Practices

- **Be specific** about the agent's expertise domain
- **Include behavioral guidelines** for how the agent should respond
- **Set boundaries** on what the agent should/shouldn't do
- **Define tone and style** appropriate for the use case

## Workflows

See [workflows.md](workflows.md) for complete workflow documentation.

Quick example:

```ruby
agent "data-processor" do
  workflow do
    step :fetch_data do
      tool 'database_query'
      params query: 'SELECT * FROM metrics WHERE date = CURRENT_DATE'
    end

    step :analyze do
      depends_on :fetch_data
      prompt "Analyze this data: {fetch_data.output}"
    end

    step :report do
      depends_on :analyze
      tool 'send_email'
      params(
        to: 'team@company.com',
        subject: 'Daily Analysis',
        body: '{analyze.output}'
      )
    end
  end
end
```

## Constraints

See [constraints.md](constraints.md) for complete constraints documentation.

Quick example:

```ruby
agent "resource-limited-agent" do
  constraints do
    timeout '30m'
    max_iterations 50

    daily_budget 1000  # Max daily cost in cents
    requests_per_minute 10

    blocked_topics ['violence', 'illegal-content']
  end
end
```

## Output Configuration

Configure how the agent formats and delivers output.

### Format

```ruby
agent "reporting-agent" do
  output do
    format :json  # or :text, :markdown, :html
  end
end
```

### Delivery

```ruby
agent "alert-agent" do
  output do
    deliver_to 'team@company.com'
    format :markdown
  end
end
```

## Complete Examples

### Scheduled Report Generator

```ruby
agent "weekly-sales-report" do
  description "Generate weekly sales analysis reports"

  mode :scheduled
  schedule "0 9 * * 1"  # Every Monday at 9 AM

  persona <<~PERSONA
    You are a sales analyst who creates clear, actionable reports.
    Focus on trends, anomalies, and actionable insights.
  PERSONA

  objectives [
    "Fetch sales data for the past week",
    "Calculate key metrics (revenue, conversion, avg order value)",
    "Identify top performing products and regions",
    "Highlight any concerning trends",
    "Generate executive summary"
  ]

  workflow do
    step :fetch_sales_data do
      tool 'database_query'
      params(
        query: "SELECT * FROM sales WHERE date >= CURRENT_DATE - INTERVAL '7 days'"
      )
    end

    step :analyze_trends do
      depends_on :fetch_sales_data
      prompt "Analyze these sales figures and identify key trends: {fetch_sales_data.output}"
    end

    step :send_report do
      depends_on :analyze_trends
      tool 'send_email'
      params(
        to: 'executives@company.com',
        subject: 'Weekly Sales Report',
        body: '{analyze_trends.output}'
      )
    end
  end

  constraints do
    timeout '15m'
    max_iterations 10
    daily_budget 500  # 500 cents = $5
  end

  output do
    format :markdown
  end
end
```

### Autonomous Monitoring Agent

```ruby
agent "system-health-monitor" do
  description "Continuously monitors system health and alerts on issues"

  mode :autonomous

  persona <<~PERSONA
    You are a site reliability engineer monitoring production systems.
    You are proactive, detail-oriented, and know when to escalate issues.
  PERSONA

  objectives [
    "Check system metrics every 5 minutes",
    "Identify anomalies (CPU >80%, memory >90%, disk >85%)",
    "Check application error rates",
    "Alert team immediately if critical issues detected",
    "Generate hourly summary reports"
  ]

  constraints do
    requests_per_minute 12  # Every 5 minutes = 12/hour
    daily_budget 2000  # $20/day

    blocked_patterns []  # No content filtering needed
  end
end
```

### Reactive Webhook Handler

```ruby
agent "github-pr-reviewer" do
  description "Automatically reviews pull requests"

  mode :reactive

  persona <<~PERSONA
    You are a senior software engineer conducting code reviews.
    Focus on: correctness, security, performance, and maintainability.
    Be constructive and specific in feedback.
  PERSONA

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

  on_webhook_event do |event|
    # Extract PR details from event
    pr_number = event.dig('pull_request', 'number')
    pr_diff = event.dig('pull_request', 'diff_url')

    # Review workflow executes when webhook received
  end

  workflow do
    step :fetch_diff do
      tool 'http_get'
      params url: '{event.pull_request.diff_url}'
    end

    step :review_code do
      depends_on :fetch_diff
      prompt "Review this code change and provide feedback: {fetch_diff.output}"
    end

    step :post_comment do
      depends_on :review_code
      tool 'github_api'
      params(
        action: 'create_comment',
        issue_number: '{event.pull_request.number}',
        body: '{review_code.output}'
      )
    end
  end

  constraints do
    timeout '10m'
    requests_per_hour 100  # Rate limit webhook processing
  end
end
```

## Environment Variables

Agents access configuration through environment variables injected by the operator:

### LLM Configuration

- `LLM_PROVIDER` - Provider name (default: `'anthropic'`)
- `LLM_MODEL` - Model name (default: `'claude-3-5-sonnet-20241022'`)
- `ANTHROPIC_API_KEY` - API key for Anthropic
- `OPENAI_API_KEY` - API key for OpenAI (if using OpenAI provider)

### Runtime Configuration

- `AGENT_NAME` - Name of this agent instance
- `AGENT_CODE_PATH` - Path to synthesized agent code (usually `/config/agent.rb`)
- `AGENT_MODE` - Execution mode (`autonomous`, `scheduled`, `reactive`)
- `CONFIG_PATH` - Path to YAML configuration file
- `WORKSPACE_PATH` - Path to persistent workspace directory

### Tool/MCP Configuration

- `MODEL_ENDPOINTS` - Comma-separated list of LLM endpoint URLs
- `MCP_SERVERS` - Comma-separated list of MCP tool server endpoints
- `TOOL_ENDPOINTS` - (Alternative name for MCP_SERVERS)

### Example Pod Environment

```yaml
env:
  - name: AGENT_NAME
    value: "weekly-sales-report"
  - name: AGENT_CODE_PATH
    value: "/config/agent.rb"
  - name: AGENT_MODE
    value: "scheduled"
  - name: LLM_PROVIDER
    value: "anthropic"
  - name: LLM_MODEL
    value: "claude-3-5-sonnet-20241022"
  - name: ANTHROPIC_API_KEY
    valueFrom:
      secretKeyRef:
        name: llm-credentials
        key: anthropic-api-key
  - name: WORKSPACE_PATH
    value: "/workspace"
```

## Next Steps

- Learn about [Workflows](workflows.md) for step-by-step task execution
- Understand [Constraints](constraints.md) for resource and behavior limits
- Explore [Webhooks](webhooks.md) for reactive agents
- Review [Best Practices](best-practices.md) for production deployments

## See Also

- [Workflow Guide](workflows.md)
- [Constraints Reference](constraints.md)
- [Webhook Guide](webhooks.md)
- [MCP Integration](mcp-integration.md)
- [Chat Endpoints](chat-endpoints.md)
- [Best Practices](best-practices.md)
