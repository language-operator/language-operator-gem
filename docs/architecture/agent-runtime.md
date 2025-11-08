# Agent Runtime Architecture

This document explains how synthesized agent code becomes a running agent in the Language Operator system.

## Overview

The Language Operator follows this flow:

```
Natural Language Description
         ↓
Operator synthesizes Ruby DSL code
         ↓
Stores in ConfigMap "<agent-name>-code"
         ↓
Creates Pod with ConfigMap mounted
         ↓
Ruby runtime loads and executes agent
         ↓
Agent executes workflow using tools and models
```

## Components

### 1. Synthesis Phase (Go Operator)

The Kubernetes operator receives an `LanguageAgent` custom resource:

```yaml
apiVersion: language-operator.io/v1alpha1
kind: LanguageAgent
metadata:
  name: email-summarizer
spec:
  description: "Check my inbox every hour and send me a summary"
  model: claude-3-5-sonnet
  schedule:
    cron: "0 * * * *"
```

The operator:
1. Sends description to LLM for synthesis
2. LLM generates Ruby DSL code
3. Stores code in ConfigMap `email-summarizer-code` with key `agent.rb`

**Example synthesized code:**
```ruby
agent "email-summarizer" do
  description "Check inbox hourly and send summary"

  objectives [
    "Connect to Gmail",
    "Fetch unread messages from the last hour",
    "Summarize key points",
    "Send summary email"
  ]

  workflow do
    step :fetch_emails,
         tool: "gmail",
         instruction: "Get unread emails from last hour"

    step :summarize,
         instruction: "Create bullet-point summary of emails"

    step :send_summary,
         tool: "gmail",
         instruction: "Send summary to user"
  end

  constraints do
    max_iterations 50
    timeout "5m"
  end
end
```

### 2. Pod Creation Phase (Go Operator)

The operator creates a Pod for the agent:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: email-summarizer-xyz123
  namespace: default
spec:
  containers:
  - name: agent
    image: language-operator/agent-runtime:v0.1.0
    env:
    - name: AGENT_NAME
      value: "email-summarizer"
    - name: AGENT_CODE_PATH
      value: "/config/agent.rb"
    - name: MODEL_ENDPOINTS
      value: "https://api.anthropic.com/v1/messages"
    - name: MCP_SERVERS
      value: "http://gmail-tool.default.svc.cluster.local:3000"
    - name: WORKSPACE_PATH
      value: "/workspace"
    - name: AGENT_MODE
      value: "scheduled"
    volumeMounts:
    - name: agent-code
      mountPath: /config
      readOnly: true
    - name: workspace
      mountPath: /workspace
  volumes:
  - name: agent-code
    configMap:
      name: email-summarizer-code
  - name: workspace
    persistentVolumeClaim:
      claimName: email-summarizer-workspace
```

### 3. Runtime Initialization Phase (Ruby)

**Entrypoint:** `lib/language_operator/agent.rb`

The container starts with this entrypoint:

```ruby
#!/usr/bin/env ruby

require 'language_operator'

# Start the agent runtime
LanguageOperator::Agent.run
```

**What happens in `Agent.run`:**

```ruby
module LanguageOperator
  module Agent
    def self.run
      # Load configuration (environment variables)
      config = Client::Config.new

      # Create agent instance
      agent = Base.new(config)

      # Start execution
      agent.run
    end
  end
end
```

### 4. Configuration Loading

**File:** `lib/language_operator/client/config.rb`

The configuration system reads environment variables:

```ruby
module LanguageOperator
  module Client
    class Config
      def self.from_env
        {
          model_endpoints: parse_endpoints(ENV['MODEL_ENDPOINTS']),
          mcp_servers: parse_endpoints(ENV['MCP_SERVERS']),
          workspace_path: ENV['WORKSPACE_PATH'] || '/workspace',
          agent_mode: ENV['AGENT_MODE'] || 'autonomous'
        }
      end

      private

      def self.parse_endpoints(value)
        return [] unless value
        value.split(',').map(&:strip)
      end
    end
  end
end
```

### 5. Agent Execution

**File:** `lib/language_operator/agent/base.rb`

The agent base class handles execution mode:

```ruby
module LanguageOperator
  module Agent
    class Base
      def initialize(config)
        @config = config
        @workspace = Workspace.new(config.workspace_path)
        @executor = Executor.new(config)
      end

      def run
        case @config.agent_mode
        when 'autonomous'
          run_autonomous
        when 'scheduled'
          run_scheduled
        else
          raise "Unknown agent mode: #{@config.agent_mode}"
        end
      end

      private

      def run_autonomous
        # Continuous execution loop
        loop do
          @executor.run_cycle
          sleep 1
        end
      end

      def run_scheduled
        # Wait for schedule trigger, then execute once
        @executor.run_cycle
      end
    end
  end
