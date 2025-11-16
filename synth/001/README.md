# 001 - Minimal Viable Synthesis

## Instructions

"Say something in your logs"

## Significance

This is the **foundational validation** of the DSL v1 architecture. It proves that the entire synthesis pipeline works end-to-end with the simplest possible agent.

Think of this as the "Hello World" of organic function synthesis - before we can validate learning, progressive synthesis, or neural task execution, we must first prove we can synthesize and execute *anything at all*.

## What This Demonstrates

### 1. Basic Synthesis Flow Works
- **Natural language → Agent code generation** - The synthesis template can produce valid Ruby DSL
- **Go operator synthesis** - The operator's synthesis controller generates executable code
- **ConfigMap storage** - Synthesized code is stored and mounted correctly

### 2. DSL v1 Core Primitives
- **`task` definition** - Symbolic task with explicit implementation block
- **`main` block** - Explicit entry point with imperative control flow
- **`execute_task`** - Task invocation mechanism works
- **`output` block** - Result handling and processing

### 3. Ruby Runtime Execution
- **DSL parsing** - Ruby gem can load and parse synthesized agents
- **Task execution** - `TaskExecutor` can execute symbolic tasks
- **Agent lifecycle** - Agent runs to completion successfully

### 4. Symbolic Task Execution
```ruby
task :generate_log_message do |_inputs|
  { message: 'Test agent is saying hello!' }
end
```

This is a **symbolic organic function** - explicit code implementation with a stable contract:
- **Contract**: `outputs: { message: 'string' }`
- **Implementation**: Returns hard-coded message
- **Caller**: `main` block calls via `execute_task(:generate_log_message)`

## Why This Matters

### Validates the Foundation
Before building complex features (learning, neural execution, re-synthesis), we must prove the basic pipeline works:

```
User Instruction
    ↓
Synthesis (Go operator)
    ↓
ConfigMap (agent.rb)
    ↓
Ruby Runtime Execution
    ↓
Output
```

### Establishes DSL v1 Baseline
This test uses the **new DSL v1 model** (task/main) rather than the old workflow/step model. It proves:
- ✅ `task` replaces `step`
- ✅ `main` replaces implicit `workflow`
- ✅ Imperative control flow works
- ✅ Organic function abstraction is viable

### No Neural Complexity Yet
By using a **purely symbolic task**, this test isolates synthesis validation from LLM execution complexity:
- No LLM API calls to fail
- No neural task instruction parsing
- No MCP server connections
- Just pure: synthesize → execute → output

## What It Doesn't Test

This test intentionally **does not** validate:
- ❌ Neural task execution (that's test 002)
- ❌ Scheduled mode (that's test 002)
- ❌ Learning/re-synthesis (future tests)
- ❌ MCP tool integration (future tests)
- ❌ Error handling/recovery (future tests)

## Success Criteria

✅ **Agent synthesizes successfully** - No syntax errors in generated code
✅ **Agent executes** - Runtime can load and run the agent
✅ **Task executes** - `execute_task(:generate_log_message)` returns expected output
✅ **Output appears** - Message is logged to stdout
✅ **Process completes** - Agent exits cleanly (exit code 0)

## Connection to DSL v1 Proposal

From [dsl-v1.md](../requirements/proposals/dsl-v1.md):

> **Core Insight:** Functions with stable contracts can evolve from neural to symbolic implementation through observation, creating a real-time synthesis system that improves with usage.

This test validates the **"stable contract"** foundation:
- The task has a contract: `outputs: { message: 'string' }`
- The `main` block calls it: `execute_task(:generate_log_message)`
- The implementation is symbolic (explicit code)

Test 002 will add the **"evolving implementation"** part (neural execution). But first, we prove the contract abstraction works.

## Running the Test

```bash
# Execute the synthesized agent
ruby synth/001/agent.rb

# Expected output:
# Test agent is saying hello!
```

## What Success Looks Like

```
[INFO] Loading agent: test-agent
[INFO] Executing main block
[INFO] Executing task: generate_log_message
[INFO] Task returned: {:message=>"Test agent is saying hello!"}
[INFO] Processing output
Test agent is saying hello!
[INFO] Agent completed successfully
```

---

**Status**: ✅ VALIDATED - Basic synthesis pipeline works

**Next**: Test 002 validates neural task execution (the organic function secret sauce)