# How Agents Work

Language Operator transforms your natural language descriptions into working AI agents through a process called synthesis. This guide explains what happens when you create an agent.

## The Agent Creation Process

### 1. You Describe What You Want

```bash
langop agent create daily-report
# Interactive wizard asks:
# - What should this agent do?
# - When should it run?
# - What tools does it need?
```

You describe your agent in plain English:
- "Generate a daily sales report from our database"
- "Respond to GitHub pull request webhooks with code reviews"  
- "Monitor our API and alert on errors"

### 2. Language Operator Synthesizes Code

Behind the scenes, Language Operator creates a complete agent definition that includes:
- **Tasks** - Individual work units with clear input/output contracts
- **Main logic** - The execution flow that coordinates tasks
- **Configuration** - Scheduling, constraints, and resource limits

### 3. Your Agent Runs and Learns

Initially, your agent uses AI to figure out how to accomplish tasks. Over time, it learns patterns and generates optimized code automatically.

## Agent Structure

When Language Operator synthesizes an agent, it creates code structured like this:

### Tasks (Work Units)

Each task has a clear contract defining what data goes in and what comes out:

```ruby
# A task that fetches sales data
task :fetch_sales_data,
  instructions: "get yesterday's sales from the database",
  inputs: {},
  outputs: { sales: 'array', total: 'number' }
```

### Main Logic (Coordination)

The main block coordinates tasks and handles the overall flow:

```ruby
main do |inputs|
  # Get the data
  sales = execute_task(:fetch_sales_data)
  
  # Generate the report
  report = execute_task(:generate_report, inputs: sales)
  
  # Return the result
  report
end
```

### Output Handling

Defines what happens with the results:

```ruby
output do |outputs|
  # Send the report via email
  execute_tool('email', 'send', {
    to: 'team@company.com',
    subject: 'Daily Sales Report',
    body: outputs[:report]
  })
end
```

## How Tasks Execute

### Neural Tasks (AI-Powered)

Initially, tasks use AI to figure out what to do:

```ruby
task :analyze_data,
  instructions: "identify trends and anomalies in the sales data",
  inputs: { data: 'array' },
  outputs: { trends: 'array', anomalies: 'array' }

# Language Operator uses AI to:
# 1. Understand the instruction
# 2. Call appropriate tools
# 3. Process the results
# 4. Return data matching the output schema
```

### Symbolic Tasks (Optimized Code)

Over time, agents learn patterns and generate optimized code:

```ruby
task :analyze_data,
  inputs: { data: 'array' },
  outputs: { trends: 'array', anomalies: 'array' }
do |inputs|
  # Generated code based on learned patterns
  trends = inputs[:data].group_by { |item| item[:category] }
                        .map { |cat, items| { category: cat, total: items.sum { |i| i[:amount] } } }
  
  anomalies = inputs[:data].select { |item| item[:amount] > 10000 }
  
  { trends: trends, anomalies: anomalies }
end
```

## Agent Lifecycle

### Phase 1: Initial Synthesis
- You describe what you want
- Language Operator creates a working agent
- All tasks start as neural (AI-powered)

### Phase 2: Learning
- Agent runs and accomplishes tasks using AI
- Language Operator observes patterns in how tasks execute
- System identifies opportunities for optimization

### Phase 3: Optimization
- Frequently-used patterns become optimized code
- AI tasks gradually become efficient symbolic code
- Performance improves and costs decrease

### Phase 4: Continuous Improvement
- Agent continues learning new patterns automatically
- System continuously adapts to changing requirements
- Optimization happens transparently in the background

## Key Benefits

**Immediate Functionality**: Your agent works right away, even for complex tasks

**Automatic Optimization**: No manual performance tuning required

**Cost Reduction**: AI usage decreases as agents learn efficient patterns

**Reliability**: Learned patterns are more predictable than AI inference

**Adaptability**: Agents can learn new patterns as requirements change

## Next Steps

- **[Understanding Generated Code](understanding-generated-code.md)** - Learn to read synthesized agents
- **[Using Tools](using-tools.md)** - How agents interact with external services