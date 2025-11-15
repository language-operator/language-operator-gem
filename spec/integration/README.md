# Integration Tests for DSL v1 Task Execution

This directory contains comprehensive integration tests for the Language Operator DSL v1 task execution functionality. These tests validate the end-to-end behavior of neural tasks, symbolic tasks, hybrid agents, parallel execution, type coercion, and error handling.

## Overview

The integration tests complement the existing E2E tests (`spec/e2e/`) by focusing specifically on DSL v1 task execution features rather than CLI/agent lifecycle. They provide:

- **Comprehensive coverage** of all DSL v1 execution paths
- **Performance benchmarks** with baseline measurements  
- **Mock LLM integration** for consistent neural task testing
- **Real-world scenarios** demonstrating practical usage patterns
- **Error simulation** for robust error handling validation

## Test Structure

### Core Test Files

| File | Purpose | Coverage |
|------|---------|----------|
| `integration_helper.rb` | Test framework and utilities | Mock LLM, performance measurement, agent creation |
| `neural_task_execution_spec.rb` | Neural task testing | Instructions-based tasks, LLM integration, validation |
| `symbolic_task_execution_spec.rb` | Symbolic task testing | Ruby code blocks, context access, performance |
| `hybrid_agent_execution_spec.rb` | Mixed task workflows | Neural + symbolic combinations, data flow |
| `parallel_execution_spec.rb` | Parallel task execution | Implicit/explicit parallelism, performance gains |
| `type_coercion_spec.rb` | Type coercion edge cases | Input/output validation, boundary conditions |
| `error_handling_spec.rb` | Error handling paths | Exception handling, recovery, debugging |
| `performance_benchmarks_spec.rb` | Performance measurement | Baselines, regression detection, optimization |
| `comprehensive_integration_spec.rb` | Real-world scenarios | Complete workflows, practical examples |

### Test Categories

#### 1. Neural Task Execution (`neural_task_execution_spec.rb`)
Tests LLM-based tasks that execute based on instructions rather than code.

```ruby
task :analyze_sentiment,
  instructions: "Analyze the sentiment of the given text",
  inputs: { text: 'string' },
  outputs: { sentiment: 'string', confidence: 'number' }
```

**Coverage:**
- Simple neural tasks with structured outputs
- Complex neural tasks with multiple inputs/outputs
- Neural task validation and schema compliance
- Mock LLM response handling
- Type coercion for neural task inputs/outputs

#### 2. Symbolic Task Execution (`symbolic_task_execution_spec.rb`)
Tests Ruby code-based tasks with explicit implementations.

```ruby
task :calculate_statistics,
  inputs: { numbers: 'array' },
  outputs: { sum: 'number', average: 'number' }
do |inputs|
  sum = inputs[:numbers].sum
  { sum: sum, average: sum.to_f / inputs[:numbers].length }
end
```

**Coverage:**
- Simple computational tasks
- Complex data processing logic
- Context access (execute_task, execute_llm, execute_tool)
- Ruby exception handling
- Performance characteristics

#### 3. Hybrid Agent Execution (`hybrid_agent_execution_spec.rb`)
Tests agents combining neural and symbolic tasks for optimal performance.

```ruby
# Fast symbolic data preprocessing
task :preprocess_data do |inputs|
  # Deterministic data cleaning
end

# Creative neural analysis  
task :analyze_patterns,
  instructions: "Identify patterns and insights"

# Fast symbolic reporting
task :generate_report do |inputs|
  # Structured report generation
end
```

**Coverage:**
- Strategic task type selection (neural for creativity, symbolic for speed)
- Data flow between different task types
- Conditional execution based on task outputs
- Performance optimization patterns

#### 4. Parallel Execution (`parallel_execution_spec.rb`)
Tests both implicit dependency analysis and explicit parallel execution.

