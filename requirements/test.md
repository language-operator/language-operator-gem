# aictl Smoke Test Playbook

**Version**: 1.0  
**Target**: aictl CLI comprehensive functionality validation  
**Execution Time**: Quick (5-10 min) | Extended (15-30 min)  
**Agent Executable**: Yes  

## Overview

This playbook provides comprehensive smoke testing for the `aictl` command-line interface. It serves dual purposes:

1. **Human Documentation**: Step-by-step testing procedures for manual validation
2. **Agent Instructions**: Machine-executable test automation with structured success criteria

Tests are organized in tiers by execution time and criticality. Each test includes clear success criteria, expected outputs, and failure recovery procedures.

---

## Prerequisites

**Environment Requirements:**
- [ ] `aictl` binary installed and accessible in PATH
- [ ] Valid Kubernetes cluster (or ability to create one)
- [ ] `kubectl` configured with valid context
- [ ] Internet connectivity for model/tool operations
- [ ] Sufficient cluster permissions (RBAC)

**Validation Commands:**
```bash
# Verify aictl installation
which aictl
# Expected: Path to aictl binary

# Verify kubectl access
kubectl version --short
# Expected: Client and server versions, or client version only

# Check cluster connectivity (optional)
kubectl cluster-info
# Expected: Cluster endpoint info OR connection error (acceptable)
```

**Environment Variables:**
```bash
export TEST_PREFIX="smoke-$(date +%s)"
export TEST_CLUSTER="${TEST_PREFIX}-cluster"
export TEST_NAMESPACE="default"
export TEST_TIMEOUT="300"  # 5 minutes for most operations
```

---

## Quick Smoke Tests (5-10 minutes)

These tests validate critical functionality and basic command parsing. Suitable for CI/CD pipelines.

### Test 1: Basic Command Functionality

**Timeout:** 30 seconds  
**Dependencies:** None  
**Purpose:** Verify aictl installation and basic responsiveness

```bash
# Test: Version information
aictl version
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Output contains version number
- [ ] No error messages in stderr

```bash
# Test: General help
aictl --help
```
**Success Criteria:**
- [ ] Exit code: 0  
- [ ] Output contains subcommands: agent, cluster, model, tool, persona
- [ ] Help text is formatted properly

```bash
# Test: Invalid command handling
aictl invalid-command 2>&1
```
**Success Criteria:**
- [ ] Exit code: non-zero
- [ ] Error message suggests valid commands or help

### Test 2: Status and Configuration

**Timeout:** 60 seconds  
**Dependencies:** None  
**Purpose:** Verify system status reporting

```bash
# Test: System status
aictl status
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows cluster status OR graceful "no cluster configured" message
- [ ] No crash or stack traces

```bash
# Test: Shell completion generation
aictl completion bash > /tmp/aictl-completion-test
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Generated file is non-empty
- [ ] Contains shell completion logic

```bash
# Cleanup
rm -f /tmp/aictl-completion-test
```

### Test 3: Dry-Run Operations

**Timeout:** 90 seconds  
**Dependencies:** None  
**Purpose:** Verify planning operations work without side effects

```bash
# Test: Cluster creation preview
aictl cluster create ${TEST_CLUSTER} --dry-run
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows planned operations
- [ ] No actual cluster created
- [ ] Output indicates dry-run mode

```bash
# Test: Installation preview  
aictl install --dry-run
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows Kubernetes resources to be created
- [ ] Mentions Helm chart or operator deployment

---

## Extended Smoke Tests (15-30 minutes)

Comprehensive validation of all aictl functionality. Use for release validation and detailed regression testing.

### Test 4: Cluster Lifecycle Management

**Timeout:** 300 seconds  
**Dependencies:** Kubernetes cluster access  
**Purpose:** Validate complete cluster management workflow

#### Setup
```bash
# Ensure clean state
aictl cluster list | grep -q ${TEST_CLUSTER} && aictl cluster delete ${TEST_CLUSTER} --force
```

#### Create Cluster
```bash
# Test: Cluster creation
aictl cluster create ${TEST_CLUSTER}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Success message displayed
- [ ] Cluster configuration stored

#### List and Inspect
```bash
# Test: Cluster listing
aictl cluster list
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Contains ${TEST_CLUSTER} in output
- [ ] Shows cluster status/details

```bash
# Test: Cluster inspection
aictl cluster inspect ${TEST_CLUSTER}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows detailed cluster information
- [ ] Includes configuration details

