# Webhooks

Language Operator agents can respond to webhooks from GitHub, Stripe, Slack, and other services. This guide shows how webhook agents work and what they look like when synthesized.

## How Webhook Agents Work

When you describe an agent that responds to external events, Language Operator creates a reactive agent with webhook endpoints.

### Creating Webhook Agents

```bash
langop agent create github-pr-reviewer
# Wizard asks:
# - What service sends webhooks? (GitHub, Stripe, Slack, custom)
# - What events should trigger the agent? (pull_request, push, etc.)
# - What should the agent do when triggered?
```

Language Operator automatically:
1. Sets up secure webhook endpoints
2. Configures authentication (HMAC, API keys, etc.)
3. Handles payload parsing and validation
4. Routes events to your agent logic

## Webhook Agent Structure

### Basic Structure

```ruby
agent "github-pr-reviewer" do
  description "Reviews pull requests and provides feedback"
  mode :reactive
  
  # Webhook configuration
  webhook do
    endpoint "github"
    authentication :hmac_sha256
    secret ENV['GITHUB_WEBHOOK_SECRET']
    events ['pull_request.opened', 'pull_request.synchronize']
  end
  
  # Event processing tasks
  task :analyze_pr,
    instructions: "analyze the pull request changes and identify issues",
    inputs: { pr_number: 'integer', diff: 'string', files: 'array' },
    outputs: { issues: 'array', suggestion: 'string' }
  
  # Main webhook handler
  main do |webhook_payload|
    # Extract PR information
    pr_data = execute_task(:extract_pr_info, inputs: webhook_payload)
    
    # Analyze the changes
    analysis = execute_task(:analyze_pr, inputs: pr_data)
    
    # Post review comment
    execute_task(:post_review, inputs: analysis.merge(pr_data))
  end
  
  output do |outputs|
    # Results are handled by tasks (posting comments, etc.)
    { status: 'review_posted', timestamp: Time.now }
  end
end
```

## Common Webhook Patterns

### GitHub Integration

**Pull Request Reviews**:
```ruby
agent "pr-reviewer" do
  description "Automatically reviews pull requests for code quality"
  mode :reactive
  
  webhook do
    endpoint "github"
    authentication :hmac_sha256
    events ['pull_request.opened', 'pull_request.synchronize']
  end
  
  task :fetch_pr_diff,
    instructions: "get the diff and changed files for the pull request",
    inputs: { pr_number: 'integer', repo: 'string' },
    outputs: { diff: 'string', files: 'array' }
  
  task :review_code,
    instructions: "analyze code for bugs, style issues, and best practices",
    inputs: { diff: 'string', files: 'array' },
    outputs: { issues: 'array', overall_rating: 'string' }
  
  task :post_review,
    instructions: "post review comments on the pull request",
    inputs: { pr_number: 'integer', issues: 'array', rating: 'string' },
    outputs: { comment_posted: 'boolean' }
  
  main do |webhook_payload|
    pr_info = {
      pr_number: webhook_payload['pull_request']['number'],
      repo: webhook_payload['repository']['full_name']
    }
    
    diff_data = execute_task(:fetch_pr_diff, inputs: pr_info)
    review = execute_task(:review_code, inputs: diff_data)
    execute_task(:post_review, inputs: review.merge(pr_info))
  end
end
```

**Issue Management**:
```ruby
agent "issue-triager" do
  description "Automatically triages and labels GitHub issues"
  mode :reactive
  
  webhook do
    endpoint "github"
    events ['issues.opened']
  end
  
  task :classify_issue,
    instructions: "classify issue type and priority based on title and description",
    inputs: { title: 'string', body: 'string' },
    outputs: { type: 'string', priority: 'string', labels: 'array' }
  
  task :assign_issue,
    instructions: "assign issue to appropriate team member based on classification",
    inputs: { type: 'string', priority: 'string' },
    outputs: { assignee: 'string' }
  
  main do |webhook_payload|
    issue_data = {
      title: webhook_payload['issue']['title'],
      body: webhook_payload['issue']['body']
    }
    
    classification = execute_task(:classify_issue, inputs: issue_data)
    assignment = execute_task(:assign_issue, inputs: classification)
    
    # Apply labels and assignment
    execute_task(:update_issue, inputs: {
      issue_number: webhook_payload['issue']['number'],
      labels: classification[:labels],
      assignee: assignment[:assignee]
    })
  end
end
```

