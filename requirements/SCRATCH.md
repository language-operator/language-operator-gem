# Knowledge Base

Living document of critical insights, patterns, and gotchas for this codebase.

## Project

This is the Gem component of language-operator, an operator for Kubernetes that orchestrates agentic workloads.  Language clusters are manipulated by the `aictl` command, which you can run from source via `bundle exec bin/aictl`.

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

**Task Flows:**
- **Neural:** TaskExecutor → LLM prompt → JSON parsing → validation (fail fast)
- **Symbolic:** TaskDefinition#call → code execution → validation (fail fast)

**Runtime:** Agent detects DSL v1/v0, creates TaskExecutor, executes via mode (autonomous/scheduled)

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

**Components:** TraceAnalyzer (OTLP query) + PatternDetector (pattern→code generation)
**Threshold:** 85% consistency, 10+ executions → symbolic conversion
**Config:** OTEL_QUERY_ENDPOINT, OTEL_QUERY_API_KEY, OTEL_QUERY_BACKEND
**Gotcha:** WebMock stubs needed before TraceAnalyzer init (auto-detection in constructor)

## CLI Architecture

**Pattern:** Wizards in `cli/wizards/` + Helpers in `cli/helpers/` + UxHelper for TTY components

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

## Current Priorities (2025-11-24)

**P1 - Resource/Performance:**
- #61 - Resource leak in cluster list (likely duplicate of resolved #62/#67)

**P2 - UX/Config:**
(None currently)

**P3 - Enhancements:**
- #51 - Include complete MCP tool schemas
- #39 - Update examples to task/main
- #40 - Performance optimization
- #41 - Comprehensive test suite

**Recently Completed (Major Issues):**
- ✅ #66, #55, #59, #62, #67 - CLI and K8s client fixes
- ✅ #60, #69, #50, #68, #64, #46, #48 - Security vulnerabilities resolved
- ✅ #45, #52, #44, #54, #53 - Runtime and UX improvements
- ✅ #49 - CLI exits on invalid selection (2025-11-24) - Fixed UserPrompts.select to retry instead of exit
- ✅ #47 - Silent type conversion failures (2025-11-24) - Replaced to_i/to_f with strict Integer()/Float() validation