#### Context Switching
```bash
# Test: Current cluster display
aictl cluster current
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows current active cluster

```bash
# Test: Cluster switching
aictl use ${TEST_CLUSTER}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Confirmation message displayed
- [ ] Context successfully switched

#### Cleanup
```bash
# Test: Cluster deletion
aictl cluster delete ${TEST_CLUSTER} --yes
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Cluster removed from list
- [ ] Cleanup completed successfully

### Test 5: Model Management

**Timeout:** 180 seconds  
**Dependencies:** Active cluster  
**Purpose:** Validate model configuration and testing

#### Setup
```bash
# Ensure we have a cluster
aictl cluster create ${TEST_CLUSTER} 2>/dev/null || aictl use ${TEST_CLUSTER}
export TEST_MODEL="${TEST_PREFIX}-model"
```

#### Model Creation
```bash
# Test: Model creation with wizard (using defaults)
echo -e "gpt-4\nopenai\nsk-test-key\nn\ny" | aictl model create ${TEST_MODEL}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Model created successfully
- [ ] Configuration stored

**Alternative for non-interactive environments:**
```bash
# Test: Model creation with flags
aictl model create ${TEST_MODEL} --provider openai --model gpt-4 --api-key sk-test-key || echo "Interactive mode required"
```

#### Model Operations
```bash
# Test: Model listing
aictl model list
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Contains ${TEST_MODEL} in output
- [ ] Shows provider and model details

```bash
# Test: Model inspection
aictl model inspect ${TEST_MODEL}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows detailed model configuration
- [ ] Includes provider, model, and connection details

```bash
# Test: Model connectivity (may fail with test key)
aictl model test ${TEST_MODEL}
```
**Success Criteria:**
- [ ] Exit code: 0 (connection success) OR meaningful error message
- [ ] No crashes or stack traces
- [ ] Clear indication of test result

#### Cleanup
```bash
# Test: Model deletion
aictl model delete ${TEST_MODEL} --force
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Model removed from list
- [ ] Configuration cleaned up

### Test 6: Agent Lifecycle (Core Functionality)

**Timeout:** 600 seconds  
**Dependencies:** Active cluster with model  
**Purpose:** Validate complete agent workflow including synthesis

#### Setup
```bash
# Ensure prerequisites
aictl cluster create ${TEST_CLUSTER} 2>/dev/null || aictl use ${TEST_CLUSTER}
export TEST_AGENT="${TEST_PREFIX}-agent"
export AGENT_DESCRIPTION="a helpful assistant that responds to greetings and provides basic information"
```

#### Agent Creation
```bash
# Test: Agent creation from natural language
aictl agent create "${AGENT_DESCRIPTION}"
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Agent creation initiated
- [ ] Synthesis process started

```bash
# Alternative: Agent creation with wizard
aictl agent create --wizard < /dev/null || echo "Wizard requires interactive input"
```

#### Agent Operations
```bash
# Test: Agent listing
aictl agent list
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows created agent
- [ ] Displays agent status

#### Wait for Synthesis
```bash
# Test: Check synthesis status (retry mechanism)
for i in {1..30}; do
    if aictl agent inspect ${TEST_AGENT} 2>/dev/null | grep -q "Synthesized.*True"; then
        echo "Agent synthesis completed"
        break
    fi
    echo "Waiting for synthesis... (${i}/30)"
    sleep 10
done
```
**Success Criteria:**
- [ ] Agent synthesis completes within 5 minutes
- [ ] No synthesis errors reported
- [ ] Agent status shows as synthesized

#### Code and Logs
```bash
# Test: Synthesized code retrieval
aictl agent code ${TEST_AGENT}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Code output contains Ruby class definition
- [ ] No empty or malformed code

```bash
# Test: Agent logs access
aictl agent logs ${TEST_AGENT} --tail 10
```
**Success Criteria:**
- [ ] Exit code: 0 OR expected "no logs yet" message
- [ ] No permission errors
- [ ] Proper log formatting if logs exist

#### Agent Management
```bash
# Test: Agent inspection
aictl agent inspect ${TEST_AGENT}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows comprehensive agent details
- [ ] Includes status, configuration, and runtime info

```bash
# Test: Agent versions
aictl agent versions ${TEST_AGENT}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows version history or current version
- [ ] No errors accessing ConfigMaps

