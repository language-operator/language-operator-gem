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

Validates that agents can run on a schedule using cron syntax:
- ✅ **Mode dispatch** - Runtime recognizes `:scheduled` mode
- ✅ **Cron parsing** - Schedule expression is parsed correctly
- ✅ **Scheduler integration** - `rufus-scheduler` integration works
- ✅ **Repeated execution** - Agent runs multiple times automatically

### 3. Complete Neural Execution Flow
```
┌─────────────────────────────────────────────────────────┐
│  Scheduler Triggers (every 10 minutes)                  │
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

### No Other Framework Can Do This

| Framework | Neural Execution | Symbolic Execution | Transparent Evolution |
|-----------|-----------------|-------------------|---------------------|
| **Language Operator** | ✅ Instructions-based tasks | ✅ Code blocks | ✅ Contract abstraction |
| LangChain | ❌ Chains are static | ✅ Python code | ❌ No abstraction |
| AutoGen | ✅ Conversational | ❌ No symbolic optimization | ❌ No contracts |
| CrewAI | ✅ Agents with prompts | ❌ No learning | ❌ No abstraction |

## The Organic Function In Action

**What makes this revolutionary:**

1. **Instant Working Code**: User says "tell me a fortune" → Agent runs immediately (neural)
2. **No Manual Implementation**: Never wrote `execute_llm()` or fortune generation logic
3. **Type Safety**: Output is validated against schema
4. **Learning Ready**: After N runs, system can observe patterns and synthesize symbolic implementation
5. **Zero Breaking Changes**: When re-synthesized, `main` block never changes

**This is what "living code" means**: Code that starts neural (flexible, works immediately) and becomes symbolic (fast, cheap) through observation, all while maintaining a stable contract.

---

**Status**: ✅ VALIDATED - Neural organic functions work

**Next**: Test 003+ will validate learning, re-synthesis, and progressive neural→symbolic evolution

---

## Technical Deep Dive

### How Neural Execution Works

When `execute_task(:generate_fortune)` is called:

1. **Task Lookup**: Runtime finds task definition in agent
2. **Type Check**: Task has `instructions`, no code block → Neural execution
3. **Prompt Construction**:
   ```
   You are an AI agent executing a task.

   Task: generate_fortune
   Instructions: Generate a random fortune for the user

   Inputs: {}

   You must return a response matching this schema:
   { fortune: 'string' }

   [Available tools if any MCP servers connected]
   ```
4. **LLM Invocation**: Send prompt to configured LLM (via `ruby_llm`)
5. **Response Parsing**: Extract structured output from LLM response
6. **Schema Validation**: Ensure response matches `{ fortune: 'string' }`
7. **Return**: Validated output returned to caller

### What This Enables Later

Once this works, the learning system can:

1. **Observe Execution**: Collect OpenTelemetry traces showing what the LLM did
2. **Detect Patterns**: Analyze if LLM behavior is deterministic
3. **Synthesize Code**: Generate symbolic implementation from observed pattern
4. **Re-Deploy**: Update ConfigMap with learned code
5. **Transparent Evolution**: `main` block continues working identically

**This test proves step 1 works** (neural execution). Future tests prove steps 2-5.