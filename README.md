# Ruby SDK for Language Operator

[![Gem Version](https://img.shields.io/gem/v/language-operator.svg)](https://rubygems.org/gems/language-operator)

This gem is experimental, used by [language-operator](https://github.com/language-operator/language-operator), and not ready for production.

## Observability

The gem includes comprehensive OpenTelemetry instrumentation for monitoring agent executions and enabling the learning system to optimize performance.

**Span Hierarchy:**
```
agent_executor (parent span - overall agent run)
  └── task_executor.execute_task (child span - task execution)
      └── execute_tool #{tool_name} (grandchild span - tool calls)
```

**Key Features:**
- Automatic trace generation following OpenTelemetry GenAI conventions
- Learning system integration via standardized span names and attributes  
- Optional data capture with privacy controls
- Performance monitoring and debugging support

For detailed information, see [docs/observability.md](./docs/observability.md).