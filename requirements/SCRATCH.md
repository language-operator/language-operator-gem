# Knowledge Base

Living document of critical insights, patterns, and gotchas for this codebase.

## DSL Architecture (v1 - Current)

**Core Model:** Task/Main (imperative, replacing declarative workflow/step)

**Key Components:**
- `TaskDefinition`: Organic functions with stable contracts (inputs/outputs), evolving implementations (neural→symbolic)
- `MainDefinition`: Imperative entry point using Ruby control flow + `execute_task()`
- `TypeSchema`: 7-type system (string, integer, number, boolean, array, hash, any)

**Migration Strategy:**
- DSL v0 (workflow/step) marked deprecated but fully functional
- Both models supported in schema generation for backward compatibility
- Deprecation clearly noted in descriptions, safe methods updated

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

**JSON Schema Patterns:**
- `patternProperties` for flexible parameter validation without enumeration
- Regex patterns as keys validate both names and types dynamically
- Always include `examples` for complex schemas (aids understanding)

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
| `lib/language_operator/dsl/schema.rb` | JSON Schema generation (DSL→schema) | High (1100+ lines) |
| `lib/language_operator/dsl/task_definition.rb` | Task contract+validation | Medium (316 lines) |
| `lib/language_operator/dsl/main_definition.rb` | Main block execution | Low (115 lines) |
| `lib/language_operator/agent/task_executor.rb` | Neural/symbolic task execution | Medium (233 lines) |
| `lib/language_operator/agent/safety/ast_validator.rb` | Code security validation | High |
| `spec/language_operator/dsl/schema_spec.rb` | Schema test coverage (186 tests) | High |
| `spec/language_operator/agent/task_executor_spec.rb` | Task executor tests (19 tests) | Medium |

## Current Status

**Completed (2025-11-22):**
- ✅ Issue #26: Schema generation for task/main model
- ✅ Issue #25: AST validator updated for DSL v1
- ✅ Issues #21-23: TaskDefinition, MainDefinition, TypeCoercion implemented
- ✅ Issue #28: TaskExecutor for task execution runtime
- ✅ Issue #32 (partial): DependencyGraph and ParallelExecutor for implicit parallelism
- ✅ Issue #36: TraceAnalyzer for pattern detection with multi-backend support
- ✅ Issue #37: PatternDetector for learning eligibility and code generation
- ✅ Issue #52: Wizard consolidation - removed ux/ folder, consolidated under cli/wizards/

**Test Suite Health:**
- 135 examples, 0 failures, 2 pending (syntax error tests)
- 186 schema-specific tests, all passing
- 19 TaskExecutor tests, all passing
- 20 DependencyGraph tests, all passing
- 11 ParallelExecutor tests, all passing
- 39 TraceAnalyzer tests, all passing
- 31 PatternDetector tests, all passing
- Total learning tests: 70/70 passing
- RuboCop clean

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

**Architecture:**
- DependencyGraph: AST-based analysis extracts task dependencies from main block
- ParallelExecutor: Level-based execution using Concurrent::FixedThreadPool
- Default pool size: 4 threads (configurable)

**How It Works:**
1. Parse main block code to extract `execute_task` calls
2. Build dependency graph based on variable flow (which tasks use outputs from which other tasks)
3. Assign execution levels via topological sort
4. Execute each level in parallel (all tasks in level run concurrently)
5. Wait for level completion before starting next level

**Performance:**
- Measured 2x speedup for I/O-bound parallel tasks
- Thread pool handles > pool size tasks gracefully
- Fail-fast error handling (collects all errors, raises RuntimeError)

**Current Status (2025-11-14):**
- ✅ DependencyGraph: Complete and tested (20 tests)
- ✅ ParallelExecutor: Complete and tested (11 tests)
- ⚠️  Integration: Partial - blocked on variable-to-result mapping

**Blocking Issue:**
The fundamental challenge is mapping variable names from code to task results:
```ruby
# User code:
s1 = execute_task(:fetch1)
merged = execute_task(:merge, inputs: { s1: s1 })

# ParallelExecutor passes: { fetch1: {...} }
# But merge expects: { s1: {...} }
```