#### Workspace Operations
```bash
# Test: Workspace access
aictl agent workspace ${TEST_AGENT} --list
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows workspace contents or empty workspace
- [ ] No permission errors

#### Learning Operations
```bash
# Test: Learning status
aictl agent learning status ${TEST_AGENT}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows learning configuration
- [ ] No crashes on learning queries

#### Cleanup
```bash
# Test: Agent deletion
aictl agent delete ${TEST_AGENT}
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Agent removed from list
- [ ] Kubernetes resources cleaned up

### Test 7: Tool Management

**Timeout:** 180 seconds  
**Dependencies:** Active cluster  
**Purpose:** Validate tool installation and management

#### Setup
```bash
aictl cluster create ${TEST_CLUSTER} 2>/dev/null || aictl use ${TEST_CLUSTER}
```

#### Tool Operations
```bash
# Test: Tool search
aictl tool search github
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Returns search results
- [ ] Shows available tools or "no tools found"

```bash
# Test: Tool listing
aictl tool list
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows installed tools or empty list
- [ ] Proper formatting

```bash
# Test: Tool installation (if available)
aictl tool install filesystem 2>/dev/null || echo "Tool not available in registry"
```
**Success Criteria:**
- [ ] Exit code: 0 OR expected "not found" error
- [ ] Clear success/failure message
- [ ] No crashes

```bash
# Test: Tool inspection (if installed)
aictl tool inspect filesystem 2>/dev/null || echo "Tool not installed"
```
**Success Criteria:**
- [ ] Exit code: 0 OR expected "not found" error
- [ ] Shows tool details if available
- [ ] Proper error handling

```bash
# Test: Tool health check (if installed)
aictl tool test filesystem 2>/dev/null || echo "Tool not available"
```
**Success Criteria:**
- [ ] Exit code: 0 OR expected error
- [ ] Health check results displayed
- [ ] No crashes on test execution

### Test 8: Persona Management

**Timeout:** 120 seconds  
**Dependencies:** None (personas are local)  
**Purpose:** Validate persona configuration management

#### Persona Operations
```bash
# Test: Persona listing
aictl persona list
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows available personas
- [ ] Proper formatting

```bash
# Test: Persona display
aictl persona show helpful-assistant 2>/dev/null || aictl persona show $(aictl persona list | head -1 | awk '{print $1}')
```
**Success Criteria:**
- [ ] Exit code: 0 OR "not found" error
- [ ] Shows persona definition if available
- [ ] Proper YAML/text formatting

```bash
# Test: Persona creation (non-interactive)
export TEST_PERSONA="${TEST_PREFIX}-persona"
echo "A test persona for smoke testing" | aictl persona create ${TEST_PERSONA} 2>/dev/null || echo "Interactive mode required"
```
**Success Criteria:**
- [ ] Exit code: 0 OR expected interactive mode error
- [ ] Persona created if non-interactive supported
- [ ] Clear messaging about requirements

### Test 9: Installation Operations

**Timeout:** 120 seconds  
**Dependencies:** Kubernetes cluster  
**Purpose:** Validate operator installation workflow

#### Installation Testing
```bash
# Test: Installation preview
aictl install --dry-run
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows planned Kubernetes resources
- [ ] Indicates Helm chart or operator components

```bash
# Test: Installation status check
aictl install --check 2>/dev/null || echo "Check command not available"
```
**Success Criteria:**
- [ ] Shows installation status
- [ ] No crashes on status check
- [ ] Clear indication of operator state

```bash
# Test: Upgrade preview
aictl upgrade --dry-run 2>/dev/null || echo "Upgrade requires existing installation"
```
**Success Criteria:**
- [ ] Shows upgrade plan OR appropriate error
- [ ] No crashes
- [ ] Clear messaging

### Test 10: System Utilities

**Timeout:** 90 seconds  
**Dependencies:** None  
**Purpose:** Validate system diagnostic and validation tools

#### System Operations
```bash
# Test: Schema display
aictl system schema
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Shows JSON schema
- [ ] Valid JSON format

```bash
# Test: Template validation
echo 'agent "test" { description "test agent" }' > /tmp/test-template.agent
aictl system validate-template /tmp/test-template.agent
```
**Success Criteria:**
- [ ] Exit code: 0
- [ ] Validation passes OR shows specific errors
- [ ] Clear validation results