end
```

### 6. DSL Code Loading (Future Implementation)

**Note:** This integration is planned but not yet implemented. The DSL infrastructure exists but needs to be wired into the agent runtime.

**Planned implementation:**

```ruby
def run_autonomous
  # Load synthesized agent code
  agent_code_path = ENV['AGENT_CODE_PATH'] || '/config/agent.rb'

  if File.exist?(agent_code_path)
    # Load the DSL file
    LanguageOperator::Dsl.load_agent_file(agent_code_path)

    # Get agent definition from registry
    agent_name = ENV['AGENT_NAME']
    agent_def = LanguageOperator::Dsl.agent_registry.get(agent_name)

    if agent_def&.workflow
      # Execute the defined workflow
      @executor.execute_workflow(agent_def)
    else
      # Fall back to autonomous mode
      @executor.run_cycle
    end
  else
    # No synthesized code, run generic autonomous mode
    @executor.run_cycle
  end
end
```

**The DSL loader** (`lib/language_operator/dsl.rb:109-121`):

```ruby
module LanguageOperator
  module Dsl
    def self.load_agent_file(path)
      context = AgentContext.new
      code = File.read(path)
      context.instance_eval(code, path)
    end
  end
end
```

**The registry** (`lib/language_operator/dsl/agent_context.rb:47-88`):

```ruby
module LanguageOperator
  module Dsl
    class AgentRegistry
      def initialize
        @agents = {}
      end

      def register(name, definition)
        @agents[name.to_s] = definition
      end

      def get(name)
        @agents[name.to_s]
      end

      def all
        @agents.values
      end
    end

    def self.agent_registry
      @agent_registry ||= AgentRegistry.new
    end
  end
end
```

### 7. Workflow Execution

**File:** `lib/language_operator/agent/executor.rb`

The executor runs the agent's workflow:

```ruby
module LanguageOperator
  module Agent
    class Executor
      def execute_workflow(agent_definition)
        # Extract workflow from agent definition
        workflow = agent_definition.workflow

        # Execute each step
        workflow.steps.each do |step|
          execute_step(step)
        end
      end

      def execute_step(step)
        case step.type
        when :tool
          call_tool(step.tool, step.instruction)
        when :analysis
          analyze(step.instruction)
        else
          # Generic LLM call
          call_llm(step.instruction)
        end
      end
    end
  end
end
```

## Environment Variables

The agent runtime uses these environment variables (injected by the operator):

| Variable | Description | Example |
|----------|-------------|---------|
| `AGENT_NAME` | Name of the agent | `email-summarizer` |
| `AGENT_CODE_PATH` | Path to synthesized DSL code | `/config/agent.rb` |
| `CONFIG_PATH` | Optional YAML config file | `/config/config.yaml` |
| `MODEL_ENDPOINTS` | Comma-separated LLM API endpoints | `https://api.anthropic.com/v1/messages` |
| `MCP_SERVERS` | Comma-separated MCP tool server URLs | `http://gmail.svc:3000,http://slack.svc:3000` |
| `WORKSPACE_PATH` | Path to persistent workspace | `/workspace` |
| `AGENT_MODE` | Execution mode (`autonomous` or `scheduled`) | `scheduled` |

## Complete Flow Example

### 1. User creates agent
```bash
$ aictl agent create "check my inbox every hour and send me a summary"
```

### 2. Operator synthesizes code

The operator calls an LLM with a synthesis prompt and receives:

```ruby
agent "inbox-checker-abc123" do
  description "Check inbox hourly and send summary"

  objectives [
    "Fetch unread emails",
    "Create summary",
    "Send notification"
  ]

  workflow do
    step :fetch, tool: "gmail"
    step :summarize
    step :notify, tool: "gmail"
  end
end
```

### 3. Operator creates ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: inbox-checker-abc123-code
data:
  agent.rb: |
    agent "inbox-checker-abc123" do
      description "Check inbox hourly and send summary"
      # ... (full code)
    end