**Solution Options:**
1. Enhanced AST analysis (complex, 2-3 days)
2. Naming convention: var name = task name (simple, 1 day)
3. Explicit dependency DSL (medium, 1-2 days)
4. Defer to follow-up issue (pragmatic, 0 days)

**Recommendation:** Option 4 - defer integration, ship infrastructure

## Learning System (Phase 4)

**Architecture (2025-11-19):**
- `TraceAnalyzer`: Query OTLP backends for task execution traces
- `PatternDetector`: Convert deterministic patterns to symbolic Ruby code
- Adapter Pattern: Pluggable backend support (SigNoz, Jaeger, Tempo)
- Pattern Detection: Analyze tool call sequences for consistency
- Code Generation: Tool sequences → chained execute_task calls

**Backend Support:**
1. **SigNoz** (Primary): ClickHouse-backed, POST /api/v5/query_range, AND/OR filters
2. **Jaeger**: HTTP /api/traces with tags filter (gRPC planned for future)
3. **Tempo**: GET /api/search with TraceQL syntax

**Auto-Detection Chain:** signoz → jaeger → tempo → no learning (graceful degradation)

**Pattern Consistency Algorithm:**
- Groups executions by input signature (serialized inputs)
- For each group: finds most common tool call sequence
- Calculates weighted average consistency across all input signatures
- Threshold: 0.85 (85% consistency required for learning)

**Configuration:**
```ruby
ENV['OTEL_QUERY_ENDPOINT'] = 'https://example.signoz.io'
ENV['OTEL_QUERY_API_KEY'] = 'api-key'  # SigNoz only
ENV['OTEL_QUERY_BACKEND'] = 'signoz'   # Optional explicit selection
```

**Pattern Detector Algorithm:**
1. Pre-flight checks: consistency >= 0.85, executions >= 10, pattern exists
2. Parse pattern: "db_fetch → cache_get" → [:db_fetch, :cache_get]
3. Generate code: Chained execute_task calls with variable passing
4. Validate: ASTValidator ensures no dangerous methods
5. Return: Complete Ruby DSL v1 agent definition

**Code Generation Example:**
```ruby
# Input: "db_fetch → cache_get → api_send"
# Output:
step1_result = execute_task(:db_fetch, inputs: inputs)
step2_result = execute_task(:cache_get, inputs: step1_result)
final_result = execute_task(:api_send, inputs: step2_result)
{ result: final_result }
```

**Key Learnings:**
- WebMock stubs must be set up BEFORE TraceAnalyzer initialization (auto-detection)
- Input normalization uses `.sort.to_h.to_s` - different values = different signatures
- All adapters normalize to common span format: `{span_id, trace_id, name, timestamp, duration_ms, attributes}`
- TaskTracer already emits required attributes: `task.name`, `task.input.*`, `task.output.*`, `gen_ai.tool.name`
- Generated code must include frozen_string_literal and require 'language_operator'
- Agent names convert underscores to hyphens, append "-symbolic" suffix

## CLI Architecture (Wizards)

**Consolidated Structure (2025-11-22):**
- All wizards in `lib/language_operator/cli/wizards/`
- Common helpers in `lib/language_operator/cli/helpers/`
- All wizards use `UxHelper` pattern (no direct `Pastel.new` or `TTY::Prompt.new`)

**Key Wizards:**
- `AgentWizard` - Interactive agent creation
- `ModelWizard` - LLM model configuration
- `QuickstartWizard` - First-time setup

**Helper Modules:**
- `UxHelper` - Provides `pastel`, `prompt`, `spinner`, `table`, `box`
- `ValidationHelper` - Common input validation (URLs, K8s names, secrets)
- `ProviderHelper` - LLM provider testing and model fetching

**Pattern:**
```ruby
class MyWizard
  include Helpers::UxHelper
  include Helpers::ValidationHelper

  def run
    puts box("Welcome!")
    name = ask_k8s_name("Name:")
    # wizard logic
  end
end
```

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