### Stripe Integration

**Payment Processing**:
```ruby
agent "payment-processor" do
  description "Handles successful payments and sends notifications"
  mode :reactive
  
  webhook do
    endpoint "stripe"
    authentication :stripe_signature
    events ['payment_intent.succeeded']
  end
  
  task :extract_payment_info,
    instructions: "extract customer and payment details from Stripe payload",
    inputs: { stripe_payload: 'hash' },
    outputs: { customer_id: 'string', amount: 'number', currency: 'string' }
  
  task :send_receipt,
    instructions: "send payment receipt email to customer",
    inputs: { customer_id: 'string', amount: 'number', currency: 'string' },
    outputs: { email_sent: 'boolean' }
  
  task :update_subscription,
    instructions: "update customer subscription status in database",
    inputs: { customer_id: 'string', amount: 'number' },
    outputs: { subscription_updated: 'boolean' }
  
  main do |webhook_payload|
    payment_info = execute_task(:extract_payment_info, 
      inputs: { stripe_payload: webhook_payload })
    
    # Send receipt and update subscription in parallel
    execute_parallel([
      { name: :send_receipt, inputs: payment_info },
      { name: :update_subscription, inputs: payment_info }
    ])
  end
end
```

### Slack Integration

**Command Handler**:
```ruby
agent "slack-bot" do
  description "Handles slack slash commands and interactive messages"
  mode :reactive
  
  webhook do
    endpoint "slack"
    authentication :slack_verification
    events ['slash_command', 'interactive_message']
  end
  
  task :parse_command,
    instructions: "parse slack command and extract parameters",
    inputs: { command: 'string', text: 'string' },
    outputs: { action: 'string', params: 'hash' }
  
  task :execute_action,
    instructions: "execute the requested action with given parameters",
    inputs: { action: 'string', params: 'hash' },
    outputs: { result: 'string', success: 'boolean' }
  
  main do |webhook_payload|
    if webhook_payload['type'] == 'slash_command'
      command_info = {
        command: webhook_payload['command'],
        text: webhook_payload['text']
      }
      
      parsed = execute_task(:parse_command, inputs: command_info)
      result = execute_task(:execute_action, inputs: parsed)
      
      # Respond to Slack
      execute_task(:send_slack_response, inputs: {
        response_url: webhook_payload['response_url'],
        message: result[:result]
      })
    end
  end
end
```

### Custom Webhooks

**API Integration**:
```ruby
agent "api-monitor" do
  description "Monitors API health via webhooks and alerts on issues"
  mode :reactive
  
  webhook do
    endpoint "custom"
    authentication :api_key
    path "/health-check"
  end
  
  task :analyze_health_data,
    instructions: "analyze API health metrics and identify problems",
    inputs: { metrics: 'hash' },
    outputs: { status: 'string', issues: 'array', alerts_needed: 'boolean' }
  
  task :send_alerts,
    instructions: "send alerts to operations team via multiple channels",
    inputs: { issues: 'array', severity: 'string' },
    outputs: { alerts_sent: 'array' }
  
  main do |webhook_payload|
    analysis = execute_task(:analyze_health_data, 
      inputs: { metrics: webhook_payload })
    
    if analysis[:alerts_needed]
      execute_task(:send_alerts, inputs: {
        issues: analysis[:issues],
        severity: analysis[:status]
      })
    end
  end
end
```

## Webhook Configuration

### Authentication Methods

Language Operator supports multiple authentication methods:

**HMAC Signature Verification** (GitHub, Stripe):
```ruby
webhook do
  endpoint "github"
  authentication :hmac_sha256
  secret ENV['GITHUB_WEBHOOK_SECRET']
end
```

**API Key Authentication**:
```ruby
webhook do
  endpoint "custom"
  authentication :api_key
  api_key ENV['WEBHOOK_API_KEY']
  header "X-API-Key"  # Custom header name
end
```

**Bearer Token Authentication**:
```ruby
webhook do
  endpoint "custom"
  authentication :bearer_token
  token ENV['WEBHOOK_TOKEN']
end
```

**Custom Authentication**:
```ruby
webhook do
  endpoint "custom"
  authentication :custom
  validate do |headers, body|
    # Custom validation logic
    headers['X-Custom-Auth'] == ENV['CUSTOM_SECRET']
  end
end
```

### Event Filtering

Filter specific events to reduce noise:

