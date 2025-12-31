# Language Operator Knowledge Base

Critical insights and patterns for the language-operator Ruby gem.

## Quick Reference

- **Project**: Kubernetes agent orchestration with `langop` CLI (`bundle exec bin/langop`)
- **DSL**: Task/Main model (v1) replaces workflow/step (v0, deprecated)
- **Components**: TaskDefinition (contracts), MainDefinition (imperative), TypeSchema (7 types)
- **Test Status**: Unit tests passing (384 examples), integration tests have pre-existing failures

## Key Patterns

**Testing:**
- Use `<<~'RUBY'` (single quotes) to prevent RSpec context leakage in heredocs
- Parser gem is forgiving - use AST validation for semantic, not syntactic checks
- Hash keys: Use `.keys.first.to_s` for pattern properties access

**Schema:** `patternProperties` with regex keys for dynamic type validation

**Security (AST Validator):**
- Allowed: `task`, `main`, `execute_task`, `inputs`, `outputs`, `instructions`, `TypeCoercion`
- Blocked: `system`, `exec`, `spawn`, `fork`, `eval`, `instance_eval`, `class_eval`, `send`, dangerous file ops

## Architecture Overview

**Key Files:**
- `dsl/schema.rb` (1100+ lines) - JSON Schema generation
- `agent/safety/ast_validator.rb` - Code security validation
- `agent/task_executor.rb` - Neural/symbolic task execution
- `agent/learning/trace_analyzer.rb` - OTLP query adapter

**Core Systems:**
- ✅ DSL v1: Schema, AST validator, definitions
- ✅ Task execution: Neural & symbolic modes
- ✅ Parallel execution: DependencyGraph & ParallelExecutor (not integrated - variable mapping issue)
- ✅ Learning system: TraceAnalyzer & PatternDetector (85% consistency, 10+ executions → symbolic)
- ✅ CLI: Unified wizards pattern with UxHelper
- ✅ Agent runtime: Persistent mode for autonomous agents (AGENT_IDLE_TIMEOUT, AGENT_NEW_INSTRUCTION)
- ❌ Kubernetes events: **REMOVED** - Timeout-prone event emission replaced by OpenTelemetry observability

## Implementation Details

**Task Execution:**
- Neural: TaskExecutor → LLM → JSON → validation
- Symbolic: TaskDefinition#call → code → validation
- Runtime: Agent detects DSL version, creates TaskExecutor

**Parallel Execution (Blocked):**
- Infrastructure: DependencyGraph + ParallelExecutor (2x I/O speedup)
- Issue: Variable-to-result mapping (`s1 = execute_task(:fetch1)` vs `{fetch1: {...}}`)

**Learning System:**
- TraceAnalyzer (OTLP) + PatternDetector
- Config: OTEL_QUERY_ENDPOINT, OTEL_QUERY_API_KEY, OTEL_QUERY_BACKEND
- Gotcha: WebMock stubs needed before TraceAnalyzer init

**JSON Parsing Resilience (Neural Tasks):**
- Retry mechanism for malformed LLM responses (reduces crash rate from 66% to <10%)
- Parsing-specific retry with strict JSON-only instructions
- Flag reset at task start to prevent infinite loops in scheduled agents

## Common Gotchas

1. **Hash Keys:** Ruby symbols ≠ strings - check types in tests
2. **Heredocs:** Use `<<~'RUBY'` (single quotes) to prevent RSpec context leakage
3. **Parser:** Too forgiving for syntax validation - use AST for semantic checks
4. **Tools:** Access via LLM interface (`execute_llm`), not direct RPC
5. **Futures:** Use `future.wait` + `future.rejected?`, not `rescue` around `future.value`
6. **Constants:** Use `::Logger::WARN` to avoid namespace conflicts
7. **WebMock:** Stub HTTP before object initialization if constructor makes requests
8. **UX:** Always use `UxHelper` for TTY components

## Current Active Issues (2025-12-27)

**P1 - Test Failures (Integration Suite):**
- #119 - hybrid_agent_execution_spec.rb syntax errors (5 failures)
- #120 - neural_task_execution_spec.rb syntax errors (7 failures)
- #121 - symbolic_task_execution_spec.rb syntax errors (4 failures)
- #122 - type_coercion_spec.rb output validation failure (1 failure)

**P1 - UX/Operational Issues:**
- #100 - Agent pause/resume commands fail silently on kubectl errors
- #102 - Agent workspace validation fails for legitimate pod names with special characters
- #105 - StreamingBody MockStream incomplete IO interface may break middleware compatibility

**P2 - Legacy Cleanup:**
- #78 - Remove dead code tool.rb file (645 lines)
- #76 - Dead code: unused expression in model test

**P3 - Enhancements:**
- #51 - Include complete MCP tool schemas
- #40 - Performance optimization
- #41 - Comprehensive test suite

## Recently Resolved (Last 5)

1. **#134** (2025-12-28) - Ensure clusterRef for all resource types - Added cluster_ref support to personas (4 new tests)
2. **#140** (2025-12-27) - Remove Kubernetes events - Eliminated timeout-prone event emission code (935 lines removed)
3. **#131** (2025-12-09) - Gem packaging issues preventing require - Fixed file permissions (600→644) and added packaging verification tests
4. **#125** (2025-12-02) - Remove aictl agent learning command - Integrated learning status into agent inspect
5. **#118** (2025-11-28) - Parallel execution test failures - 6 failures fixed via timing relaxation and AST validator compliance

## Key Learnings

**Agent Runtime:**
- Autonomous mode requires persistent execution after initial task completion
- Signal handling (SIGTERM/SIGINT) for graceful shutdown
- Idle timeout configurable via AGENT_IDLE_TIMEOUT
- New instructions via AGENT_NEW_INSTRUCTION environment variable

**Resource Management:**
- All Kubernetes resources (agents, models, tools) need clusterRef for proper lifecycle
- Cluster finalizers require explicit resource association
- ResourceBuilder.build_resource() accepts cluster_ref parameter

**Neural Task Execution:**
- LLM responses may include malformed THINK blocks
- Aggressive fallback patterns + retry with strict JSON instructions
- Parsing retry flag must reset at task start (not in ensure block)
- Scheduled vs autonomous modes have different execution expectations

**Schema & Documentation:**
- Schema CHANGELOG.md must match gem VERSION for CI tests
- Template at lib/language_operator/templates/schema/CHANGELOG.md
- Test: spec/language_operator/dsl/schema_artifacts_spec.rb:116

**Gem Packaging:**
- Source file permissions are preserved in built gems (600 → 600, 644 → 644)
- All source files must be 644 for non-root user access after gem installation
- Packaging test at spec/language_operator/packaging_spec.rb verifies permissions and file inclusion
- Version changes require Gemfile.lock update for CI success