```ruby
# Implicit parallelization (automatic dependency detection)
main do |inputs|
  a = execute_task(:independent_task_a)  # Can run in parallel
  b = execute_task(:independent_task_b)  # Can run in parallel
  execute_task(:dependent_task, inputs: { a: a, b: b })  # Runs after a & b
end

# Explicit parallelization  
main do |inputs|
  results = execute_parallel([
    { name: :task_a, inputs: { ... } },
    { name: :task_b, inputs: { ... } }
  ])
end
```

**Coverage:**
- Dependency graph analysis and level-based execution
- Thread pool management and resource constraints
- Performance improvements for I/O-bound tasks
- Error handling in parallel scenarios

#### 5. Type Coercion (`type_coercion_spec.rb`)
Tests the type system's coercion capabilities and validation.

**Coverage:**
- String → Integer/Number/Boolean coercion
- Symbol → String coercion
- Complex nested type handling
- Edge cases and boundary values
- Performance impact measurement

#### 6. Error Handling (`error_handling_spec.rb`)
Tests comprehensive error handling and recovery mechanisms.

**Coverage:**
- Ruby exceptions in symbolic tasks
- LLM API failures and timeouts
- Input/output validation errors
- Cascading error propagation
- Retry logic and recovery patterns
- Rich error context for debugging

#### 7. Performance Benchmarks (`performance_benchmarks_spec.rb`)
Establishes performance baselines and measures optimization impact.

**Coverage:**
- Symbolic vs neural task performance comparison
- Parallel execution scalability measurement
- Memory usage and resource consumption
- Task execution overhead analysis
- Regression detection baselines

#### 8. Comprehensive Integration (`comprehensive_integration_spec.rb`)
Real-world scenarios demonstrating practical DSL v1 usage.

**Scenarios:**
- **Data Processing Pipeline:** Extract, clean, transform, analyze, report
- **Customer Service Bot:** Intent classification, knowledge lookup, response generation
- **Financial Analysis:** Data validation, metric calculation, risk assessment

## Test Framework Features

### Mock LLM Integration

The test framework includes sophisticated LLM mocking via WebMock:

```ruby
# Automatic response generation based on task instructions
setup_llm_mocks  # Stubs HTTP requests to LLM APIs

# Generates contextual responses:
"fetch user data" → { user: {...}, preferences: {...} }
"analyze sentiment" → { sentiment: "positive", confidence: 0.85 }
"generate report" → { report: "Generated report content" }
```

### Performance Measurement

Built-in performance utilities for optimization and regression detection:

```ruby
# Measure execution time with statistical analysis
result = measure_performance('Task description') do
  execute_main_with_timing(agent, inputs)
end

# Compare two approaches
benchmark_comparison(
  'Symbolic approach', -> { ... },
  'Neural approach', -> { ... }
)
```

### Agent Creation Helpers

Streamlined agent creation for testing:

```ruby
agent = create_test_agent('agent-name', <<~'RUBY')
  agent "test-agent" do
    task :example do |inputs|
      { result: 'test' }
    end
    
    main do |inputs|
      execute_task(:example)
    end
  end
RUBY
```

## Running Integration Tests

### All Integration Tests

```bash
make test-integration
# OR
bundle exec rspec spec/integration/ --tag type:integration
```

### Specific Test Categories

```bash
# Neural task tests
bundle exec rspec spec/integration/neural_task_execution_spec.rb

# Symbolic task tests  
bundle exec rspec spec/integration/symbolic_task_execution_spec.rb

# Performance benchmarks
make test-performance
# OR
bundle exec rspec spec/integration/performance_benchmarks_spec.rb
```

### With Performance Benchmarks

```bash
INTEGRATION_BENCHMARK=true bundle exec rspec spec/integration/performance_benchmarks_spec.rb
```

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `INTEGRATION_MOCK_LLM` | `true` | Enable LLM response mocking |
| `INTEGRATION_BENCHMARK` | `false` | Enable performance measurement output |
| `INTEGRATION_TIMEOUT` | `30` | Test timeout in seconds |

## CI/CD Integration

Integration tests are automatically run in GitHub Actions:

