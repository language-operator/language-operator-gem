# Agent Optimization

Language Operator agents automatically learn and improve over time. This guide explains how optimization works and how to monitor and control it.

## How Optimization Works

### The Learning Process

1. **Initial State**: All tasks start as "neural" - using AI to figure out what to do
2. **Observation**: Language Operator tracks how tasks execute over multiple runs
3. **Pattern Detection**: When consistent patterns emerge, the system generates optimized code
4. **Deployment**: Neural tasks are replaced with efficient symbolic code automatically

### What Gets Optimized

**Neural Task (Before)**:
```ruby
task :fetch_user_data,
  instructions: "get user profile and preferences from the database",
  inputs: { user_id: 'integer' },
  outputs: { user: 'hash', preferences: 'hash' }
```

**Symbolic Task (After)**:
```ruby
task :fetch_user_data,
  inputs: { user_id: 'integer' },
  outputs: { user: 'hash', preferences: 'hash' }
do |inputs|
  user = execute_tool('database', 'query', {
    table: 'users',
    where: { id: inputs[:user_id] }
  })
  
  preferences = execute_tool('database', 'query', {
    table: 'user_preferences', 
    where: { user_id: inputs[:user_id] }
  })
  
  { user: user.first, preferences: preferences.first }
end
```

## Benefits of Optimization

### Performance
- **Faster execution**: Direct code runs faster than AI inference
- **Predictable timing**: No variability from AI model response times
- **Lower latency**: No network calls to AI services for learned tasks

### Cost Reduction
- **Reduced AI costs**: Symbolic tasks don't use paid AI services
- **Better resource utilization**: More efficient CPU and memory usage
- **Scalability**: Optimized agents handle more load with same resources

### Reliability
- **Consistent behavior**: Symbolic tasks produce identical results for same inputs
- **No AI model dependencies**: Learned tasks work even if AI services are unavailable
- **Easier debugging**: You can read and understand the generated code

## Monitoring Optimization

### Check Optimization Status

```bash
# View current optimization status
aictl agent status my-agent

# Detailed optimization metrics  
aictl agent optimize my-agent --status
```

### Understanding Optimization Metrics

```bash
Agent: my-agent
Tasks: 5 total
  - 2 neural (40%)
  - 3 symbolic (60%)
  
Optimization opportunities:
  - fetch_user_data: 15 runs, 95% pattern confidence ✅ Ready
  - send_notification: 8 runs, 78% pattern confidence ⏳ Needs more data
  - process_results: Optimized ✅
  - validate_input: Optimized ✅
  - generate_report: 3 runs, learning...
  
Cost savings: 67% reduction in AI usage
Performance improvement: 2.3x faster average execution
```

## Controlling Optimization

### Automatic Optimization (Default)

By default, agents optimize automatically:
- Tasks become symbolic after 10+ consistent executions
- Pattern detection requires 85%+ consistency
- Optimization happens during low-traffic periods

### Manual Optimization

Trigger optimization manually:

```bash
# Optimize specific agent
aictl agent optimize my-agent

# Optimize specific task
aictl agent optimize my-agent --task fetch_user_data

# Preview what would be optimized (dry run)
aictl agent optimize my-agent --dry-run
```

### Optimization Settings

Configure optimization behavior in your agent:

```ruby
agent "my-agent" do
  # Agent definition...
  
  optimization do
    auto_optimize true              # Enable automatic optimization
    min_executions 10              # Minimum runs before optimization
    confidence_threshold 0.85      # Pattern consistency required
    optimization_schedule "0 2 * * *"  # When to run optimization (2 AM daily)
  end
end
```

## Optimization Patterns

### Data Fetching Tasks

**Common pattern**: Tasks that fetch data from APIs or databases

```ruby
# Before: AI figures out API calls
task :get_weather,
  instructions: "get current weather for the city",
  inputs: { city: 'string' },
  outputs: { temperature: 'number', condition: 'string' }

# After: Direct API call
task :get_weather,
  inputs: { city: 'string' },
  outputs: { temperature: 'number', condition: 'string' }
do |inputs|
  weather = execute_tool('weather_api', 'current', {
    location: inputs[:city],
    units: 'celsius'
  })
  
  { 
    temperature: weather['temp'],
    condition: weather['description']
  }
end
```

### Data Transformation Tasks

**Common pattern**: Tasks that process and transform data