```bash
# Test: Synthesis template display
aictl system synthesis-template test 2>/dev/null || echo "Template not found (expected)"
```
**Success Criteria:**
- [ ] Exit code: 0 OR expected "not found" error
- [ ] Shows template if available
- [ ] Proper error handling

#### Cleanup
```bash
rm -f /tmp/test-template.agent
```

---

## Error Handling and Recovery

### Common Failure Patterns

#### Connection Issues
**Problem**: Cannot connect to Kubernetes cluster
**Symptoms**: `kubectl` commands fail, cluster operations error
**Recovery**:
```bash
# Check cluster access
kubectl cluster-info
kubectl get nodes

# Verify context
kubectl config current-context
kubectl config get-contexts
```

#### Permission Issues
**Problem**: Insufficient RBAC permissions
**Symptoms**: "forbidden" errors, resource creation fails
**Recovery**:
```bash
# Check current permissions
kubectl auth can-i create deployments
kubectl auth can-i create configmaps
kubectl auth can-i create services
```

#### Resource Conflicts
**Problem**: Resources already exist
**Symptoms**: "already exists" errors
**Recovery**:
```bash
# Clean up conflicting resources
aictl cluster delete ${TEST_CLUSTER} --force
kubectl delete namespace ${TEST_NAMESPACE} --force
```

#### Synthesis Timeouts
**Problem**: Agent synthesis takes too long
**Symptoms**: Synthesis never completes, timeouts
**Recovery**:
```bash
# Check operator logs
kubectl logs -l app=language-operator -n language-operator-system

# Verify model connectivity
aictl model test ${TEST_MODEL}

# Check agent events
kubectl get events --field-selector involvedObject.name=${TEST_AGENT}
```

### Cleanup Procedures

#### Complete Environment Reset
```bash
# Remove all test resources
aictl cluster delete ${TEST_CLUSTER} --force 2>/dev/null || true
aictl model delete ${TEST_MODEL} --force 2>/dev/null || true
aictl persona delete ${TEST_PERSONA} --force 2>/dev/null || true

# Clean Kubernetes resources
kubectl delete namespace ${TEST_NAMESPACE} --force 2>/dev/null || true
kubectl delete configmaps -l test-prefix=${TEST_PREFIX} 2>/dev/null || true
```

#### Verification of Cleanup
```bash
# Verify resources removed
aictl cluster list | grep -v ${TEST_PREFIX}
aictl agent list | grep -v ${TEST_PREFIX}
kubectl get all -l test-prefix=${TEST_PREFIX}
```

---

## Agent Execution Metadata

### Parsing Instructions for Agents

**Test Structure Recognition:**
- Tests are marked with `### Test N:` headers
- Success criteria are checkbox lists `- [ ]`
- Commands are in code blocks with `bash` language
- Metadata is in **Key:** Value format

**Execution Flow:**
1. Parse prerequisites and validate environment
2. Set up environment variables from setup sections
3. Execute tests in order, respecting timeouts
4. Validate success criteria after each command
5. Handle failures according to recovery procedures
6. Execute cleanup procedures

**Timeout Handling:**
- Global timeout: 30 minutes for full suite
- Individual test timeouts specified in metadata
- Command timeout: 30 seconds unless specified

**Success Reporting:**
- Track pass/fail for each test
- Generate summary report with failure details
- Include command outputs for failed tests
- Report total execution time

**Environment Variables for Agents:**
```bash
SMOKE_TEST_MODE="quick|extended"
SMOKE_TEST_CLEANUP="true|false"  
SMOKE_TEST_CLUSTER_NAME="existing-cluster-name"
SMOKE_TEST_TIMEOUT="1800"  # 30 minutes
SMOKE_TEST_NAMESPACE="smoke-test"
```

---

## Conclusion

This playbook provides comprehensive validation of aictl functionality through structured, executable tests. It serves as both documentation for manual testing and instructions for automated agent execution.

**Quick smoke tests** validate critical functionality in CI/CD pipelines, while **extended tests** provide thorough regression testing for releases.

**Total Estimated Execution Time:**
- Quick tests: 5-10 minutes
- Extended tests: 15-30 minutes  
- With cleanup: Add 2-5 minutes

For questions or issues, refer to the troubleshooting guide or consult the aictl documentation.