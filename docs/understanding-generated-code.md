# Understanding Generated Code

When you create an agent with Language Operator, it generates Ruby code that defines how your agent works. This guide helps you read and understand that generated code.

## Agent Structure Overview

Every synthesized agent has this basic structure:

```ruby
agent "my-agent" do
  # Agent metadata
  description "What this agent does"
  mode :scheduled
  schedule "0 9 * * *"  # 9 AM daily
  
  # Task definitions (work units)
  task :task_name,
    instructions: "what to do",
    inputs: { param: 'type' },
    outputs: { result: 'type' }
  
  # Main execution logic
  main do |inputs|
    result = execute_task(:task_name, inputs: inputs)
    result
  end
  
  # Output handling
  output do |outputs|
    # What to do with results
  end
  
  # Optional constraints
  constraints do
    timeout "10m"
    daily_budget 5.00
  end
end
```

## Agent Metadata

### Description
Plain English description of what the agent does:

```ruby
description "Monitors GitHub issues and alerts on critical bugs"
```

### Execution Mode
How the agent is triggered:

```ruby
mode :scheduled    # Runs on a schedule
mode :autonomous   # Runs continuously  
mode :reactive     # Responds to webhooks/events
```

### Schedule (for scheduled agents)
Cron expression defining when to run:

```ruby
schedule "0 9 * * *"      # 9 AM daily
schedule "*/15 * * * *"   # Every 15 minutes
schedule "0 0 * * 1"      # Every Monday at midnight
```

## Task Definitions

Tasks are individual work units with clear contracts. They come in two types:

### Neural Tasks (AI-Powered)

Initially, most tasks use AI to figure out what to do:

```ruby
task :analyze_logs,
  instructions: "scan error logs and identify critical issues",
  inputs: { logs: 'array' },
  outputs: { critical_issues: 'array', summary: 'string' }
```

**Key parts:**
- `instructions` - Natural language description of what to do
- `inputs` - Data this task needs (with types)
- `outputs` - Data this task produces (with types)

### Symbolic Tasks (Optimized Code)

After learning, tasks become optimized code blocks:

```ruby
task :fetch_recent_logs,
  inputs: { hours: 'integer' },
  outputs: { logs: 'array' }
do |inputs|
  since_time = Time.now - (inputs[:hours] * 3600)
  logs = execute_tool('logging', 'query', {
    since: since_time.iso8601,
    level: 'ERROR'
  })
  { logs: logs }
end
```

**Key differences:**
- No `instructions` (has explicit code instead)
- `do |inputs|` block contains the actual implementation
- More efficient and predictable than AI inference

## Main Logic

The `main` block coordinates task execution:

```ruby
main do |inputs|
  # Sequential execution
  logs = execute_task(:fetch_recent_logs, inputs: { hours: 24 })
  analysis = execute_task(:analyze_logs, inputs: logs)
  
  # Conditional logic
  if analysis[:critical_issues].any?
    execute_task(:send_alert, inputs: analysis)
  end
  
  # Return final result
  analysis
end
```

**Important concepts:**
- `execute_task(:name, inputs: {})` - Calls a task
- Task results are hashes matching the `outputs` schema
- You can use regular Ruby (if/else, loops, variables)
- The return value becomes the agent's output

## Output Handling

Defines what happens with the agent's final result:

### Neural Output
```ruby
output instructions: "send results to team via Slack"
```

### Symbolic Output
```ruby
output do |outputs|
  execute_tool('slack', 'post_message', {
    channel: '#alerts',
    text: "Found #{outputs[:critical_issues].length} critical issues"
  })
end
```

## Type System

Tasks use a simple type system for validation:

| Type | Description | Example |
|------|-------------|---------|
| `'string'` | Text data | `"hello world"` |
| `'integer'` | Whole numbers | `42` |
| `'number'` | Any number | `3.14` |
| `'boolean'` | True/false | `true` |
| `'array'` | List of items | `[1, 2, 3]` |
| `'hash'` | Key-value pairs | `{name: "Alice"}` |
| `'any'` | Any data type | anything |

## Constraints

Optional limits on agent behavior:

```ruby
constraints do
  timeout "30m"           # Maximum execution time
  max_iterations 100      # For autonomous agents
  daily_budget 10.00      # Maximum cost per day
  memory_limit "512Mi"    # Memory usage limit
end
```

## Learning Progression Example

Here's how a task evolves over time:

### Initially (Neural)
```ruby
task :calculate_metrics,
  instructions: "calculate average response time and error rate from logs",
  inputs: { logs: 'array' },
  outputs: { avg_response_time: 'number', error_rate: 'number' }
```

### After Learning (Symbolic)
```ruby
task :calculate_metrics,
  inputs: { logs: 'array' },
  outputs: { avg_response_time: 'number', error_rate: 'number' }
do |inputs|
  response_times = inputs[:logs].map { |log| log['response_time'] }.compact
  total_requests = inputs[:logs].length
  error_count = inputs[:logs].count { |log| log['status'] >= 400 }
  
  {
    avg_response_time: response_times.sum / response_times.length.to_f,
    error_rate: (error_count / total_requests.to_f) * 100
  }
end
```

## Common Patterns

### Error Handling
```ruby
main do |inputs|
  begin
    result = execute_task(:risky_operation, inputs: inputs)
    result
  rescue => e
    { error: e.message, success: false }
  end
end
```

### Conditional Execution
```ruby
main do |inputs|
  data = execute_task(:fetch_data, inputs: inputs)
  
  if data[:records].any?
    execute_task(:process_records, inputs: data)
  else
    { message: "No records to process" }
  end
end
```

### Parallel Task Execution
```ruby
main do |inputs|
  # Run multiple tasks in parallel
  results = execute_parallel([
    { name: :fetch_source1 },
    { name: :fetch_source2 }
  ])
  
  # Merge results
  execute_task(:merge_data, inputs: { 
    source1: results[0], 
    source2: results[1] 
  })
end
```

## Next Steps

- **[How Agents Work](how-agents-work.md)** - Understanding the synthesis process
- **[Agent Optimization](agent-optimization.md)** - How learning improves performance
- **[Using Tools](using-tools.md)** - How agents interact with external services