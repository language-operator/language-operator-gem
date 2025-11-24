# Agent Constraints Reference

Complete reference for configuring agent constraints to control behavior, resource usage, and costs.

## Table of Contents

- [Overview](#overview)
- [Time Constraints](#time-constraints)
- [Resource Constraints](#resource-constraints)
- [Budget Constraints](#budget-constraints)
- [Rate Limiting](#rate-limiting)
- [Content Filtering](#content-filtering)
- [Complete Examples](#complete-examples)

## Overview

Constraints define limits on agent behavior and resource usage. They help:
- Prevent runaway costs
- Enforce rate limits
- Block inappropriate content
- Manage resource consumption
- Ensure timely execution

Define constraints in an agent's `constraints` block:

```ruby
agent "my-agent" do
  constraints do
    timeout '30m'
    daily_budget 1000
    requests_per_minute 10
  end
end
```

## Time Constraints

### Timeout

Maximum execution time for the entire agent workflow or autonomous loop iteration.

```ruby
constraints do
  timeout '30m'  # 30 minutes
end
```

**Format:**
- `'5m'` - 5 minutes
- `'2h'` - 2 hours
- `'30s'` - 30 seconds
- `'1h30m'` - 1 hour 30 minutes

**Default:** No timeout (runs indefinitely)

**Use cases:**
- Prevent hung workflows
- Enforce SLA requirements
- Manage computational costs

**Example:**

```ruby
agent "time-sensitive-reporter" do
  constraints do
    timeout '15m'  # Must complete within 15 minutes
  end

  workflow do
    step :fetch_data do
      tool 'slow_database_query'
      timeout '5m'  # Step-level timeout
    end

    step :analyze do
      prompt "Analyze: {fetch_data.output}"
      # Inherits remaining agent timeout
    end
  end
end
```

### Max Iterations

Maximum number of iterations for autonomous agents or workflow loops.

```ruby
constraints do
  max_iterations 100
end
```

**Default:** No limit

**Use cases:**
- Prevent infinite loops
- Control cost in autonomous mode
- Enforce bounded execution

**Example:**

```ruby
agent "bounded-monitor" do
  mode :autonomous

  constraints do
    max_iterations 50  # Stop after 50 checks
  end

  objectives [
    "Check system status every 5 minutes",
    "Alert if issues found"
  ]
end
```

## Resource Constraints

### Memory Limit

Maximum memory the agent process can use.

```ruby
constraints do
  memory '2Gi'  # 2 Gigabytes
end
```

**Format:**
- `'512Mi'` - 512 Megabytes
- `'2Gi'` - 2 Gigabytes
- `'100Mi'` - 100 Megabytes

**Default:** No memory limit (uses container/pod limits)

**Note:** This sets a soft limit. The Kubernetes pod should have matching resource limits.

**Example:**

```ruby
agent "memory-intensive-processor" do
  constraints do
    memory '4Gi'  # Allow up to 4GB
    timeout '1h'
  end

  workflow do
    step :process_large_dataset do
      tool 'data_processor'
      # May use significant memory
    end
  end
end
```

## Budget Constraints

Control costs by limiting LLM API spending.

### Daily Budget

Maximum spending per day (in cents).

```ruby
constraints do
  daily_budget 1000  # $10.00 per day
end
```

**Units:** Cents (100 = $1.00)

**Behavior:**
- Agent stops when daily budget exceeded
- Budget resets at midnight UTC
- Tracked across all LLM calls

### Hourly Budget

Maximum spending per hour (in cents).

```ruby
constraints do
  hourly_budget 100  # $1.00 per hour
end
```

**Units:** Cents

**Behavior:**
- Agent pauses when hourly budget exceeded
- Resumes at the next hour
- Useful for rate-limiting expensive operations

### Token Budget

Maximum tokens to consume (input + output combined).

```ruby
constraints do
  token_budget 100000  # 100k tokens max
end
```

**Units:** Tokens

**Behavior:**
- Tracks total tokens across all LLM calls
- Stops when budget exhausted
- Resets based on agent schedule

### Combined Budget Constraints

```ruby
agent "cost-controlled-agent" do
  constraints do
    daily_budget 2000    # $20/day maximum
    hourly_budget 200    # $2/hour maximum
    token_budget 500000  # 500k tokens maximum per day
  end

  # Agent will stop if ANY limit is reached
end
```

**Example:**

```ruby
agent "budget-conscious-analyst" do
  description "Analyze data within strict budget limits"

  mode :scheduled
  schedule "0 9 * * *"  # Daily at 9 AM

  constraints do
    timeout '30m'
    daily_budget 500      # $5/day max
    token_budget 100000   # 100k tokens max
  end

  workflow do
    step :analyze do
      prompt "Provide a concise analysis of today's sales data"
      # Encouraged to be brief due to token budget
    end
  end
end
```

## Rate Limiting

Control request frequency to prevent abuse and manage costs.

### Requests Per Minute

```ruby
constraints do
  requests_per_minute 10  # Max 10 LLM calls per minute
end
```

**Behavior:**
- Enforced across all LLM API calls
- Agent pauses if limit exceeded
- Useful for staying within API quotas

### Requests Per Hour

```ruby
constraints do
  requests_per_hour 100  # Max 100 LLM calls per hour
end
```

### Requests Per Day

```ruby
constraints do
  requests_per_day 1000  # Max 1000 LLM calls per day
end
```

### Rate Limit (Generic)

Alternative syntax for any time period:

```ruby
constraints do
  rate_limit requests: 60, period: '1h'  # 60 requests per hour
end
```

### Combined Rate Limits

```ruby
agent "rate-limited-agent" do
  constraints do
    requests_per_minute 5    # Burst protection
    requests_per_hour 200    # Hourly cap
    requests_per_day 2000    # Daily cap
  end

  # Agent respects all limits (most restrictive applies)
end
```

**Example:**

```ruby
agent "monitoring-agent" do
  mode :autonomous

  constraints do
    requests_per_minute 2   # Check every 30 seconds max
    requests_per_day 2880   # 2 per minute * 60 min * 24 hr
    daily_budget 500        # $5/day budget
  end

  objectives [
    "Monitor system health continuously",
    "Alert on anomalies"
  ]
end
```

## Content Filtering

Block or filter inappropriate content and topics.

### Blocked Topics

Prevent the agent from processing certain topics:

```ruby
constraints do
  blocked_topics ['violence', 'illegal-activity', 'adult-content']
end
```

**Behavior:**
- Agent rejects requests containing blocked topics
- Content moderation applied to inputs and outputs
- Logged for audit purposes

### Blocked Patterns

Block content matching regex patterns:

```ruby
constraints do
  blocked_patterns [
    /\b\d{3}-\d{2}-\d{4}\b/,  # SSN pattern
    /\b\d{16}\b/,              # Credit card number
    /password\s*[:=]/i         # Password disclosure
  ]
end
```

**Behavior:**
- Regex matched against all inputs and outputs
- Request rejected if pattern found
- Helps prevent data leakage

### Combined Content Filtering

```ruby
agent "safe-agent" do
  constraints do
    blocked_topics [
      'violence',
      'hate-speech',
      'illegal-activity',
      'self-harm'
    ]

    blocked_patterns [
      /\b\d{3}-\d{2}-\d{4}\b/,           # SSN
      /\b\d{16}\b/,                       # Credit card
      /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i  # Email addresses
    ]
  end
end
```

**Example:**

```ruby
agent "customer-service-agent" do
  description "Safe customer service assistant"

  mode :reactive

  persona <<~PERSONA
    You are a helpful customer service representative.
    Always maintain a professional and respectful tone.
  PERSONA

  constraints do
    # Safety constraints
    blocked_topics [
      'violence',
      'hate-speech',
      'illegal-activity'
    ]

    # PII protection
    blocked_patterns [
      /\b\d{3}-\d{2}-\d{4}\b/,  # SSN
      /\b\d{16}\b/,              # Credit card
    ]

    # Rate limiting
    requests_per_minute 30
    requests_per_hour 500

    # Budget
    hourly_budget 100  # $1/hour
    daily_budget 1000  # $10/day

    # Time limits
    timeout '5m'
  end
end
```

## Complete Examples

### Production ETL Agent

```ruby
agent "production-etl" do
  description "Production-grade ETL with comprehensive constraints"

  mode :scheduled
  schedule "0 2 * * *"  # 2 AM daily

  constraints do
    # Time constraints
    timeout '2h'           # Must complete within 2 hours
    max_iterations 10      # Max 10 retry attempts

    # Resource constraints
    memory '8Gi'          # Allow 8GB memory for large datasets

    # Budget constraints
    daily_budget 2000     # $20/day maximum
    token_budget 1000000  # 1M tokens max

    # Rate limiting (avoid API throttling)
    requests_per_minute 30
    requests_per_hour 1000

    # Content filtering
    blocked_patterns [
      /\b\d{3}-\d{2}-\d{4}\b/,  # Prevent SSN in logs
      /password\s*[:=]/i         # Prevent password leakage
    ]
  end

  workflow do
    step :extract do
      tool 'database_extract'
      timeout '30m'  # Step-level timeout
    end

    step :transform do
      depends_on :extract
      tool 'data_transform'
      timeout '45m'
    end

    step :load do
      depends_on :transform
      tool 'warehouse_load'
      timeout '30m'
      retry_on_failure max_attempts: 3
    end
  end
end
```

### Cost-Optimized Analysis Agent

```ruby
agent "frugal-analyst" do
  description "Cost-optimized analysis with strict budgets"

  mode :scheduled
  schedule "0 9 * * 1-5"  # Weekdays at 9 AM

  constraints do
    # Aggressive budget controls
    daily_budget 100        # Only $1/day
    hourly_budget 50        # $0.50/hour
    token_budget 50000      # 50k tokens max

    # Rate limits to spread requests
    requests_per_minute 2   # Slow and steady
    requests_per_hour 60

    # Reasonable timeout
    timeout '30m'
  end

  workflow do
    step :analyze do
      prompt "Provide a BRIEF analysis (under 200 words) of today's key metrics"
      # Prompt emphasizes brevity to save tokens
    end

    step :distribute do
      depends_on :analyze
      tool 'send_email'
      params(
        to: 'team@company.com',
        subject: 'Daily Brief',
        body: '{analyze.output}'
      )
    end
  end
end
```

### High-Throughput Webhook Handler

```ruby
agent "webhook-processor" do
  description "Handle high-volume webhook events"

  mode :reactive

  webhook "/api/events" do
    method :post
    authenticate { verify_api_key }
  end

  constraints do
    # High throughput settings
    requests_per_minute 120   # 2/second burst
    requests_per_hour 5000    # 83/minute sustained
    requests_per_day 50000    # Room for spikes

    # Generous budget for high volume
    hourly_budget 500    # $5/hour
    daily_budget 10000   # $100/day

    # Quick timeout per event
    timeout '30s'  # Process each event fast

    # Memory for concurrent processing
    memory '4Gi'

    # Safety
    blocked_topics ['spam', 'malicious-content']
  end

  on_webhook_event do |event|
    # Process event quickly within 30s timeout
  end
end
```

### Secure Customer Data Agent

```ruby
agent "secure-data-processor" do
  description "Process customer data with strong PII protection"

  mode :scheduled
  schedule "0 0 * * *"  # Midnight daily

  constraints do
    # Time and resource limits
    timeout '1h'
    memory '4Gi'

    # Budget
    daily_budget 1000  # $10/day

    # Comprehensive PII filtering
    blocked_patterns [
      # SSN
      /\b\d{3}-\d{2}-\d{4}\b/,
      # Credit card
      /\b(?:\d{4}[-\s]?){3}\d{4}\b/,
      # Phone numbers
      /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,
      # Email addresses
      /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
      # IP addresses
      /\b(?:\d{1,3}\.){3}\d{1,3}\b/,
      # API keys (common formats)
      /\b[A-Za-z0-9_-]{32,}\b/
    ]

    # Sensitive topics
    blocked_topics [
      'medical-records',
      'financial-details',
      'authentication-credentials'
    ]

    # Rate limiting
    requests_per_minute 10
  end

  workflow do
    step :process_data do
      tool 'data_anonymizer'
      # Ensures PII is removed before analysis
    end

    step :analyze_anonymized do
      depends_on :process_data
      prompt "Analyze this anonymized data: {process_data.output}"
    end
  end
end
```

## Best Practices

### Time Constraints

1. **Always set timeouts for production** - Prevent indefinite hangs
2. **Set realistic limits** - Allow enough time for completion
3. **Use step-level timeouts** - Granular control over slow operations
4. **Monitor timeout events** - Optimize workflows that frequently timeout

### Resource Constraints

1. **Match Kubernetes limits** - Ensure container resources align
2. **Test with realistic data** - Verify memory limits are sufficient
3. **Monitor resource usage** - Track actual consumption vs. limits

### Budget Constraints

1. **Start conservative** - Begin with low budgets, increase as needed
2. **Use hourly + daily limits** - Prevent burst spending
3. **Track costs** - Monitor actual spending vs. budgets
4. **Set token budgets** - Prevent excessive LLM usage
5. **Review monthly** - Adjust budgets based on actual costs

### Rate Limiting

1. **Layer limits** - Use minute, hour, and day limits together
2. **Account for bursts** - Minute limit should allow reasonable bursts
3. **Match API quotas** - Stay within provider rate limits
4. **Monitor rejections** - Track how often limits are hit

### Content Filtering

1. **Block sensitive patterns** - Always filter PII (SSN, credit cards, etc.)
2. **Use broad patterns** - Catch variations (with/without dashes, etc.)
3. **Test filters** - Verify patterns match intended content
4. **Log blocks** - Audit what content is being filtered
5. **Review regularly** - Update patterns as new risks emerge

### Combined Constraints

1. **Use multiple constraint types** - Defense in depth
2. **Make budgets compatible** - Ensure daily budget allows hourly * 24
3. **Test limits** - Verify constraints work as expected
4. **Document rationale** - Explain why specific limits were chosen
5. **Monitor violations** - Track which constraints are hit most often

## See Also

- [Understanding Generated Code](understanding-generated-code.md) - Working with agent definitions
- [Best Practices](best-practices.md) - Production deployment patterns  
- [Webhooks](webhooks.md) - Reactive agent configuration
- [CLI Reference](cli-reference.md) - Managing constraints via CLI
