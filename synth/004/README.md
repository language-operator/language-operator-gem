# 004 - System Health Monitoring & Observability Validation

## Instructions

"Check if the system is healthy every 5 minutes and report any issues"

## Significance

This validates observability infrastructure and system self-monitoring capabilities in DSL v1.

While tests 001-003 validated synthesis, neural execution, and learning, this test validates that the system can properly observe and report on its own health - including the critical infrastructure required for observability itself.

This is the first synthesis test focused on infrastructure resilience and event emission validation.

## What This Demonstrates

### 1. Self-Observability Architecture

The synthesized agent should naturally generate tasks that validate:
- **Kubernetes API connectivity** - Can reach cluster API for event emission
- **LLM endpoint availability** - Can execute neural tasks
- **Monitoring system integration** - Can send telemetry data
- **Event emission functionality** - Task Completion events are generated
- **Network policy compliance** - Agent can reach required services

### 2. Infrastructure Resilience Testing

```ruby
# Expected synthesis pattern
task :check_kubernetes_api,
  instructions: "Test connectivity to Kubernetes API server",
  outputs: { reachable: 'boolean', response_time_ms: 'integer' }

task :check_llm_endpoint,
  instructions: "Verify LLM model is responding",
  outputs: { available: 'boolean', model_name: 'string' }

task :check_monitoring_system,
  instructions: "Test OpenTelemetry/monitoring endpoint connectivity",
  outputs: { telemetry_working: 'boolean', endpoint: 'string' }

task :validate_event_emission,
  instructions: "Ensure task execution events are being emitted properly",
  outputs: { events_working: 'boolean', last_event_time: 'string' }

main do |inputs|
  # Systematic health validation
  api_status = execute_task(:check_kubernetes_api)
  llm_status = execute_task(:check_llm_endpoint)
  monitoring_status = execute_task(:check_monitoring_system)
  events_status = execute_task(:validate_event_emission)
  
  # Overall health determination and reporting
  overall_healthy = api_status[:reachable] && 
                   llm_status[:available] && 
                   monitoring_status[:telemetry_working] &&
                   events_status[:events_working]
  
  {
    healthy: overall_healthy,
    components: {
      kubernetes: api_status,
      llm: llm_status,
      monitoring: monitoring_status,
      events: events_status
    },
    timestamp: Time.now.iso8601
  }
end
```

### 3. Scheduled Health Monitoring

```ruby
mode :scheduled
schedule "*/5 * * * *"  # Every 5 minutes
```

Each execution:
1. Tests all critical infrastructure components
2. Generates multiple Task Completion events (validation target)
3. Reports comprehensive health status
4. Creates telemetry spans for observability
5. Exits and waits for next scheduled run

### 4. Event Emission Validation (Critical)

This test specifically validates the Task Completion event infrastructure that was failing due to NetworkPolicy issues. Each health check execution should generate:

- **Task Start events** for each health check task
- **Task Completion events** (success/failure) for each task
- **OpenTelemetry traces** with health check spans
- **Agent execution events** for overall run status

**Key Validation**: If Task Completion events are missing, the health check itself reports the observability system as unhealthy.

### 5. Meta-Validation Property

The test has a beautiful self-validating property:

```
IF observability infrastructure is broken
THEN health check cannot report properly
THEN system correctly reports as unhealthy
THEREFORE test reveals infrastructure issues
```

This makes it impossible for observability problems to hide - they become part of the health status.

## Why This Matters

### Fills Critical Testing Gap

Current synthesis test coverage:
- ✅ **001**: Basic synthesis functionality
- ✅ **002**: Neural task execution + scheduling  
- ✅ **003**: Progressive learning + optimization
- ✅ **004**: Infrastructure resilience + observability

### Validates Production Readiness

Real-world deployments require:
- **Health monitoring** - System can detect its own problems
- **Event emission** - Observability data is generated correctly
- **Network policies** - Security restrictions don't break functionality
- **Infrastructure dependencies** - All required services are reachable

### Catches Infrastructure Configuration Errors

This test would immediately detect:
- NetworkPolicy blocking Kubernetes API access
- Broken OpenTelemetry configuration
- LLM endpoint connectivity issues
- Missing RBAC permissions for event creation
- Firewall rules blocking required traffic

