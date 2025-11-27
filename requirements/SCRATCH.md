# Language Operator Knowledge Base

Critical insights and patterns for the language-operator Ruby gem.

## Quick Reference

- **Project**: Kubernetes agent orchestration with `aictl` CLI (`bundle exec bin/aictl`)  
- **DSL**: Task/Main model (v1) replaces workflow/step (v0, deprecated)
- **Components**: TaskDefinition (contracts), MainDefinition (imperative), TypeSchema (7 types)
- **Test Status**: All passing, RuboCop clean

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
- ✅ Learning system: TraceAnalyzer & PatternDetector 
- ✅ CLI: Unified wizards pattern with UxHelper

## Implementation Details

**Task Execution:**
- Neural: TaskExecutor → LLM → JSON → validation
- Symbolic: TaskDefinition#call → code → validation  
- Runtime: Agent detects DSL version, creates TaskExecutor

**Parallel Execution (Blocked):**
- Infrastructure: DependencyGraph + ParallelExecutor (2x I/O speedup)
- Issue: Variable-to-result mapping (`s1 = execute_task(:fetch1)` vs `{fetch1: {...}}`)

**Learning System:**
- TraceAnalyzer (OTLP) + PatternDetector (85% consistency, 10+ executions → symbolic)
- Config: OTEL_QUERY_ENDPOINT, OTEL_QUERY_API_KEY, OTEL_QUERY_BACKEND
- Gotcha: WebMock stubs needed before TraceAnalyzer init

## Common Gotchas

1. **Hash Keys:** Ruby symbols ≠ strings - check types in tests
2. **Heredocs:** Use `<<~'RUBY'` (single quotes) to prevent RSpec context leakage  
3. **Parser:** Too forgiving for syntax validation - use AST for semantic checks
4. **Tools:** Access via LLM interface (`execute_llm`), not direct RPC
5. **Futures:** Use `future.wait` + `future.rejected?`, not `rescue` around `future.value`
6. **Constants:** Use `::Logger::WARN` to avoid namespace conflicts
7. **WebMock:** Stub HTTP before object initialization if constructor makes requests
8. **UX:** Always use `UxHelper` for TTY components

## Current Active Issues (2025-11-27)

**P1 - UX/Operational Issues:**
- #100 - Agent pause/resume commands fail silently on kubectl errors  
- #102 - Agent workspace validation fails for legitimate pod names with special characters
- #105 - StreamingBody MockStream incomplete IO interface may break middleware compatibility

**Recently Resolved (2025-11-27):**
- #109 - ✅ Agent runtime exits after task completion instead of waiting for further instructions
  - Implemented persistent mode for autonomous agents with DSL v1 (task/main model)
  - Added `execute_main_block_persistent` method with signal handling (SIGTERM/SIGINT)
  - Agent now enters idle state after initial task completion instead of exiting
  - Configurable idle timeout via `AGENT_IDLE_TIMEOUT` environment variable
  - Support for new instructions via `AGENT_NEW_INSTRUCTION` environment variable
  - Backward compatibility maintained - scheduled mode still exits after execution
  - Fixes CrashLoopBackOff in Kubernetes deployments for autonomous agents

- #108 - ✅ Universal cluster association for all resource types (tools, agents, models)
  - Added clusterRef field to all resource specs for proper cluster lifecycle management
  - Updated ResourceBuilder.build_resource() to accept cluster_ref parameter
  - Modified all CLI commands (agent create, model create, tool install) to pass cluster reference
  - Added comprehensive test coverage for cluster association
  - Maintains backward compatibility for existing resources
  - Fixes cluster finalizer cleanup issue for all aictl-created resources

**Recently Resolved (2025-11-26):**
- #92 - ✅ CLI error handler exit(1) bypasses Thor error handling and testing
  - Implemented Thor-compatible error classes with specific exit codes (2-6)
  - Replaced all exit(1) calls with proper Thor exceptions
  - Added comprehensive test coverage
  - Maintains backward compatibility and DEBUG mode behavior

**P2 - Legacy Cleanup:**
- #78 - Remove dead code tool.rb file (645 lines, cleanup)
- #76 - Dead code: unused expression in model test

**P3 - Enhancements:**
- #51 - Include complete MCP tool schemas
- #40 - Performance optimization
- #41 - Comprehensive test suite