```

### 4. Operator creates Pod

Pod spec includes:
- ConfigMap mounted at `/config/agent.rb`
- Environment variables set
- Workspace PVC mounted at `/workspace`

### 5. Container starts

```
$ /usr/local/bin/agent-runtime
→ Loads lib/language_operator/agent.rb
→ Calls LanguageOperator::Agent.run
→ Creates Agent::Base instance
→ Loads environment config
```

### 6. Agent initializes

```
→ Reads MODEL_ENDPOINTS
→ Reads MCP_SERVERS
→ Connects to workspace at /workspace
→ Checks AGENT_MODE = "scheduled"
```

### 7. Code loads (future)

```
→ Reads /config/agent.rb
→ Evaluates DSL code
→ Registers agent in AgentRegistry
→ Retrieves agent definition
```

### 8. Execution begins

```
→ Executor.execute_workflow(agent_def)
→ Runs each workflow step
→ Calls tools via MCP
→ Calls LLM for reasoning
→ Writes state to workspace
```

## State and Memory

Agents maintain state in their workspace:

```bash
/workspace/
├── state.json          # Current agent state
├── history.log         # Execution history
├── cache/              # Cached data
│   └── emails.json
└── reports/            # Generated outputs
    └── summary.md
```

**Example state file:**

```json
{
  "last_run": "2025-11-08T09:00:00Z",
  "emails_processed": 47,
  "status": "success"
}
```

**Agents can read their own state:**

```ruby
workflow do
  step :load_state,
       instruction: "Read /workspace/state.json to see when we last ran"

  step :fetch_emails,
       tool: "gmail",
       instruction: "Fetch emails since last run timestamp"

  step :save_state,
       instruction: "Update /workspace/state.json with current timestamp"
end
```

## Tool Integration

Agents communicate with MCP tool servers over HTTP:

```
Agent Pod                         Tool Pod
┌─────────────┐                  ┌──────────┐
│             │ HTTP POST        │          │
│  Executor   │─────────────────▶│  Gmail   │
│             │ /tools/send      │  MCP     │
│             │                  │  Server  │
│             │◀─────────────────│          │
│             │ Response         │          │
└─────────────┘                  └──────────┘
```

**Tool call example:**

```ruby
# In executor
def call_tool(tool_name, instruction)
  endpoint = find_tool_endpoint(tool_name)

  response = HTTP.post("#{endpoint}/tools/execute", json: {
    tool: tool_name,
    instruction: instruction,
    context: current_context
  })

  response.parse
end
```

## Model Integration

Agents call LLM APIs for reasoning:

```ruby
def call_llm(instruction)
  endpoint = @config.model_endpoints.first

  response = HTTP.post(endpoint, json: {
    model: "claude-3-5-sonnet-20241022",
    messages: [{
      role: "user",
      content: instruction
    }]
  })

  response.parse["content"]
end
```

## Debugging

To inspect a running agent:

```bash
# View agent logs
$ kubectl logs inbox-checker-abc123

# View workspace files
$ kubectl exec inbox-checker-abc123 -- ls -la /workspace

# View synthesized code
$ kubectl get configmap inbox-checker-abc123-code -o yaml

# View environment variables
$ kubectl exec inbox-checker-abc123 -- env | grep AGENT
```

## Current Limitations

1. **DSL integration not complete:** The synthesized code is stored in ConfigMap but not yet loaded by the runtime
2. **No workflow execution:** Agents run in generic autonomous mode, not executing defined workflows
3. **Limited error recovery:** Failed agents don't automatically restart
4. **No agent-to-agent communication:** Agents can't coordinate with each other yet

## Future Enhancements

1. **Complete DSL integration:** Wire up ConfigMap code loading into agent runtime
2. **Workflow engine:** Full support for multi-step workflows with conditionals
3. **Agent coordination:** Pub/sub system for agent communication
4. **Hot reloading:** Update agent code without pod restart
5. **Debugging tools:** Interactive agent inspection and step-through

## Related Files

- [lib/language_operator/agent.rb](../../lib/language_operator/agent.rb) - Entrypoint
- [lib/language_operator/agent/base.rb](../../lib/language_operator/agent/base.rb) - Agent initialization
- [lib/language_operator/agent/executor.rb](../../lib/language_operator/agent/executor.rb) - Execution engine
- [lib/language_operator/dsl.rb](../../lib/language_operator/dsl.rb) - DSL loader
- [lib/language_operator/dsl/agent_context.rb](../../lib/language_operator/dsl/agent_context.rb) - Agent registry
- [lib/language_operator/client/config.rb](../../lib/language_operator/client/config.rb) - Configuration
- [examples/agent_example.rb](../../examples/agent_example.rb) - DSL example

## References

- [Language Operator README](../../README.md)
- [Architecture Review: requirements/reviews/001.md](../../requirements/reviews/001.md)
