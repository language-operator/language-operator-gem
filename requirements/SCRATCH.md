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

## Current Priorities (2025-11-26)

**P1 - Critical Security Issues:**
- ✅ #96 - Kubeconfig path injection vulnerability (RESOLVED 2025-11-26)
- ✅ #95 - Path traversal validation too permissive (RESOLVED 2025-11-26)

**P2 - Resource Leaks (COMPLETED - 2025-11-26):**
- ✅ #107 - WebServer creates new Executor per request causing MCP connection resource leaks (COMPLETED 2025-11-26)
- ✅ #106 - Parallel task execution loses OpenTelemetry trace context across threads (COMPLETED 2025-11-26)
- ✅ #99 - TypeCoercion cache memory leak (resolved by #88 fix)
- ✅ #88 - TypeCoercion cache unbounded growth (duplicate of #99)

**P3 - Runtime Stability (ACTIVE - 2025-11-26):**
- ✅ #97 - SafeExecutor constant redefinition creates inconsistent execution environment (COMPLETED 2025-11-26)
- 🔥 #91 - Race condition in TaskExecutor timeout handling and error classification [READY] 
- 🔥 #93 - Schedule validation accepts invalid cron intervals causing runtime failures [READY] (HIGHEST PRIORITY)

**P4 - UX/Operational Issues (ACTIVE - 2025-11-26):**
- 🔥 #90 - Silent failure in Config.get_int with misleading error messages [READY] (foundational config issue)
- #101 - AgentWizard time parsing allows invalid times but generates broken cron expressions (related to #93)
- #100 - Agent pause/resume commands fail silently on kubectl errors
- #102 - Agent workspace validation fails for legitimate pod names with special characters
- #92 - CLI error handler exit(1) bypasses Thor error handling and testing
- #105 - StreamingBody MockStream incomplete IO interface may break middleware compatibility

**P5 - Legacy Cleanup:**
- #78 - Remove dead code tool.rb file (645 lines, cleanup)
- #76 - Dead code: unused expression in model test

**P6 - Enhancements:**
- #51 - Include complete MCP tool schemas
- #40 - Performance optimization
- #41 - Comprehensive test suite

