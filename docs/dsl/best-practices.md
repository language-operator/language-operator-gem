# Best Practices Guide

Comprehensive guide to designing, securing, and deploying Language Operator agents in production.

## Table of Contents

- [Agent Design Patterns](#agent-design-patterns)
- [Security Best Practices](#security-best-practices)
- [Performance Optimization](#performance-optimization)
- [Testing Strategies](#testing-strategies)
- [Debugging Tips](#debugging-tips)
- [Cost Optimization](#cost-optimization)
- [Production Deployment Checklist](#production-deployment-checklist)

## Agent Design Patterns

### When to Use Each Mode

#### Autonomous Mode

**Use when:**
- Continuous monitoring and alerting required
- Background data processing
- Proactive task execution
- Long-running workflows

**Don't use when:**
- Responding to external events (use reactive)
- Scheduled execution only (use scheduled)
- Cost control is critical (autonomous can be expensive)

**Example:**
```ruby
agent "security-monitor" do
  mode :autonomous

  objectives [
    "Monitor security logs continuously",
    "Detect anomalies in access patterns",
    "Alert on suspicious activity"
  ]

  constraints do
    max_iterations 1000  # Prevent runaway
    daily_budget 5000    # $50/day limit
    requests_per_minute 2  # Check every 30s
  end
end
```

**Best practices:**
- Always set `max_iterations` to prevent infinite loops
- Use `requests_per_minute` to control check frequency
- Set aggressive budget limits
- Monitor costs closely

#### Scheduled Mode

**Use when:**
- Tasks run on fixed schedule (daily, weekly, etc.)
- Reports and summaries needed periodically
- Batch processing at specific times
- Predictable resource usage required

**Don't use when:**
- Need to respond to events in real-time (use reactive)
- Continuous monitoring required (use autonomous)

**Example:**
```ruby
agent "daily-report" do
  mode :scheduled
  schedule "0 9 * * *"  # 9 AM daily

  workflow do
    step :gather_data do
      # Collect yesterday's data
    end

    step :analyze do
      depends_on :gather_data
      # Analyze and summarize
    end

    step :send_report do
      depends_on :analyze
      # Email report
    end
  end

  constraints do
    timeout '30m'        # Must complete in 30 min
    daily_budget 500     # $5/day
  end
end
```

**Best practices:**
- Always set `timeout` to prevent hanging
- Choose appropriate schedule frequency
- Consider timezone (cron runs in UTC by default)
- Set reasonable daily budget based on frequency

#### Reactive Mode

**Use when:**
- Handling webhooks from external services
- Exposing MCP tools to other agents
- Providing chat completion endpoints
- Event-driven workflows

**Don't use when:**
- Need proactive task execution (use autonomous)
- Fixed schedule sufficient (use scheduled)

**Example:**
```ruby
agent "webhook-handler" do
  mode :reactive

  webhook "/events" do
    method :post

    authenticate do
      verify_signature(
        header: 'X-Signature',
        secret: ENV['WEBHOOK_SECRET'],
        algorithm: :sha256
      )
    end

    validate do
      content_type 'application/json'
      max_body_size '5MB'
    end
  end

  constraints do
    timeout '30s'             # Quick response
    requests_per_minute 100   # Handle bursts
    hourly_budget 500         # $5/hour
  end
end
```

**Best practices:**
- Always implement authentication
- Set quick timeouts (seconds, not minutes)
- Handle high request rates
- Validate all inputs

### Workflow Design

#### Breaking Down Complex Tasks

**Good: Focused steps**
```ruby
workflow do
  step :fetch_data do
    tool 'database_query'
  end

  step :validate_data do
    depends_on :fetch_data
    # Validate quality
  end

  step :transform_data do
    depends_on :validate_data
    # Apply transformations
  end

  step :load_data do
    depends_on :transform_data
    # Save results
  end
end
```

**Bad: Monolithic step**
```ruby
workflow do
  step :do_everything do
    # Fetch, validate, transform, and load all in one step
    # Hard to debug, no granular error handling
  end
end
```

**Benefits of focused steps:**
- Easier to debug (know which step failed)
- Better error handling (retry specific steps)
- Clearer dependencies
- Reusable steps

#### Error Handling in Workflows

**Always handle errors:**
```ruby
step :risky_operation do
  tool 'external_api'

  on_error do |error|
    # Log error
    logger.error("Step failed: #{error.message}")

    # Optionally retry or fail gracefully
    { status: 'failed', error: error.message }
  end
end
```

**Retry with backoff:**
```ruby
step :flaky_operation do
  tool 'unreliable_api'

  retry_on_failure(
    max_attempts: 3,
    backoff: :exponential
  )
end
```

## Security Best Practices

### Webhook Security

#### Always Authenticate Webhooks

**Bad: No authentication**
```ruby
webhook "/insecure" do
  method :post
  # Anyone can call this!
end
```

**Good: HMAC signature verification**
```ruby
webhook "/secure" do
  method :post

  authenticate do
    verify_signature(
      header: 'X-Hub-Signature-256',
      secret: ENV['WEBHOOK_SECRET'],
      algorithm: :sha256
    )
  end
end
```

**Good: API key authentication**
```ruby
webhook "/api-secured" do
  method :post

  authenticate do
    verify_api_key(
      header: 'X-API-Key',
      secret: ENV['API_KEY']
    )
  end
end
```

#### Validate All Inputs

```ruby
webhook "/validated" do
  method :post

  authenticate do
    verify_signature(...)
  end

  validate do
    content_type 'application/json'
    max_body_size '5MB'
    require_headers ['X-Event-Type', 'X-Request-ID']

    custom do |request|
      # Additional validation
      body = JSON.parse(request.body.read)
      body.key?('event') && body.key?('data')
    rescue JSON::ParserError
      false
    end
  end
end
```

### PII Protection

#### Filter Sensitive Data

**Use blocked_patterns:**
```ruby
constraints do
  blocked_patterns [
    /\b\d{3}-\d{2}-\d{4}\b/,           # SSN
    /\b\d{16}\b/,                       # Credit card
    /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,  # Phone
    /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,  # Email
    /password\s*[:=]/i,                 # Password disclosure
    /api[_-]?key\s*[:=]\s*['"][^'"]+['"]/i  # API keys
  ]
end
```

#### Sanitize Tool Parameters

```ruby
tool "search_users" do
  parameter :email do
    type :string
    required true
    email_format  # Validates format

    # Custom sanitization
    validate ->(value) {
      # Ensure email is from allowed domains
      allowed = ENV['ALLOWED_EMAIL_DOMAINS'].split(',')
      domain = value.split('@').last
      return "Email domain not allowed" unless allowed.include?(domain)
      true
    }
  end
end
```

#### Redact Sensitive Output

```ruby
step :process_user_data do
  execute do |context|
    user_data = fetch_user(context[:user_id])

    # Redact sensitive fields
    user_data['ssn'] = 'REDACTED'
    user_data['credit_card'] = 'REDACTED'
    user_data['password'] = 'REDACTED'

    user_data
  end
end
```

### Secrets Management

#### Never Hardcode Secrets

**Bad:**
```ruby
authenticate do
  verify_api_key(
    header: 'X-API-Key',
    secret: 'hardcoded-secret-123'  # NEVER DO THIS
  )
end
```

**Good: Use environment variables**
```ruby
authenticate do
  verify_api_key(
    header: 'X-API-Key',
    secret: ENV['WEBHOOK_API_KEY']  # From Kubernetes Secret
  )
end
```

#### Kubernetes Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: agent-secrets
type: Opaque
data:
  webhook-secret: <base64-encoded-value>
  api-key: <base64-encoded-value>
  anthropic-api-key: <base64-encoded-value>
```

Reference in agent:
```yaml
env:
  - name: WEBHOOK_SECRET
    valueFrom:
      secretKeyRef:
        name: agent-secrets
        key: webhook-secret
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: agent-secrets
        key: api-key
```

### Rate Limiting

**Always set rate limits:**
```ruby
constraints do
  requests_per_minute 30   # Prevent burst abuse
  requests_per_hour 1000   # Hourly cap
  requests_per_day 10000   # Daily cap
end
```

**For public-facing agents:**
```ruby
constraints do
  requests_per_minute 10   # Conservative for public
  requests_per_hour 300
  requests_per_day 2000

  daily_budget 1000  # $10/day max
end
```

## Performance Optimization

### Timeouts

#### Set Appropriate Timeouts

**For quick operations:**
```ruby
constraints do
  timeout '30s'  # Quick webhook responses
end
```

**For data processing:**
```ruby
constraints do
  timeout '15m'  # Enough for ETL
end
```

**For complex analysis:**
```ruby
constraints do
  timeout '1h'  # Long-running reports
end
```

#### Step-Level Timeouts

```ruby
workflow do
  step :quick_check do
    timeout '5s'
    # Fast validation
  end

  step :slow_processing do
    timeout '10m'
    # Heavy computation
  end
end
```

### Caching

#### Cache Expensive Operations

```ruby
tool "fetch_exchange_rates" do
  execute do |params|
    # Check cache first
    cache_key = "exchange_rates:#{Date.today}"
    cached = Redis.current.get(cache_key)
    return cached if cached

    # Fetch from API
    rates = fetch_from_api
    result = rates.to_json

    # Cache for 1 hour
    Redis.current.setex(cache_key, 3600, result)

    result
  end
end
```

### Parallel Processing

**For independent steps:**
```ruby
workflow do
  # These can run in parallel
  step :fetch_users do
    tool 'database_query'
  end

  step :fetch_products do
    tool 'database_query'
  end

  # This waits for both
  step :combine do
    depends_on [:fetch_users, :fetch_products]
    # Merge results
  end
end
```

### Resource Limits

**Match container resources:**
```ruby
constraints do
  memory '4Gi'  # Match pod memory limit
  timeout '30m'
end
```

Pod spec:
```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

## Testing Strategies

### Unit Testing Tools

```ruby
RSpec.describe 'MCP Tools' do
  let(:mcp_def) { LanguageOperator::Dsl::McpServerDefinition.new('test') }

  before do
    mcp_def.tool('add') do
      parameter :a do
        type :number
        required true
      end

      parameter :b do
        type :number
        required true
      end

      execute do |params|
        params['a'] + params['b']
      end
    end
  end

  it 'adds numbers correctly' do
    tool = mcp_def.tools['add']
    result = tool.call('a' => 5, 'b' => 3)
    expect(result).to eq(8)
  end

  it 'validates required parameters' do
    tool = mcp_def.tools['add']
    expect {
      tool.call('a' => 5)  # Missing 'b'
    }.to raise_error(ArgumentError)
  end
end
```

### Integration Testing Webhooks

```ruby
RSpec.describe 'Webhook Integration' do
  include Rack::Test::Methods

  let(:agent) { create_agent_with_webhook }
  let(:app) { agent.web_server.rack_app }

  it 'handles webhook requests' do
    post '/webhook', {
      event: 'test',
      data: { key: 'value' }
    }.to_json, {
      'CONTENT_TYPE' => 'application/json',
      'X-Signature' => generate_signature
    }

    expect(last_response.status).to eq(200)
  end

  it 'rejects unauthorized requests' do
    post '/webhook', {}, {
      'CONTENT_TYPE' => 'application/json'
      # Missing signature
    }

    expect(last_response.status).to eq(401)
  end
end
```

### Load Testing

```bash
# Use Apache Bench for simple load tests
ab -n 1000 -c 10 -T application/json \
  -p request.json \
  http://localhost:8080/v1/chat/completions

# Use k6 for more sophisticated tests
k6 run load-test.js
```

k6 script:
```javascript
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: 10,
  duration: '30s',
};

export default function () {
  const payload = JSON.stringify({
    model: 'test-model',
    messages: [{ role: 'user', content: 'Hello' }],
  });

  const params = {
    headers: { 'Content-Type': 'application/json' },
  };

  const res = http.post('http://localhost:8080/v1/chat/completions', payload, params);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
}
```

## Debugging Tips

### Enable Debug Logging

```bash
# Set environment variable
export DEBUG=true
# or
export MCP_DEBUG=true

# Run agent
ruby agent.rb
```

In code:
```ruby
tool "debug_tool" do
  execute do |params|
    if ENV['DEBUG']
      puts "Params: #{params.inspect}"
    end

    result = process(params)

    if ENV['DEBUG']
      puts "Result: #{result.inspect}"
    end

    result
  end
end
```

### Structured Logging

```ruby
require 'logger'

logger = Logger.new(STDOUT)
logger.level = ENV['LOG_LEVEL'] || Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  {
    timestamp: datetime.iso8601,
    severity: severity,
    component: progname,
    message: msg
  }.to_json + "\n"
end

# In agent
step :process do
  execute do |context|
    logger.info("Processing started", user_id: context[:user_id])
    result = process(context)
    logger.info("Processing completed", duration: Time.now - start_time)
    result
  end
end
```

### Trace Workflow Execution

```ruby
workflow do
  before_step do |step_name|
    puts "[#{Time.now}] Starting step: #{step_name}"
  end

  after_step do |step_name, result|
    puts "[#{Time.now}] Completed step: #{step_name}"
    puts "Result: #{result.inspect}"
  end

  on_error do |step_name, error|
    puts "[#{Time.now}] Error in step #{step_name}: #{error.message}"
    puts error.backtrace.join("\n")
  end
end
```

### Monitor Resource Usage

```ruby
require 'benchmark'

step :heavy_processing do
  execute do |context|
    memory_before = `ps -o rss= -p #{Process.pid}`.to_i

    result = Benchmark.measure do
      # Heavy processing
      process_large_dataset(context[:data])
    end

    memory_after = `ps -o rss= -p #{Process.pid}`.to_i
    memory_used = (memory_after - memory_before) / 1024.0  # MB

    logger.info(
      "Step completed",
      duration: result.real,
      memory_mb: memory_used
    )
  end
end
```

### Test in Isolation

```ruby
# Test workflow steps independently
step_def = workflow.steps[:fetch_data]
result = step_def.execute(test_context)
puts result

# Test tools independently
tool = mcp_server.tools['process_csv']
result = tool.call('csv_data' => test_csv)
puts result
```

## Cost Optimization

### Budget Management

**Multi-tier budgets:**
```ruby
constraints do
  hourly_budget 100      # $1/hour - prevents burst spending
  daily_budget 1000      # $10/day - daily cap
  requests_per_minute 30 # Rate limiting
end
```

**For development:**
```ruby
constraints do
  daily_budget 100   # $1/day during development
  token_budget 50000 # Limit token usage
end
```

**For production:**
```ruby
constraints do
  hourly_budget 500    # $5/hour
  daily_budget 5000    # $50/day
  token_budget 1000000 # 1M tokens/day
end
```

### Prompt Optimization

**Avoid verbose system prompts:**

**Bad: Excessive detail (wastes tokens)**
```ruby
system_prompt <<~PROMPT
  You are a helpful assistant. You should always be polite.
  You should always be respectful. You should always provide
  accurate information. You should always cite your sources.
  You should always... (500 more words)
PROMPT
```

**Good: Concise and clear**
```ruby
system_prompt <<~PROMPT
  You are a technical support expert. Provide clear, accurate
  solutions with step-by-step instructions. Cite sources when
  referencing documentation.
PROMPT
```

### Use Appropriate Models

```ruby
# For simple tasks - use smaller/cheaper models
agent "simple-classifier" do
  # Configure via LLM_MODEL env var
  # Use claude-3-haiku or gpt-3.5-turbo for simple tasks
end

# For complex tasks - use advanced models
agent "complex-analyst" do
  # Use claude-3-opus or gpt-4 for complex reasoning
end
```

### Cache When Possible

```ruby
tool "expensive_lookup" do
  execute do |params|
    cache_key = "lookup:#{params['query']}"

    # Check cache
    cached = Cache.get(cache_key)
    return cached if cached

    # Expensive operation
    result = complex_api_call(params['query'])

    # Cache for 1 hour
    Cache.set(cache_key, result, ttl: 3600)

    result
  end
end
```

### Limit Response Length

```ruby
as_chat_endpoint do
  max_tokens 1000  # Limit response length
  system_prompt "Keep responses under 200 words"
end
```

## Production Deployment Checklist

### Pre-Deployment

- [ ] All secrets stored in Kubernetes Secrets (not hardcoded)
- [ ] Budget constraints configured (`daily_budget`, `hourly_budget`)
- [ ] Rate limits set (`requests_per_minute`, `requests_per_hour`)
- [ ] Timeouts configured (`timeout` at agent and step level)
- [ ] PII filtering enabled (`blocked_patterns` for SSN, credit cards, etc.)
- [ ] Webhook authentication implemented (HMAC, API key, etc.)
- [ ] Input validation configured (`validate` blocks on webhooks)
- [ ] Resource limits set (`memory`, matching pod limits)
- [ ] Error handling implemented (try/catch in tools, `on_error` in workflows)
- [ ] Logging configured (structured JSON logs)
- [ ] Health checks responsive (`/health`, `/ready`)

### Security

- [ ] No hardcoded secrets or API keys
- [ ] All webhooks authenticated
- [ ] HTTPS/TLS enabled (via Gateway/Ingress)
- [ ] Content-type validation on all endpoints
- [ ] Request size limits (`max_body_size`)
- [ ] Rate limiting configured
- [ ] PII patterns blocked
- [ ] Sensitive topics filtered
- [ ] API gateway/ingress authentication (for public endpoints)

### Testing

- [ ] Unit tests for all tools
- [ ] Integration tests for webhooks
- [ ] Load tests performed (verify rate limits)
- [ ] Error handling tested
- [ ] Timeout behavior verified
- [ ] Budget limits tested
- [ ] Streaming tested (if using chat endpoints)

### Monitoring

- [ ] Metrics exported (Prometheus, CloudWatch, etc.)
- [ ] Logs aggregated (ELK, Loki, CloudWatch Logs)
- [ ] Alerts configured:
  - [ ] Budget approaching limit
  - [ ] High error rate
  - [ ] Rate limit exceeded
  - [ ] Slow response times
  - [ ] Pod crashes/restarts
- [ ] Dashboards created (Grafana, CloudWatch)
- [ ] On-call runbook prepared

### Performance

- [ ] Resource requests/limits appropriate
- [ ] Timeouts tuned for workload
- [ ] Caching implemented for expensive operations
- [ ] Parallel processing used where applicable
- [ ] Database queries optimized
- [ ] Connection pooling configured

### Cost Management

- [ ] Budget constraints enforced
- [ ] Token budgets set
- [ ] Prompt optimized for efficiency
- [ ] Appropriate model selected (not over-powered)
- [ ] Caching implemented
- [ ] Cost tracking enabled
- [ ] Alerts for cost overruns

### Documentation

- [ ] Agent purpose documented
- [ ] Webhook endpoints documented
- [ ] Tool schemas documented
- [ ] Environment variables documented
- [ ] Runbook created
- [ ] Incident response plan
- [ ] Rollback procedure documented

### Deployment

- [ ] Staging environment tested
- [ ] Gradual rollout plan (canary or blue/green)
- [ ] Rollback plan ready
- [ ] Monitoring verified in production
- [ ] Load tested at production scale
- [ ] Backup/DR plan in place

### Post-Deployment

- [ ] Monitor metrics for first 24 hours
- [ ] Review error logs
- [ ] Verify budget tracking
- [ ] Check resource utilization
- [ ] Gather user feedback
- [ ] Tune parameters based on real usage
- [ ] Document lessons learned

## Production Configuration Example

```ruby
agent "production-agent" do
  description "Production-ready agent with best practices"
  mode :reactive

  # Chat endpoint or webhook
  as_chat_endpoint do
    system_prompt <<~PROMPT
      You are a customer support assistant.
      Provide clear, helpful responses.
      Escalate to human for sensitive issues.
    PROMPT

    model "support-v1"
    temperature 0.7
    max_tokens 1500
  end

  # Security
  constraints do
    # Budget controls
    hourly_budget 500       # $5/hour
    daily_budget 5000       # $50/day
    token_budget 1000000    # 1M tokens/day

    # Rate limiting
    requests_per_minute 60
    requests_per_hour 2000
    requests_per_day 20000

    # Timeouts
    timeout '30s'

    # PII protection
    blocked_patterns [
      /\b\d{3}-\d{2}-\d{4}\b/,           # SSN
      /\b\d{16}\b/,                       # Credit card
      /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,  # Phone
      /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,  # Email
      /password\s*[:=]/i,                 # Password
    ]

    # Content safety
    blocked_topics [
      'violence',
      'hate-speech',
      'illegal-activity'
    ]
  end
end
```

Corresponding Kubernetes deployment:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production-agent
spec:
  replicas: 3  # High availability
  selector:
    matchLabels:
      app: production-agent
  template:
    metadata:
      labels:
        app: production-agent
    spec:
      containers:
      - name: agent
        image: agent-runtime:v1.0.0
        env:
        - name: AGENT_NAME
          value: "production-agent"
        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: agent-secrets
              key: anthropic-api-key
        - name: LOG_LEVEL
          value: "INFO"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
```

## See Also

- [Agent Reference](agent-reference.md) - Complete agent DSL reference
- [Workflows](workflows.md) - Workflow definition guide
- [Constraints](constraints.md) - Resource and behavior limits
- [Webhooks](webhooks.md) - Reactive agent configuration
- [MCP Integration](mcp-integration.md) - Tool server capabilities
- [Chat Endpoints](chat-endpoints.md) - OpenAI-compatible endpoint guide
