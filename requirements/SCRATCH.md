# Knowledge Base

Living document of critical insights, patterns, and gotchas for this codebase.

## DSL Architecture (v1)

**Core Model:** Task/Main (imperative) - replaces v0 workflow/step (declarative, deprecated)

**Key Components:**
- `TaskDefinition`: Stable contracts (inputs/outputs), evolving implementations (neural→symbolic)
- `MainDefinition`: Imperative entry point with Ruby control flow + `execute_task()`
- `TypeSchema`: 7-type system (string, integer, number, boolean, array, hash, any)

**Backward Compatibility:** v0 (workflow/step) remains functional, marked deprecated

## Testing Patterns

**RSpec Best Practices:**
- Use single-quoted heredocs (`<<~'RUBY'`) when testing code with interpolation to avoid context issues
- RuboCop requires uppercase annotation keywords with colon+space (e.g., `# TODO: fix`)
- Symbol hash keys: Use `.keys.first.to_s` or `.values.first` for pattern properties, not direct string access

**Parser Gem Quirks:**
- Very forgiving - accepts syntax variations Ruby rejects
- Makes syntax error testing difficult (2 pending tests skipped for this reason)
- AST validation works well for semantic checks, less so for syntactic ones

## Schema Generation

**Key Pattern:** `patternProperties` with regex keys for dynamic type validation without enumeration

## Security (AST Validator)

**Safe Methods Lists:**
- DSL v1: `task`, `main`, `execute_task`, `inputs`, `outputs`, `instructions`
- DSL v0: Removed `workflow`, `step`, `depends_on`, `prompt`
- Helpers: Added `TypeCoercion` for validation

**Blocked Patterns:**
- System execution: `system`, `exec`, `spawn`, `fork`
- Dynamic evaluation: `eval`, `instance_eval`, `class_eval`, `send`
- File operations: Direct `File` access, dangerous IO
- Works in both task blocks and main blocks

## Critical File Map

| File | Purpose | Complexity |
|------|---------|------------|
| `dsl/schema.rb` | JSON Schema generation (DSL→schema) | High (1100+ lines) |
| `dsl/task_definition.rb` | Task contract + validation | Medium |
| `dsl/main_definition.rb` | Main block execution | Low |
| `agent/task_executor.rb` | Neural/symbolic task execution | Medium |
| `agent/safety/ast_validator.rb` | Code security validation | High |
| `agent/learning/trace_analyzer.rb` | OTLP query adapter | Medium |
| `agent/learning/pattern_detector.rb` | Pattern→code generation | Medium |

## Current Status

**Completed:**
- ✅ DSL v1 (task/main model): Schema, AST validator, core definitions
- ✅ Task execution runtime: Neural & symbolic modes
- ✅ Parallel execution infrastructure: DependencyGraph & ParallelExecutor (not yet integrated)
- ✅ Learning system: TraceAnalyzer & PatternDetector with multi-backend support
- ✅ CLI consolidation: All wizards under cli/wizards/ with UxHelper pattern

**Test Suite:** All passing, RuboCop clean

## Task Execution (DSL v1)