### Self-Healing Validation

The test validates that agents can:
- Detect infrastructure problems
- Report issues clearly
- Continue functioning despite partial failures
- Provide actionable diagnostic information

## Real-World Use Cases This Enables

### Cluster Health Monitoring
```ruby
# Production monitoring agent
"Monitor cluster resources and alert if anything is degraded"
# → Generates comprehensive cluster health dashboard
```

### Service Dependency Validation  
```ruby
# Service mesh health checking
"Test all service connections and report any broken integrations"
# → Validates microservice communication patterns
```

### Infrastructure Compliance Auditing
```ruby
# Security and compliance monitoring  
"Check if all security policies are working correctly"
# → Validates network policies, RBAC, pod security standards
```

### Self-Healing System Validation
```ruby
# Resilience testing
"Verify the system can recover from common failure scenarios"
# → Tests automatic recovery mechanisms
```

## Expected Synthesis Outcomes

### Neural Phase (Initial Synthesis)
- **All tasks neural** - Uses LLM to determine health check methods
- **Flexible validation** - Adapts to different infrastructure configurations
- **Comprehensive checking** - Tests all critical system components

### Learning Phase (After Pattern Detection)
- **Deterministic checks become symbolic** - API connectivity, endpoint tests
- **Complex analysis stays neural** - Overall health determination, anomaly detection
- **Optimized execution** - Faster, cheaper health checks over time

### Progressive Optimization
```ruby
# Run 1-10: All neural health checks
# Run 11+: Learned symbolic implementations for standard checks
# Always: Neural analysis of overall system health patterns
```

## Validation Criteria

### Infrastructure Health
- [ ] Kubernetes API connectivity verified
- [ ] LLM endpoint responsiveness confirmed  
- [ ] Monitoring system integration working
- [ ] Network policies allow required access

### Event Emission
- [ ] Task Completion events generated for each task
- [ ] Events contain proper metadata and timing
- [ ] OpenTelemetry traces collected successfully
- [ ] No event emission timeout errors

### Error Handling
- [ ] Graceful handling of connectivity failures
- [ ] Clear reporting of specific issues
- [ ] Continued operation despite partial failures
- [ ] Actionable diagnostic information provided

### Schedule Reliability
- [ ] Executions occur every 5 minutes as scheduled
- [ ] Consistent performance across runs
- [ ] Proper cleanup after each execution
- [ ] No resource leaks or accumulation

## Comparison to Traditional Monitoring

### Traditional Approach (Prometheus/Nagios)
```yaml
# Static configuration, manual setup
- name: check_api
  command: curl -f https://k8s-api/healthz
  interval: 5m
  
- name: check_llm  
  command: curl -f https://llm-endpoint/health
  interval: 5m
```

### Language Operator Approach (Organic Functions)
```ruby
# Natural language → comprehensive monitoring
"Check if the system is healthy every 5 minutes and report any issues"

# Synthesizes intelligent monitoring that:
# - Adapts to infrastructure changes
# - Learns optimal check patterns  
# - Provides contextual analysis
# - Integrates with existing observability
```

## Files Generated

| File | Purpose |
|------|---------|
| `instructions.txt` | Single-sentence natural language instruction |
| `agent.synthesized.rb` | Initial neural health monitoring agent |
| `Makefile` | Synthesis and execution commands |
| `output.log` | Health check execution logs |

## Synthesis Commands

```bash
# Create and deploy health monitoring agent
make create

# Monitor health check execution
make logs

# Check for Task Completion events
make events

# Validate observability infrastructure
make validate
```

## Expected Impact

This test validates that Language Operator can synthesize production-ready monitoring infrastructure from a simple natural language instruction, while ensuring the observability systems required for operational visibility are functioning correctly.

The zen aspect: A simple request for health monitoring becomes a comprehensive validation of the entire system's ability to observe itself.

## Related Tests

- [001 - Minimal Synthesis](../001/README.md) - Basic synthesis validation
- [002 - Neural Execution](../002/README.md) - Neural task execution + scheduling  
- [003 - Progressive Learning](../003/README.md) - Learning and optimization