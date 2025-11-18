# 001 - Minimal Viable Synthesis

## Instructions

"Say something in your logs"

## Significance

This is a basic validation of the DSL v1 architecture. It checks that the synthesis pipeline works end-to-end with a simple agent.

This is essentially a "Hello World" test - before attempting more complex features like learning or neural task execution, we need to verify that we can synthesize and execute basic functionality.

## What This Demonstrates

### 1. Basic Synthesis Flow Works
- **Natural language → Agent code generation** - The synthesis template produces valid Ruby DSL
- **Go operator synthesis** - The operator's synthesis controller generates executable code
- **ConfigMap storage** - Synthesized code is stored and mounted

### 2. DSL v1 Core Primitives
- **`task` definition** - Symbolic task with explicit implementation block
- **`main` block** - Explicit entry point with imperative control flow
- **`execute_task`** - Task invocation mechanism
- **`output` block** - Result handling and processing

### 3. Ruby Runtime Execution
- **DSL parsing** - Ruby gem loads and parses synthesized agents
- **Task execution** - `TaskExecutor` executes symbolic tasks
- **Agent lifecycle** - Agent runs to completion

### 4. Symbolic Task Execution
```ruby
task :generate_log_message do |_inputs|
  { message: 'Test agent is saying hello!' }
end
```

This is a symbolic organic function - explicit code implementation with a defined contract:
- **Contract**: `outputs: { message: 'string' }`
- **Implementation**: Returns hard-coded message
- **Caller**: `main` block calls via `execute_task(:generate_log_message)`

## Why This Matters

### Validates the Foundation
Before building more complex features (learning, neural execution, re-synthesis), we need to verify the basic pipeline works:

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
This test uses the new DSL v1 model (task/main) rather than the old workflow/step model. It verifies:
- ✅ `task` replaces `step`
- ✅ `main` replaces implicit `workflow`
- ✅ Imperative control flow works
- ✅ Organic function abstraction works

### No Neural Complexity Yet
By using a purely symbolic task, this test isolates synthesis validation from LLM execution complexity:
- No LLM API calls to fail
- No neural task instruction parsing
- No MCP server connections
- Just: synthesize → execute → output