# Observability and Telemetry

The Language Operator gem includes comprehensive OpenTelemetry instrumentation to enable observability, debugging, and optimization of agent executions.

## OpenTelemetry Integration

The gem automatically instruments agent executions with OpenTelemetry spans, following the [OpenTelemetry Semantic Conventions for GenAI](https://opentelemetry.io/docs/specs/semconv/gen-ai/).

### Configuration

Configure telemetry via environment variables:

```bash
# Basic telemetry (always enabled)
OTEL_EXPORTER_OTLP_ENDPOINT=https://your-otel-collector:4317

# Data capture controls (optional - defaults to metadata only)
CAPTURE_TASK_INPUTS=true      # Capture full task inputs as JSON
CAPTURE_TASK_OUTPUTS=true     # Capture full task outputs as JSON  
CAPTURE_TOOL_ARGS=true        # Capture tool call arguments
CAPTURE_TOOL_RESULTS=true     # Capture tool call results
```

**Security Note:** Data capture is disabled by default to prevent sensitive information leakage. Only enable full data capture in secure environments.

## Span Hierarchy

The gem creates a hierarchical trace structure that enables the learning system to identify and analyze complete agent executions:

```
agent_executor (parent span - overall agent run)
  └── task_executor.execute_task (child span - task 1)
      └── execute_tool github (grandchild span - tool call 1)
      └── execute_tool slack (grandchild span - tool call 2)
  └── task_executor.execute_task (child span - task 2)
  └── task_executor.execute_task (child span - task 3)
```

### Span Names

| Span Name | Purpose | Created By |
|-----------|---------|------------|
| `agent_executor` | Overall agent execution | `LanguageOperator::Agent.execute_main_block()` |
| `task_executor.execute_task` | Individual task execution | `TaskExecutor#execute_task()` |
| `execute_tool #{tool_name}` | Tool calls from LLM responses | `TaskTracer#record_single_tool_call()` |
| `execute_tool.#{tool_name}` | Direct tool calls from symbolic tasks | `Client::Base` tool wrapper |

## Span Attributes

### Agent Executor Span

The top-level `agent_executor` span includes:

```
agent.name: "my-agent"           # Agent identifier
agent.task_count: 5              # Number of tasks in agent
agent.mode: "autonomous"         # Execution mode (autonomous/scheduled/interactive)
```

### Task Executor Span  

Each `task_executor.execute_task` span includes:

```
# Core identification (CRITICAL for learning system)
task.name: "fetch_user_data"            # Task identifier
gen_ai.operation.name: "execute_task"   # Operation type

# Execution metadata
task.max_retries: 3                     # Retry configuration
task.timeout: 30000                     # Timeout in milliseconds
task.type: "hybrid"                     # Task type (neural/symbolic/hybrid)
task.has_neural: "true"                 # Has neural implementation
task.has_symbolic: "false"              # Has symbolic implementation

# Agent context
agent.name: "my-agent"                  # Agent identifier (explicit for learning system)

# Data capture (when enabled)
task.inputs: '{"user_id": 123}'         # JSON-encoded inputs (CAPTURE_TASK_INPUTS=true)
task.outputs: '{"user": {...}}'         # JSON-encoded outputs (CAPTURE_TASK_OUTPUTS=true)
```

### Tool Call Spans

Tool calls create spans with names like `execute_tool #{tool_name}` and include:

```
# GenAI semantic attributes
gen_ai.operation.name: "execute_tool"           # Operation type
gen_ai.tool.name: "github"                      # Tool identifier
gen_ai.tool.call.id: "call_123"                 # Call ID (if available)

# Data capture (when enabled)
gen_ai.tool.call.arguments: '{"repo": "..."}'   # JSON arguments (CAPTURE_TOOL_ARGS=true)
gen_ai.tool.call.result: '{"status": "ok"}'     # JSON result (CAPTURE_TOOL_RESULTS=true)

# Size metadata (always captured)
gen_ai.tool.call.arguments.size: 45             # Arguments size in bytes
gen_ai.tool.call.result.size: 1024              # Result size in bytes
```

## Learning System Integration

This span naming convention enables the language-operator Kubernetes controller to:

1. **Identify Task Executions**: Query traces by `task_executor.execute_task` spans
2. **Group by Agent**: Filter by `agent.name` attribute  
3. **Analyze Patterns**: Extract execution patterns from span attributes
4. **Build Optimizations**: Create optimized implementations based on trace analysis

### Example OTLP Query

To find all task executions for an agent:

```sql
SELECT * FROM spans 
WHERE name = 'task_executor.execute_task' 
  AND attributes['agent.name'] = 'my-agent'
  AND start_time > NOW() - INTERVAL '1 hour'
```

## Data Privacy and Security

### Default Behavior (Secure)

By default, the gem captures:
- ✅ Task names and metadata
- ✅ Execution timing and counts  
- ✅ Tool names and call frequencies
- ✅ Data sizes (bytes)
- ❌ **NOT** actual data content

### Full Data Capture (Optional)

When explicitly enabled, the gem additionally captures:
- ⚠️ Complete task inputs and outputs as JSON
- ⚠️ Tool call arguments and results  
- ⚠️ LLM prompts and responses

**Warning:** Only enable full data capture in development or secure production environments. Captured data may contain sensitive information.

### Data Sanitization

When full capture is enabled, the gem:
- Truncates large payloads (>1000 chars for span attributes)
- Converts complex objects to JSON automatically
- Respects OpenTelemetry attribute limits

## Performance Impact

Telemetry overhead is minimal:
- **Default mode**: <5% performance overhead
- **Full capture mode**: ~10% performance overhead  
- **Span creation**: <1ms per span
- **Data serialization**: 1-5ms for complex objects

## Debugging with Traces

### Common Queries

**Find slow tasks:**
```sql
SELECT attributes['task.name'], duration_ms
FROM spans 
WHERE name = 'task_executor.execute_task' 
  AND duration_ms > 5000
ORDER BY duration_ms DESC
```

**Tool usage analysis:**
```sql  
SELECT attributes['gen_ai.tool.name'], COUNT(*)
FROM spans
WHERE name LIKE 'execute_tool%'
GROUP BY attributes['gen_ai.tool.name']
```

**Agent execution frequency:**
```sql
SELECT attributes['agent.name'], COUNT(*) as executions
FROM spans
WHERE name = 'agent_executor'
  AND start_time > NOW() - INTERVAL '24 hours'  
GROUP BY attributes['agent.name']
```

### Trace Sampling

For high-volume agents, consider trace sampling:

```bash
# Sample 10% of traces
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

## Related Documentation

- [Agent Runtime Architecture](./agent-internals.md) - How agents execute
- [Best Practices](./best-practices.md) - Production deployment guidance
- [Understanding Generated Code](./understanding-generated-code.md) - Agent code structure

## External Resources

- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
- [Language Operator Controller](https://github.com/language-operator/language-operator) - Learning system implementation
- [OTLP Specification](https://opentelemetry.io/docs/specs/otlp/) - Wire format