```yaml
- name: Run integration tests
  run: bundle exec rspec spec/integration/ --tag type:integration
  env:
    INTEGRATION_MOCK_LLM: 'true'
    INTEGRATION_BENCHMARK: 'false'

- name: Run performance benchmarks
  run: bundle exec rspec spec/integration/performance_benchmarks_spec.rb
  env:
    INTEGRATION_MOCK_LLM: 'true' 
    INTEGRATION_BENCHMARK: 'true'
```

## Test Coverage

The integration tests provide comprehensive coverage of DSL v1 features:

### ✅ Fully Covered Features

- **Task Definition:** Neural (instructions) and symbolic (code blocks)
- **Main Block Execution:** Imperative control flow with execute_task
- **Type System:** All 7 types with coercion and validation
- **Parallel Execution:** Both implicit and explicit parallelism
- **Error Handling:** Exception handling, validation, recovery
- **Context Access:** execute_llm, execute_tool, task-to-task calls
- **Performance:** Baseline measurement and optimization validation

### ✅ Real-World Scenarios

- **Data Processing:** Multi-source ETL with validation and reporting
- **Customer Service:** Intent classification and response generation  
- **Financial Analysis:** Risk assessment with regulatory compliance
- **Mixed Workflows:** Strategic neural/symbolic task selection

### ✅ Edge Cases & Error Conditions

- **Type Coercion:** Boundary values, null handling, complex nested types
- **Error Propagation:** Cascading failures, partial success handling
- **Resource Limits:** Memory exhaustion, timeout scenarios
- **API Failures:** LLM timeouts, malformed responses

## Development Guidelines

### Writing New Integration Tests

1. **Use the Integration Helper:** Leverage `integration_helper.rb` utilities
2. **Follow Naming Conventions:** `*_spec.rb` files with descriptive names
3. **Include Performance Measurement:** Use `measure_performance` for timing-critical tests
4. **Test Real Scenarios:** Create practical examples that mirror actual usage
5. **Validate Comprehensively:** Check both success cases and error conditions

### Performance Considerations

- **Symbolic tasks** should execute in microseconds
- **Neural tasks** (mocked) should complete within 100ms
- **Parallel execution** should show measurable speedup for I/O tasks
- **Type coercion** overhead should be minimal

### Mock LLM Best Practices

- Use realistic response structures
- Include validation-appropriate outputs
- Simulate various success/failure scenarios
- Keep responses deterministic for reliable testing

## Troubleshooting

### Common Issues

**Tests timing out:**
```bash
INTEGRATION_TIMEOUT=60 bundle exec rspec spec/integration/
```

**LLM mock issues:**
```bash
INTEGRATION_MOCK_LLM=false bundle exec rspec spec/integration/
# Note: This will attempt real LLM calls and likely fail without API keys
```

**Performance variance:**
```bash
# Run multiple times for statistical confidence
for i in {1..5}; do make test-performance; done
```

### Debugging

1. **Check mock setup:** Ensure `setup_llm_mocks` is called
2. **Validate agent DSL:** Use `create_test_agent` with simple examples first
3. **Review execution traces:** Add debug output in task blocks
4. **Measure timing:** Use `execute_main_with_timing` for execution analysis

## Contributing

When adding new DSL v1 features:

1. **Add corresponding integration tests** covering happy path and error cases
2. **Include performance benchmarks** if the feature affects execution speed
3. **Update this README** with new test categories and coverage areas
4. **Verify CI integration** runs successfully with new tests

## Related Documentation

- [DSL v1 Proposal](../../requirements/proposals/dsl-v1.md) - Complete DSL specification
- [TaskExecutor Documentation](../../docs/task-executor.md) - Task execution internals  
- [E2E Test Guide](../e2e/README.md) - CLI and agent lifecycle testing
- [Testing Best Practices](../../docs/testing-guide.md) - General testing guidelines

---

**Last Updated:** 2024-11-15  
**Test Coverage:** 30+ integration scenarios covering all DSL v1 features  
**Performance Baselines:** Established for symbolic, neural, and parallel execution