```ruby
webhook do
  endpoint "github"
  events [
    'pull_request.opened',
    'pull_request.synchronize',
    'issues.opened'
  ]
  
  # Additional filters
  filters do
    branch 'main'                    # Only main branch
    repository 'company/main-repo'   # Specific repository
    label_present 'needs-review'     # Must have label
  end
end
```

## Webhook Endpoints

### Automatic URL Generation

Language Operator automatically generates secure webhook URLs:

```
https://webhooks.your-cluster.com/agents/{agent-id}/webhook/{endpoint}
```

**Examples**:
- `https://webhooks.company.com/agents/pr-reviewer-abc123/webhook/github`
- `https://webhooks.company.com/agents/payment-processor-def456/webhook/stripe`

### Custom Paths

For custom integrations, specify custom paths:

```ruby
webhook do
  endpoint "custom"
  path "/api/v1/health-check"  # Custom path
  methods ['POST', 'PUT']      # Allowed HTTP methods
end
```

## Security Features

### Request Validation

All webhook requests are validated:
- **Signature verification**: HMAC signatures verified automatically
- **Content-type checking**: Ensures proper JSON/form data
- **Rate limiting**: Prevents abuse and DoS attacks
- **IP whitelisting**: Restrict access to known service IPs

### Payload Sanitization

Webhook payloads are automatically sanitized:
- Potentially dangerous fields are filtered
- Large payloads are truncated if needed
- Sensitive information is masked in logs

## Error Handling

Webhook agents handle errors gracefully:

```ruby
main do |webhook_payload|
  begin
    # Normal processing
    result = execute_task(:process_webhook, inputs: webhook_payload)
    result
  rescue => e
    # Log error and return appropriate response
    logger.error("Webhook processing failed: #{e.message}")
    
    # Return error response
    {
      status: 'error',
      message: 'Processing failed',
      timestamp: Time.now
    }
  end
end
```

### Retry Logic

Failed webhooks are automatically retried:
- Exponential backoff for temporary failures
- Dead letter queue for permanent failures  
- Alerting when retry limits exceeded

## Monitoring and Debugging

### Webhook Logs

Monitor webhook activity:

```bash
# View webhook logs
langop agent logs pr-reviewer --webhooks-only

# Follow webhook activity in real-time
langop agent logs pr-reviewer --follow --filter webhook

# View specific webhook processing
langop agent webhook-logs pr-reviewer --webhook-id abc123
```

### Webhook Testing

Test webhooks during development:

```bash
# Test webhook endpoint
langop agent test-webhook pr-reviewer \
  --payload ./test-payload.json \
  --event pull_request.opened

# Simulate webhook with custom data
langop agent simulate-webhook pr-reviewer \
  --github-pr 123 \
  --repository company/main-repo
```

## Performance Optimization

### Parallel Processing

Process webhooks efficiently using parallel task execution:

```ruby
main do |webhook_payload|
  # Process multiple aspects in parallel
  results = execute_parallel([
    { name: :validate_payload, inputs: webhook_payload },
    { name: :fetch_context, inputs: webhook_payload },
    { name: :check_permissions, inputs: webhook_payload }
  ])
  
  # Continue with main processing
  if results.all? { |r| r[:valid] }
    execute_task(:main_processing, inputs: webhook_payload)
  end
end
```

### Webhook Queuing

High-volume webhooks are queued automatically:
- Asynchronous processing for non-urgent webhooks
- Priority queues for critical events
- Batch processing for similar events

## Best Practices

### Security
- Always use proper authentication (HMAC, API keys)
- Validate webhook sources and signatures
- Sanitize and validate all input data
- Use environment variables for secrets

### Performance  
- Process webhooks asynchronously when possible
- Use parallel execution for independent tasks
- Cache frequently accessed data
- Monitor response times and optimize bottlenecks

### Reliability
- Implement proper error handling and retries
- Log all webhook activity for debugging
- Test webhook processing with realistic payloads
- Monitor webhook endpoint availability

### Scalability
- Design for high webhook volumes
- Use efficient data structures and algorithms
- Consider webhook batching for similar events
- Scale webhook processing horizontally

## Next Steps

- **[Understanding Generated Code](understanding-generated-code.md)** - Learn to read webhook agent code
- **[Using Tools](using-tools.md)** - How webhook agents use external services
- **[Agent Configuration](agent-configuration.md)** - Configure webhook settings and limits