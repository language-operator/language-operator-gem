# Webhook Guide

Complete guide to configuring webhook endpoints for reactive agents.

## Table of Contents

- [Overview](#overview)
- [Basic Webhook Configuration](#basic-webhook-configuration)
- [HTTP Methods](#http-methods)
- [Authentication](#authentication)
- [Request Validation](#request-validation)
- [Event Handling](#event-handling)
- [Complete Examples](#complete-examples)

## Overview

Webhooks enable agents to respond to external events from services like GitHub, Stripe, Slack, and custom applications.

**Key Features:**
- Multiple authentication methods (HMAC, API key, Bearer token, Basic auth)
- Request validation (headers, content-type, custom rules)
- Automatic routing via UUID-based subdomains
- Integration with workflow execution

## Basic Webhook Configuration

Define a webhook endpoint in a reactive agent:

```ruby
agent "webhook-handler" do
  description "Handle webhook events"

  mode :reactive

  webhook "/events" do
    method :post
    # Additional configuration...
  end

  on_webhook_event do |event|
    # Process the event
    puts "Received: #{event.inspect}"
  end
end
```

**URL Structure:**
Each agent gets a unique subdomain based on its UUID:
```
https://<agent-uuid>.webhooks.your-domain.com/events
```

The operator automatically creates routing for this subdomain.

## HTTP Methods

Specify which HTTP methods the webhook accepts:

### Single Method

```ruby
webhook "/github/pr" do
  method :post  # Only POST requests
end
```

### Multiple Methods

```ruby
webhook "/api/data" do
  methods [:get, :post, :put]  # Accept GET, POST, or PUT
end
```

**Supported methods:**
- `:get`
- `:post`
- `:put`
- `:delete`
- `:patch`
- `:head`
- `:options`

## Authentication

Webhooks support multiple authentication methods to verify request origin.

### HMAC Signature Verification

Verify requests using HMAC signatures (GitHub, Stripe style):

```ruby
webhook "/github/events" do
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

**Parameters:**
- `header` (String): HTTP header containing the signature
- `secret` (String): Shared secret for verification
- `algorithm` (Symbol): Hash algorithm (`:sha1`, `:sha256`, `:sha512`)

**How it works:**
1. Receiver computes HMAC of request body using secret
2. Compares computed signature with header value
3. Rejects request if signatures don't match

**Common Patterns:**

GitHub webhooks:
```ruby
verify_signature(
  header: 'X-Hub-Signature-256',
  secret: ENV['GITHUB_WEBHOOK_SECRET'],
  algorithm: :sha256
)
```

Stripe webhooks:
```ruby
verify_signature(
  header: 'Stripe-Signature',
  secret: ENV['STRIPE_WEBHOOK_SECRET'],
  algorithm: :sha256
)
```

### API Key Authentication

Verify requests using API keys in headers or query parameters:

```ruby
webhook "/api/events" do
  method :post

  authenticate do
    verify_api_key(
      header: 'X-API-Key',
      secret: ENV['WEBHOOK_API_KEY']
    )
  end
end
```

**Header-based:**
```ruby
verify_api_key(
  header: 'X-API-Key',
  secret: ENV['API_KEY']
)
```

**Query parameter:**
```ruby
verify_api_key(
  param: 'api_key',
  secret: ENV['API_KEY']
)
```

### Bearer Token Authentication

OAuth-style bearer token authentication:

```ruby
webhook "/api/events" do
  method :post

  authenticate do
    verify_bearer_token(
      token: ENV['BEARER_TOKEN']
    )
  end
end
```

**Expected header:**
```
Authorization: Bearer <token>
```

### Basic Auth

HTTP Basic Authentication:

```ruby
webhook "/secure/endpoint" do
  method :post

  authenticate do
    basic_auth(
      username: ENV['WEBHOOK_USERNAME'],
      password: ENV['WEBHOOK_PASSWORD']
    )
  end
end
```

**Expected header:**
```
Authorization: Basic <base64(username:password)>
```

### Custom Authentication

Implement custom authentication logic:

```ruby
webhook "/custom/auth" do
  method :post

  authenticate do
    custom do |request|
      # Custom validation logic
      api_key = request.headers['X-Custom-Auth']
      valid_keys = ENV['VALID_API_KEYS'].split(',')

      if valid_keys.include?(api_key)
        true  # Authentication succeeded
      else
        false  # Authentication failed
      end
    end
  end
end
```

### Composite Authentication

Require multiple authentication methods (all must pass):

```ruby
webhook "/highly-secure" do
  method :post

  authenticate do
    all_of do
      verify_api_key header: 'X-API-Key', secret: ENV['API_KEY']
      verify_signature header: 'X-Signature', secret: ENV['HMAC_SECRET'], algorithm: :sha256
    end
  end
end
```

Accept any of multiple authentication methods (any one passes):

```ruby
webhook "/flexible-auth" do
  method :post

  authenticate do
    any_of do
      verify_api_key header: 'X-API-Key', secret: ENV['API_KEY']
      verify_bearer_token token: ENV['BEARER_TOKEN']
      basic_auth username: ENV['USERNAME'], password: ENV['PASSWORD']
    end
  end
end
```

## Request Validation

Validate incoming requests beyond authentication.

### Content-Type Validation

Require specific content types:

```ruby
webhook "/json-only" do
  method :post

  validate do
    content_type 'application/json'
  end
end
```

**Multiple acceptable types:**
```ruby
validate do
  content_type ['application/json', 'application/x-www-form-urlencoded']
end
```

### Header Validation

Require specific headers to be present:

```ruby
webhook "/strict" do
  method :post

  validate do
    require_headers ['X-Event-Type', 'X-Request-ID']
  end
end
```

**Header value validation:**
```ruby
validate do
  header_matches 'X-Event-Type', /^(push|pull_request|issues)$/
end
```

### Request Size Limits

Limit request body size:

```ruby
webhook "/limited" do
  method :post

  validate do
    max_body_size '1MB'  # Reject requests larger than 1MB
  end
end
```

**Supported formats:**
- `'1KB'` - 1 Kilobyte
- `'500KB'` - 500 Kilobytes
- `'1MB'` - 1 Megabyte
- `'10MB'` - 10 Megabytes

### Custom Validation

Implement custom validation rules:

```ruby
webhook "/custom-validation" do
  method :post

  validate do
    custom do |request|
      # Parse and validate request body
      begin
        body = JSON.parse(request.body.read)
        body.key?('event_type') && body.key?('data')
      rescue JSON::ParserError
        false
      end
    end
  end
end
```

### Combined Validation

```ruby
webhook "/comprehensive-validation" do
  method :post

  validate do
    content_type 'application/json'
    max_body_size '5MB'
    require_headers ['X-Event-Type', 'X-Request-ID']

    custom do |request|
      # Additional custom checks
      event_type = request.headers['X-Event-Type']
      ['user.created', 'user.updated', 'user.deleted'].include?(event_type)
    end
  end
end
```

## Event Handling

Process webhook events in your agent.

### Basic Event Handler

```ruby
agent "event-processor" do
  mode :reactive

  webhook "/events" do
    method :post
  end

  on_webhook_event do |event|
    puts "Event received: #{event['type']}"

    # Access event data
    user_id = event.dig('data', 'user_id')
    action = event['action']

    # Perform actions...
  end
end
```

### Event Handler with Workflow

Trigger workflows from webhook events:

```ruby
agent "github-pr-handler" do
  mode :reactive

  webhook "/github/pr" do
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
    # Event data available in workflow context
    @event_data = event
  end

  workflow do
    step :extract_pr_info do
      execute do |context|
        pr = context[:event].dig('pull_request')
        {
          number: pr['number'],
          title: pr['title'],
          author: pr.dig('user', 'login'),
          diff_url: pr['diff_url']
        }
      end
    end

    step :fetch_diff do
      depends_on :extract_pr_info
      tool 'http_get'
      params url: '{extract_pr_info.diff_url}'
    end

    step :review do
      depends_on :fetch_diff
      prompt "Review this pull request code: {fetch_diff.output}"
    end

    step :post_comment do
      depends_on :review
      tool 'github_api'
      params(
        action: 'create_comment',
        issue_number: '{extract_pr_info.number}',
        body: '{review.output}'
      )
    end
  end
end
```

### Event Filtering

Process only specific event types:

```ruby
on_webhook_event do |event|
  event_type = event['type']

  case event_type
  when 'pull_request.opened'
    # Handle new PR
    handle_new_pr(event)
  when 'pull_request.closed'
    # Handle closed PR
    handle_closed_pr(event)
  else
    # Ignore other events
    puts "Ignoring event type: #{event_type}"
  end
end
```

## Complete Examples

### GitHub Pull Request Reviewer

```ruby
agent "github-pr-reviewer" do
  description "Automatically review pull requests"

  mode :reactive

  persona <<~PERSONA
    You are a senior software engineer conducting code reviews.
    Focus on correctness, security, performance, and maintainability.
    Provide constructive, specific feedback.
  PERSONA

  webhook "/github/pull-request" do
    method :post

    # GitHub webhook authentication
    authenticate do
      verify_signature(
        header: 'X-Hub-Signature-256',
        secret: ENV['GITHUB_WEBHOOK_SECRET'],
        algorithm: :sha256
      )
    end

    # Validate GitHub webhook format
    validate do
      content_type 'application/json'
      require_headers ['X-GitHub-Event', 'X-GitHub-Delivery']
      max_body_size '10MB'
    end
  end

  on_webhook_event do |event|
    # Filter to only PR open/sync events
    gh_event = event.headers['X-GitHub-Event']
    return unless gh_event == 'pull_request'

    action = event.dig('body', 'action')
    return unless ['opened', 'synchronize'].include?(action)

    # Event passes filters, workflow will execute
  end

  workflow do
    step :extract_pr do
      execute do |context|
        pr = context[:event].dig('body', 'pull_request')
        {
          number: pr['number'],
          title: pr['title'],
          body: pr['body'],
          diff_url: pr['diff_url'],
          repo_full_name: context[:event].dig('body', 'repository', 'full_name')
        }
      end
    end

    step :fetch_diff do
      depends_on :extract_pr
      tool 'github_api'
      params(
        action: 'get_pr_diff',
        repo: '{extract_pr.repo_full_name}',
        pr_number: '{extract_pr.number}'
      )
    end

    step :review_code do
      depends_on [:extract_pr, :fetch_diff]
      prompt <<~PROMPT
        Review this pull request:

        Title: {extract_pr.title}
        Description: {extract_pr.body}

        Code changes:
        {fetch_diff.output}

        Provide a detailed code review covering:
        1. Code correctness
        2. Security issues
        3. Performance concerns
        4. Best practices
        5. Suggestions for improvement

        Be specific and constructive.
      PROMPT
    end

    step :post_review do
      depends_on [:extract_pr, :review_code]
      tool 'github_api'
      params(
        action: 'create_review_comment',
        repo: '{extract_pr.repo_full_name}',
        pr_number: '{extract_pr.number}',
        body: '{review_code.output}'
      )
    end
  end

  constraints do
    timeout '10m'
    requests_per_hour 100
    daily_budget 1000  # $10/day
  end
end
```

### Stripe Payment Processor

```ruby
agent "stripe-payment-handler" do
  description "Process Stripe payment events"

  mode :reactive

  webhook "/stripe/events" do
    method :post

    # Stripe webhook signature verification
    authenticate do
      verify_signature(
        header: 'Stripe-Signature',
        secret: ENV['STRIPE_WEBHOOK_SECRET'],
        algorithm: :sha256
      )
    end

    validate do
      content_type 'application/json'
    end
  end

  on_webhook_event do |event|
    event_type = event.dig('body', 'type')

    case event_type
    when 'payment_intent.succeeded'
      handle_successful_payment(event)
    when 'payment_intent.payment_failed'
      handle_failed_payment(event)
    when 'customer.subscription.created'
      handle_new_subscription(event)
    else
      puts "Unhandled event: #{event_type}"
    end
  end

  workflow do
    step :extract_payment do
      execute do |context|
        event_data = context[:event].dig('body', 'data', 'object')
        {
          payment_id: event_data['id'],
          amount: event_data['amount'],
          currency: event_data['currency'],
          customer_id: event_data['customer'],
          status: event_data['status']
        }
      end
    end

    step :update_database do
      depends_on :extract_payment
      tool 'database_update'
      params(
        table: 'payments',
        where: { stripe_payment_id: '{extract_payment.payment_id}' },
        data: {
          status: '{extract_payment.status}',
          updated_at: 'NOW()'
        }
      )
    end

    step :send_confirmation do
      depends_on :extract_payment
      tool 'send_email'
      params(
        to: '{extract_payment.customer_email}',
        subject: 'Payment Confirmation',
        body: 'Your payment of {extract_payment.amount} {extract_payment.currency} was successful'
      )
    end
  end

  constraints do
    timeout '30s'  # Process quickly
    requests_per_minute 100  # High throughput
    hourly_budget 100  # $1/hour
  end
end
```

### Custom Application Webhook

```ruby
agent "custom-app-handler" do
  description "Handle events from custom application"

  mode :reactive

  webhook "/app/events" do
    methods [:post, :put]

    # Flexible authentication
    authenticate do
      any_of do
        verify_api_key header: 'X-API-Key', secret: ENV['APP_API_KEY']
        verify_bearer_token token: ENV['APP_BEARER_TOKEN']
      end
    end

    validate do
      content_type 'application/json'
      max_body_size '5MB'

      custom do |request|
        # Ensure required fields present
        body = JSON.parse(request.body.read)
        body['event_type'] && body['timestamp'] && body['data']
      rescue JSON::ParserError
        false
      end
    end
  end

  on_webhook_event do |event|
    # Process event...
  end

  constraints do
    timeout '1m'
    requests_per_minute 50
    daily_budget 500
  end
end
```

### Slack Command Handler

```ruby
agent "slack-bot" do
  description "Respond to Slack slash commands"

  mode :reactive

  webhook "/slack/commands" do
    method :post

    # Slack uses token verification
    authenticate do
      custom do |request|
        token = request.params['token']
        token == ENV['SLACK_VERIFICATION_TOKEN']
      end
    end

    validate do
      content_type 'application/x-www-form-urlencoded'
    end
  end

  on_webhook_event do |event|
    command = event['command']  # e.g., '/deploy'
    text = event['text']        # command arguments
    user = event['user_name']

    # Process command...
  end

  workflow do
    step :parse_command do
      execute do |context|
        command = context[:event]['command']
        text = context[:event]['text']

        {
          command: command,
          args: text.split(' '),
          user: context[:event]['user_name']
        }
      end
    end

    step :execute_command do
      depends_on :parse_command
      prompt "Execute this Slack command: {parse_command.command} {parse_command.args}"
    end

    step :respond_to_slack do
      depends_on :execute_command
      tool 'slack_respond'
      params(
        response_url: '{event.response_url}',
        text: '{execute_command.output}'
      )
    end
  end

  constraints do
    timeout '3s'  # Slack requires fast responses
    requests_per_minute 30
  end
end
```

## Security Best Practices

### Always Use Authentication

Never expose webhooks without authentication:

```ruby
# INSECURE - Don't do this
webhook "/insecure" do
  method :post
  # No authentication!
end

# SECURE - Always authenticate
webhook "/secure" do
  method :post
  authenticate do
    verify_signature(...)
  end
end
```

### Use HTTPS

Webhooks are automatically served over HTTPS via the Gateway. Ensure:
- TLS certificates are properly configured
- No HTTP fallback is enabled

### Validate Request Size

Always limit request size to prevent DoS:

```ruby
validate do
  max_body_size '10MB'
end
```

### Store Secrets Securely

Use Kubernetes Secrets for webhook secrets:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: webhook-secrets
data:
  github-webhook-secret: <base64-encoded-secret>
  stripe-webhook-secret: <base64-encoded-secret>
```

Reference in agent environment:

```ruby
authenticate do
  verify_signature(
    secret: ENV['GITHUB_WEBHOOK_SECRET']  # From K8s Secret
  )
end
```

### Implement Rate Limiting

Protect against abuse:

```ruby
constraints do
  requests_per_minute 30
  requests_per_hour 500
end
```

### Log Webhook Activity

Enable audit logging for security monitoring:

```ruby
on_webhook_event do |event|
  # Log webhook receipt
  AuditLog.record(
    event: 'webhook_received',
    source_ip: event.request.ip,
    user_agent: event.request.user_agent,
    payload_size: event.request.content_length
  )

  # Process event...
end
```

## Troubleshooting

### Webhook Not Receiving Events

1. **Check DNS**: Verify subdomain resolves correctly
   ```bash
   dig <agent-uuid>.webhooks.your-domain.com
   ```

2. **Check Gateway routing**: Verify HTTPRoute is created
   ```bash
   kubectl get httproute -n language-operator-system
   ```

3. **Check agent status**: Verify agent is running
   ```bash
   kubectl get languageagent <agent-name> -o yaml
   ```

4. **Check webhook URL**: Get the correct URL from agent status
   ```bash
   kubectl get languageagent <agent-name> -o jsonpath='{.status.webhookURLs}'
   ```

### Authentication Failures

1. **Verify secret**: Ensure correct secret is configured
2. **Check signature algorithm**: Ensure it matches the sender's algorithm
3. **Inspect headers**: Log incoming headers to verify format
4. **Test with curl**: Send a test request with correct authentication

### Event Not Processing

1. **Check filters**: Ensure `on_webhook_event` logic isn't filtering out events
2. **Check logs**: Review agent logs for errors
3. **Verify workflow**: Test workflow execution separately
4. **Check constraints**: Ensure rate limits aren't being exceeded

## See Also

- [Agent Reference](agent-reference.md) - Complete agent DSL reference
- [Workflows](workflows.md) - Workflow definition guide
- [Constraints](constraints.md) - Resource and behavior limits
- [Best Practices](best-practices.md) - Production deployment patterns