**Neural Task Flow:**
1. TaskExecutor builds prompt from task instructions + inputs + output schema
2. LLM called via `agent.send_message` with full tool access
3. Response parsed as JSON (supports ```json blocks or raw objects)
4. Outputs validated against schema via TaskDefinition#validate_outputs
5. Fail fast on any error (critical for re-synthesis)

**Symbolic Task Flow:**
1. TaskExecutor calls TaskDefinition#call with inputs and self as context
2. TaskDefinition validates inputs, executes code block, validates outputs
3. Context provides `execute_task`, `execute_llm`, `execute_tool` helpers
4. Fail fast on any error

**Runtime Wiring:**
- Agent module detects DSL v1 (main block) vs v0 (workflow)
- Autonomous mode: `execute_main_block` creates TaskExecutor, calls MainDefinition
- Scheduled mode: `Scheduler#start_with_main` creates TaskExecutor, schedules main
- MainDefinition receives TaskExecutor as execution context via instance_exec

## Parallel Execution (DSL v1)

**Infrastructure:** DependencyGraph (AST-based) + ParallelExecutor (thread pool-based)

**Implementation Status:** Complete but not integrated - blocked on variable-to-result mapping challenge:
```ruby
s1 = execute_task(:fetch1)
merged = execute_task(:merge, inputs: { s1: s1 })
# ParallelExecutor passes { fetch1: {...} } but merge expects { s1: {...} }
```

**Performance:** 2x speedup for I/O-bound parallel tasks in tests

## Learning System

**Architecture:**
- `TraceAnalyzer`: Query OTLP backends (SigNoz/Jaeger/Tempo) for task execution traces
- `PatternDetector`: Convert deterministic patterns to symbolic Ruby code
- Auto-detection chain: signoz → jaeger → tempo → graceful degradation

**Pattern Detection:**
- Threshold: 85% consistency, 10+ executions required
- Groups by input signature (serialized, sorted)
- Generates chained execute_task calls from tool sequences
- Validates via ASTValidator before returning code

**Config:**
```ruby
ENV['OTEL_QUERY_ENDPOINT'] = 'https://example.signoz.io'
ENV['OTEL_QUERY_API_KEY'] = 'api-key'  # SigNoz only
ENV['OTEL_QUERY_BACKEND'] = 'signoz'   # Optional
```

**Key Details:**
- WebMock stubs needed before TraceAnalyzer init (auto-detection happens in constructor)
- Input normalization: `.sort.to_h.to_s` - different values = different signatures
- Required span attributes: `task.name`, `task.input.*`, `task.output.*`, `gen_ai.tool.name`

## CLI Architecture

**Structure:**
- Wizards: `cli/wizards/` (AgentWizard, ModelWizard, QuickstartWizard)
- Helpers: `cli/helpers/` (UxHelper, ValidationHelper, ProviderHelper)
- Pattern: All wizards `include UxHelper` (provides `pastel`, `prompt`, `spinner`, `table`, `box`)

## Quick Wins / Common Gotchas

1. **Hash Key Access:** Ruby symbols ≠ strings. Always check key types in tests.
2. **Heredoc Interpolation:** Use `'RUBY'` (single quotes) to prevent RSpec context leakage.
3. **Pattern Properties:** Schema validation via regex - powerful for type systems.
4. **Migration-Friendly:** Keep deprecated features functional with clear warnings.
5. **Parser Tolerance:** Don't rely on parser for syntax validation - it's too forgiving.
6. **Tool Execution:** Tools accessed via LLM interface, not direct RPC (execute_tool → execute_llm)
7. **Error Wrapping:** TaskExecutor wraps errors in RuntimeError with task context for debugging
8. **Concurrent Ruby Futures:** Use `future.wait` + `future.rejected?` to check status, not `rescue` around `future.value`
9. **Logger Constants:** Use `::Logger::WARN` not `Logger::WARN` to avoid namespace conflicts
10. **WebMock Timing:** Stub HTTP calls before object initialization if constructor makes requests
11. **Wizard Pattern:** Always use `UxHelper` for TTY components, never instantiate directly

## Current Priorities (2025-11-23)

**Issue Prioritization (by functional dependency):**

**P0 - Blocks Core Functionality:**
1. #45 (READY) - NoMethodError in Scheduler: breaks ALL scheduled agents
2. #46 - Unsafe YAML.load_file: security + Ruby 3.1+ compatibility crash
3. #44 - NoMethodError for missing mcp_servers: crashes minimal configs

**P1 - Security Vulnerabilities:**
4. #48 - Path traversal in Dsl.load_file
5. #50 - Request body consumed without rewind

**P2 - UX/Config Issues:**
6. #47 - Silent type conversion failures
7. #49 - CLI exits on invalid selection

**P3 - Enhancements:**
8. #51 - Include complete MCP tool schemas
9. #39 - Update examples to task/main
10. #40 - Performance optimization
11. #41 - Comprehensive test suite

**Rationale for #45 Priority:**
- P0 blocker making scheduled agents completely unusable
- Simple fix (remove `.cron` accessor or change AgentDefinition storage)
- No dependencies on other issues
- Enables testing/validation of scheduled agent functionality
