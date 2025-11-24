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

### Task Definitions

Tasks are Ruby blocks that process inputs and return outputs:

```ruby
task :analyze_logs do |inputs|
  # Task implementation - this can be:
  # 1. Simple Ruby code
  # 2. Calls to AI for complex reasoning
  # 3. MCP tool usage (when available)
  
  logs = inputs[:logs] || []
  critical_issues = logs.select { |log| log[:level] == 'ERROR' }
  
  {
    critical_issues: critical_issues,
    summary: "Found #{critical_issues.length} critical issues"
  }
end
```

**Key parts:**
- Task name (`:analyze_logs`)
- Input parameter (`inputs` hash)
- Ruby block with implementation
- Return value (hash with results)

### Task Evolution

Tasks can evolve from simple implementations to more sophisticated ones:

```ruby
# Simple implementation
task :fetch_recent_logs do |inputs|
  hours = inputs[:hours] || 24
  since_time = Time.now - (hours * 3600)
  
  # In a real implementation, this might call MCP tools
  # or use AI synthesis for complex queries
  { logs: [], since: since_time }
end
```

## Main Logic

The `main` block coordinates task execution and defines the agent's workflow:

```ruby
main do |inputs|
  # Task execution - tasks are called as methods
  logs = fetch_recent_logs(hours: 24)
  analysis = analyze_logs(logs: logs[:logs])
  
  # Conditional logic
  if analysis[:critical_issues].any?
    send_alert(analysis)
  end
  
  # Return final result
  analysis
end
```

**Important concepts:**
- Tasks are called as method names
- Task results are returned as hashes
- Standard Ruby control flow (if/else, loops, variables)
- The return value becomes the agent's output
- Tasks can be chained together

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