**Recently Completed (Major Issues):**
- ✅ #104 - File.expand_path unsafe expansion in kubeconfig detection (2025-11-26) - **CRITICAL SECURITY FIX**: Eliminated path traversal vulnerability in home directory expansion by replacing unsafe File.expand_path('~/.kube/config') usage across 11 locations with secure SecurePath utility. Prevents attacks via malicious HOME environment variable (HOME=/etc, HOME=../../../etc). Added comprehensive validation blocking dangerous system directories, path traversal sequences, and relative paths. Falls back to /tmp for suspicious HOME values. Added 11 security test cases covering all attack scenarios. Zero breaking changes for legitimate usage.
- ✅ #98 - Shell injection vulnerability in exec_in_pod method (2025-11-25) - **CRITICAL SECURITY FIX**: Eliminated shell injection vulnerability in workspace command by replacing string concatenation with array-based command construction using Shellwords.shellsplit and Open3.capture3(*array). Added comprehensive test coverage (16 tests) covering security attack scenarios, edge cases, and real-world exploit prevention.
- ✅ #103 - File descriptor leak in agent logs command (2025-11-26) - **SECURITY & RESOURCE FIX**: Eliminated file descriptor and thread resource leaks in agent logs command by implementing proper signal handling, thread cleanup, and resource management. Added INT signal trap for graceful Ctrl+C interruption, ensure blocks for thread termination, and IOError handling for closed streams. Added 16 comprehensive test cases covering normal operation, interruption scenarios, and resource cleanup. Prevents resource exhaustion and system instability from uncleaned resources during log streaming interruption.
- ✅ #89 - Command injection in kubectl_prefix generation (2025-11-26) - **CRITICAL SECURITY FIX**: Eliminated command injection vulnerability in ClusterContext.kubectl_prefix by adding proper shell escaping using Shellwords.escape() for all user-controlled inputs (kubeconfig, context, namespace). Prevents injection via malicious paths, context names, and namespaces. Added 16 comprehensive security tests covering all attack scenarios. Zero breaking changes for legitimate use cases.
- ✅ #94 - HTTP client SSRF attacks (2025-11-26) - **CRITICAL SECURITY FIX**: Eliminated SSRF vulnerability in HTTP client by adding comprehensive URL scheme and IP validation. Blocks non-HTTP/HTTPS schemes (file://, ftp://, etc.), private IP ranges (RFC 1918), localhost/loopback, link-local (AWS metadata), and broadcast addresses. Includes hostname resolution validation to prevent DNS rebinding. Added 30 comprehensive tests covering all security scenarios. Zero breaking changes for legitimate requests.
- ✅ #98 - Shell injection vulnerability in exec_in_pod method (2025-11-25) - **CRITICAL SECURITY FIX**: Eliminated shell injection vulnerability in workspace command by replacing string concatenation with array-based command construction using Shellwords.shellsplit and Open3.capture3(*array). Added comprehensive test coverage (16 tests) covering security attack scenarios, edge cases, and real-world exploit prevention.
- ✅ #86 - aictl cluster create should support --domain option (2025-11-25) - Added --domain CLI option for webhook routing configuration, updated ResourceBuilder to accept domain parameter, comprehensive test coverage, maintains backward compatibility
- ✅ #85 - Creating new resources should have consistent UX (2025-11-25) - Implemented DRY formatters in UxHelper for consistent ❚-formatted resource display across all creation commands (cluster, agent, model, tool) and their inspection contexts
- ✅ #84 - Add logo to aictl help output when called with no arguments (2025-11-25) - Overrode Thor's help method to display Language Operator logo before command list when aictl called without arguments or with explicit help command, specific command help remains unchanged
- ✅ #79 - Invalid Kubernetes resource names in agent creation (2025-11-24) - Fixed generate_agent_name to ensure K8s-compliant names by prepending 'agent-' when name doesn't start with letter, added comprehensive test coverage for all edge cases
- ✅ #80 - Config.get_int silent conversion bug (2025-11-24) - Replaced permissive to_i with strict Integer() conversion, added comprehensive tests for get_int/get_bool/get_array, clear error messages prevent misconfigurations
- ✅ #70 - Dead code: useless statements in agent pause and resume commands (2025-11-24) - Removed two useless ctx.namespace statements that had no effect, verified with full test suite and manual testing
- ✅ #73 - Malformed kubectl command in model test (2025-11-24) - Fixed array command handling using Shellwords.join for proper shell escaping, added comprehensive test coverage for both string and array commands
- ✅ #74 - Inconsistent empty value handling in Agent::Executor environment variable parsing (2025-11-24) - Fixed parse_array_env to behave consistently with parse_float_env/parse_int_env, added comprehensive test coverage
- ✅ #75 - Missing require statement in tool search (2025-11-24) - Added missing require_relative for Config::ToolRegistry, added comprehensive test coverage
- ✅ #77 - Tool commands broken after refactor (2025-11-24) - Investigation revealed issue was already resolved; fixed minor constant reference bug in auth command and closed issue
- ✅ #71 - Dead code: unused expressions in PatternDetector.generate_task_fragment (2025-11-24) - Removed remnants from instruction generation experiments
- ✅ #72 - Dead code: placeholder agent command implementations (2025-11-24) - Completed refactoring by moving real implementations to Agent::Base
- ✅ #66, #55, #59, #62, #67 - CLI and K8s client fixes
- ✅ #60, #69, #50, #68, #64, #46, #48 - Security vulnerabilities resolved
- ✅ #45, #52, #44, #54, #53 - Runtime and UX improvements
- ✅ #49 - CLI exits on invalid selection (2025-11-24) - Fixed UserPrompts.select to retry instead of exit
- ✅ #47 - Silent type conversion failures (2025-11-24) - Replaced to_i/to_f with strict Integer()/Float() validation
