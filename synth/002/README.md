# 002 - Neural Task Execution & Scheduled Mode

## Instructions

"Tell me a fortune every 10 minutes."

## Significance

This is the **core validation of the Organic Function concept** - the secret sauce that makes DSL v1 revolutionary.

While test 001 proved we can synthesize and execute code at all, this test proves we can execute **neural organic functions** - tasks defined purely by instructions where the LLM decides implementation at runtime.

This is what differentiates Language Operator from every other agent framework. No other system can do this.

## What This Demonstrates

### 1. Neural Task Definition and Execution
```ruby
task :generate_fortune,
  instructions: "Generate a random fortune for the user",
  inputs: {},
  outputs: { fortune: 'string' }
```

This is a **neural organic function** - the implementation exists only as natural language instructions:
- ✅ **No explicit code block** - Task has no `do |inputs| ... end`
- ✅ **LLM synthesizes behavior** - Runtime passes instructions to LLM at execution time
- ✅ **Contract enforcement** - Output must match `{ fortune: 'string' }` schema
- ✅ **Caller transparency** - `execute_task(:generate_fortune)` works identically to symbolic tasks

**This is the organic function abstraction in action**: The caller doesn't know (and doesn't care) whether the task is neural or symbolic.

### 2. Scheduled Execution Mode
```ruby
mode :scheduled
schedule "*/10 * * * *"  # Every 10 minutes
```

Validates that agents can run on a schedule using Kubernetes CronJobs:
- ✅ **Mode dispatch** - Runtime recognizes `:scheduled` mode
- ✅ **Cron parsing** - Schedule expression is used by Kubernetes CronJob
- ✅ **Kubernetes-native** - CronJob creates pods on schedule
- ✅ **Execute once and exit** - Each pod runs the task once, then terminates
- ✅ **Repeated execution** - Kubernetes creates new pods per schedule

### 3. Complete Neural Execution Flow
```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes CronJob Triggers (every 10 minutes)         │
│  Creates new pod for this execution                     │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Pod Starts → Agent Runtime Loads                       │
│  Mode: scheduled → Execute once and exit                │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  main Block Executes                                    │
│  execute_task(:generate_fortune) called                 │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  TaskExecutor Checks Task Type                          │
│  → Task has no block (neural)                           │
│  → Task has instructions                                │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Neural Execution Path                                  │
│  1. Build LLM prompt with instructions                  │
│  2. Include output schema constraint                    │
│  3. Call LLM (with any available MCP tools)             │
│  4. Parse LLM response                                  │
│  5. Validate output matches schema                      │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Output Block Processes Result                          │
│  puts outputs[:fortune]                                 │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Agent Exits → Pod Terminates                           │
│  Kubernetes waits for next cron schedule                │
└─────────────────────────────────────────────────────────┘
```

### 4. Type Validation
The runtime must validate that the LLM's response matches the output schema:
- **Expected**: `{ fortune: 'string' }`
- **Validation**: Type coercion and schema checking
- **Error handling**: If LLM returns wrong type, raise validation error

## Why This Matters

### The Organic Function Secret Sauce

This test validates the **fundamental innovation** of DSL v1:

**Traditional Approach (LangChain, AutoGen, etc.):**
```python
# You write explicit code
def generate_fortune():
    return random.choice(FORTUNES)

# Caller uses it
result = generate_fortune()
```

**Language Operator Approach (Organic Functions):**
```ruby
# You write a contract + instructions (neural)
task :generate_fortune,
  instructions: "Generate a random fortune for the user",
  outputs: { fortune: 'string' }

# Caller uses it identically
result = execute_task(:generate_fortune)

# Later, system learns and synthesizes (symbolic)
task :generate_fortune,
  outputs: { fortune: 'string' }
do |inputs|
  execute_llm("Tell me a fortune")
end

# Caller STILL uses it identically - no breaking changes!
result = execute_task(:generate_fortune)
```

**The Magic**: The contract (`outputs: { fortune: 'string' }`) is stable. The implementation (neural vs symbolic) can change without breaking callers.

### Enables Progressive Synthesis

This test proves the foundation for learning:

1. **Run 1-10**: Neural execution (this test validates this works)
2. **System observes**: LLM always calls the same tools, returns same pattern
3. **Run 11+**: Symbolic execution (future re-synthesis test validates this)

**The critical insight**: Because `execute_task(:generate_fortune)` works the same whether the task is neural or symbolic, we can replace implementations without breaking the `main` block.

## The Organic Function In Action

**What makes this revolutionary:**

1. **Instant Working Code**: User says "tell me a fortune" → Agent runs immediately (neural)
2. **No Manual Implementation**: Never wrote `execute_llm()` or fortune generation logic
3. **Type Safety**: Output is validated against schema
4. **Learning Ready**: After N runs, system can observe patterns and synthesize symbolic implementation
5. **Zero Breaking Changes**: When re-synthesized, `main` block never changes

**This is what "living code" means**: Code that starts neural (flexible, works immediately) and becomes symbolic (fast, cheap) through observation, all while maintaining a stable contract.