```ruby
# Before: AI analyzes and transforms data
task :calculate_metrics,
  instructions: "calculate average, max, and total from sales data",
  inputs: { sales: 'array' },
  outputs: { average: 'number', maximum: 'number', total: 'number' }

# After: Direct calculation
task :calculate_metrics,
  inputs: { sales: 'array' },
  outputs: { average: 'number', maximum: 'number', total: 'number' }
do |inputs|
  amounts = inputs[:sales].map { |sale| sale['amount'] }
  total = amounts.sum
  
  {
    average: total / amounts.length.to_f,
    maximum: amounts.max,
    total: total
  }
end
```

### Notification Tasks

**Common pattern**: Tasks that send alerts or notifications

```ruby
# Before: AI composes and sends notifications
task :send_alert,
  instructions: "send urgent alert to operations team via Slack",
  inputs: { issue: 'string', severity: 'string' },
  outputs: { sent: 'boolean' }

# After: Direct message composition and sending
task :send_alert,
  inputs: { issue: 'string', severity: 'string' },
  outputs: { sent: 'boolean' }
do |inputs|
  emoji = inputs[:severity] == 'critical' ? '🚨' : '⚠️'
  message = "#{emoji} #{inputs[:severity].upcase}: #{inputs[:issue]}"
  
  result = execute_tool('slack', 'post_message', {
    channel: '#ops-alerts',
    text: message
  })
  
  { sent: result['ok'] }
end
```

## Rollback and Versioning

### Rolling Back Optimizations

If an optimization causes issues, you can roll back:

```bash
# View optimization history
aictl agent history my-agent

# Roll back to previous version
aictl agent rollback my-agent --to-version v2

# Roll back specific task to neural mode
aictl agent rollback my-agent --task fetch_user_data --to-neural
```

### Version Management

Language Operator maintains version history:

```bash
# List all versions
aictl agent versions my-agent

Output:
v4 (current) - optimized 2 tasks (2024-01-15 10:30)
v3 - optimized 1 task (2024-01-14 09:15)  
v2 - initial synthesis (2024-01-10 14:22)
v1 - archived
```

## Best Practices

### Design for Optimization
- **Clear contracts**: Well-defined inputs/outputs help optimization
- **Consistent patterns**: Tasks that follow similar patterns optimize faster
- **Avoid side effects**: Tasks should be pure functions when possible

### Monitor Performance
- Track cost savings from optimization
- Monitor execution times before and after
- Watch for any behavior changes after optimization

### Gradual Optimization
- Start with automatic optimization for non-critical agents
- Use manual optimization for production-critical workflows
- Test optimized agents in staging before production deployment

### When to Stay Neural
Some tasks should remain neural:
- Creative tasks (content generation, design decisions)
- Complex reasoning that varies significantly
- Rarely-executed tasks (not worth optimizing)
- Tasks that need to adapt to changing requirements

## Troubleshooting Optimization

### Task Won't Optimize

**Possible causes:**
- Not enough executions (need 10+ runs)
- Inconsistent behavior (below 85% pattern match)
- Task is too complex for current optimization algorithms
- Task genuinely needs AI reasoning

**Solutions:**
```bash
# Check execution history
aictl agent traces my-agent --task problematic_task

# Lower confidence threshold temporarily
aictl agent optimize my-agent --task problematic_task --confidence 0.7
```

### Optimization Caused Errors

**Immediate fix:**
```bash
# Roll back to neural version
aictl agent rollback my-agent --task broken_task --to-neural
```

**Long-term fix:**
- Review the generated symbolic code
- File issue with Language Operator team
- Add error handling to the task

## Advanced Topics

### Custom Optimization Rules

For enterprise users, you can define custom optimization rules:

```ruby
optimization do
  # Never optimize tasks that call external APIs
  exclude_patterns ['external_api', 'third_party']
  
  # Always optimize database queries
  prioritize_patterns ['database', 'query', 'fetch']
  
  # Custom confidence rules
  confidence_rules do
    pattern 'data_transformation' do
      min_executions 5
      confidence_threshold 0.9
    end
  end
end
```

### Integration with CI/CD

Integrate optimization into your deployment pipeline:

```bash
# In your CI/CD pipeline
aictl agent optimize --all --wait
aictl agent test --optimized-only
aictl agent deploy --if-tests-pass
```

## Next Steps

- **[Monitoring & Debugging](monitoring.md)** - Track agent performance and debug issues
- **[Understanding Generated Code](understanding-generated-code.md)** - Read optimized code
- **[Best Practices](best-practices.md)** - Patterns for reliable agents