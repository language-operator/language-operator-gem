# 003 - Workspace File Operations & Scheduled Mode

## Instructions

"Write a story one sentence at a time, with one new sentence every hour."

## Significance

This test validates **stateful execution with workspace file operations** - the ability for agents to persist and accumulate data across multiple scheduled executions.

While test 002 proved we can execute neural tasks on a schedule, this test proves we can maintain **persistent state** across runs using the workspace directory.

## What This Demonstrates

### 1. Workspace File Operations

Agents have access to a persistent workspace directory for file operations:
- ✅ **File reading** - Check if story file exists and read current content
- ✅ **File writing** - Append new sentences to the story
- ✅ **Stateful execution** - Each run builds on previous runs
- ✅ **Standard Ruby File APIs** - Use `File.read`, `File.write`, etc.

### 2. Scheduled Execution with State

```ruby
mode :scheduled
schedule "0 * * * *"  # Every hour
```

Validates that scheduled agents can maintain state across runs:
- ✅ **Persistent storage** - Workspace directory survives pod restarts
- ✅ **Cumulative behavior** - Each execution reads previous state, adds to it
- ✅ **Multi-run workflows** - Tasks that span multiple scheduled executions

### 3. Complete Stateful Execution Flow

```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes CronJob Triggers (every hour)               │
│  Pod starts with mounted workspace volume               │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Agent Runtime Loads                                    │
│  Mode: scheduled → Execute once and exit                │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  main Block Executes                                    │
│  1. Check if story.txt exists in workspace              │
│  2. Read existing content (if any)                      │
│  3. Execute task to generate next sentence              │
│  4. Append sentence to story.txt                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  File persisted to workspace volume                     │
│  Pod exits → Kubernetes waits for next hour             │
└─────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Next Hour: New pod starts                              │
│  Same workspace volume mounted                          │
│  Reads previous content, adds new sentence              │
└─────────────────────────────────────────────────────────┘
```

## Why This Matters

### Stateful Agents Enable New Use Cases

This test unlocks a critical capability for real-world agents:

**Before (Stateless):**
- Each execution is isolated
- No memory of previous runs
- Limited to one-shot tasks

**After (Stateful with Workspace):**
- Accumulate data over time
- Build complex artifacts across multiple runs
- Enable learning and evolution

### Real-World Applications

This pattern enables:

1. **Incremental Report Building** - Add data to reports over days/weeks
2. **Data Collection Pipelines** - Append to datasets on each run
3. **Monitoring & Alerting** - Track state changes across time
4. **Creative Projects** - Build stories, documents, code incrementally
5. **Learning Systems** - Store observations and improve over time

## Expected Behavior

### Run 1 (Hour 1)
- Story file doesn't exist
- Agent generates opening sentence
- Writes: "Once upon a time, there was a brave knight."

### Run 2 (Hour 2)
- Story file exists with 1 sentence
- Agent reads it, generates next sentence
- Appends: "The knight embarked on a quest to find the lost treasure."

### Run 3 (Hour 3)
- Story file exists with 2 sentences
- Agent reads it, generates continuation
- Appends: "Along the way, she met a wise old wizard."

...and so on, building a complete story over time.

## Technical Implementation Notes

### Workspace Directory

- **Location**: Typically `/workspace` in the container
- **Persistence**: Backed by Kubernetes PersistentVolume
- **Access**: Standard Ruby `File` and `Dir` operations
- **Lifecycle**: Survives pod restarts, shared across scheduled runs

### File Operation Patterns

```ruby
# Read existing story
story_path = '/workspace/story.txt'
existing_story = File.exist?(story_path) ? File.read(story_path) : ""

# Generate next sentence (neural task)
next_sentence = execute_task(:generate_next_sentence, inputs: { context: existing_story })

# Append to story
File.open(story_path, 'a') do |f|
  f.puts next_sentence
end
```

## Testing Locally

```bash
# Synthesize the agent
make synthesize

# Execute locally (simulates one run)
make exec

# Run multiple times to simulate scheduled execution
make exec  # Run 1
make exec  # Run 2
make exec  # Run 3
```

Each local execution should append to the story, demonstrating the stateful behavior.

## What Makes This Interesting

### 1. Emergent Behavior
The agent doesn't know the full story in advance - it emerges sentence by sentence, with each new sentence influenced by what came before.

### 2. LLM Context Management
The agent must pass the growing story as context to generate coherent continuations. This tests context window management.

### 3. File I/O Integration
Proves that agents can use standard Ruby file operations within the safety sandbox.

### 4. Time-Based Workflows
Demonstrates workflows that unfold over hours/days, not just seconds.

## Success Criteria

- ✅ Agent successfully reads workspace files
- ✅ Agent successfully writes/appends to workspace files
- ✅ Story grows by one sentence per execution
- ✅ Each sentence is contextually coherent with previous sentences
- ✅ File persists across multiple runs
- ✅ No errors in scheduled execution

## Future Extensions

This pattern could be extended to:
- **Multi-file projects** - Build entire codebases incrementally
- **Data analysis** - Accumulate findings in structured files
- **Version control integration** - Track changes over time
- **Collaboration** - Multiple agents reading/writing shared files
