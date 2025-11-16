# Synthesis Test Suite

This directory contains a test suite for validating agent code synthesis locally without requiring a Kubernetes cluster.

## Purpose

The synthesis test suite allows you to:

1. **Test synthesis locally** - Generate Ruby DSL code from LanguageAgent YAML specs
2. **Compare models** - See how different LLMs (Claude, GPT-4) synthesize the same agent
3. **Iterate quickly** - Test template/prompt changes without deploying to K8s
4. **Build regression tests** - Verify synthesis quality doesn't degrade
5. **Debug synthesis issues** - Identify and fix problems in the synthesis pipeline

## Directory Structure

```
synth/
├── Makefile              # Top-level test runner
├── README.md             # This file
└── 001/                  # Test case: "hello-world"
    ├── agent.yaml        # Input: LanguageAgent spec
    ├── agent.rb          # Output: Generated code (default model)
    ├── agent.sonnet.rb   # Output: Claude Sonnet
    ├── agent.gpt-4.rb    # Output: GPT-4
    └── Makefile          # Test-specific targets
```

## Quick Start

### Prerequisites

**Option 1: Local OpenAI-Compatible Endpoint (Recommended)**

Use a local LLM server (LMStudio, vLLM, Ollama with OpenAI adapter, etc.):

```bash
export SYNTHESIS_ENDPOINT="http://192.168.68.54:1234/v1"
export SYNTHESIS_API_KEY="dummy"  # Optional, defaults to "dummy"
export SYNTHESIS_MODEL="mistralai/magistral-small-2509"  # Or your quantized model
```

**Option 2: Cloud API Keys**

```bash
export ANTHROPIC_API_KEY="sk-ant-..."  # For Claude
export OPENAI_API_KEY="sk-..."         # For GPT-4
```

The harness prioritizes `SYNTHESIS_ENDPOINT` if set, allowing you to test on quantized local models before hitting cloud APIs.

### Run a Test

```bash
# Run synthesis for test 001
cd synth/001
make synthesize

# View the generated code
cat agent.rb

# Execute the agent locally
make run

# Clean up
make clean
```

### Compare Models

```bash
cd synth/001

# Generate with all models
make synthesize-all

# Compare outputs
make compare

# Or manually inspect
cat agent.sonnet.rb
cat agent.gpt-4.rb
```

## Test Case Format

Each test case is a numbered directory (`001`, `002`, etc.) containing:

### agent.yaml

A LanguageAgent CRD spec:

```yaml
apiVersion: langop.io/v1alpha1
kind: LanguageAgent
metadata:
  name: hello-world
spec:
  instructions: |
    Say something in your logs
  # Optional: toolRefs, modelRefs, personaRefs, etc.
```

### Expected Output

The synthesis process should generate a Ruby file like:

```ruby
require 'language_operator'

agent "hello-world" do
  description "Say something in your logs"
  mode :autonomous
  objectives [
    "Log a message to the console"
  ]
  constraints do
    max_iterations 1
    timeout "30s"
  end
end
```

## Makefile Targets

### In Test Directory (`synth/001/`)

| Target | Description |
|--------|-------------|
| `make synthesize` | Generate `agent.rb` with default model |
| `make synthesize-sonnet` | Generate `agent.sonnet.rb` with Claude |
| `make synthesize-gpt-4` | Generate `agent.gpt-4.rb` with GPT-4 |
| `make synthesize-all` | Generate for all configured models |
| `make run` | Execute the synthesized `agent.rb` locally |
| `make validate` | Validate Ruby syntax of `agent.rb` |
| `make clean` | Remove all generated `.rb` files |
| `make compare` | Diff outputs from different models |

### Top-Level (`synth/`)

| Target | Description |
|--------|-------------|
| `make test` | Run default synthesis for all tests |
| `make test-all` | Run synthesis with all models |
| `make clean` | Clean all test artifacts |
| `make list` | List available test cases |

## How It Works

### Synthesis Flow

1. **Load agent.yaml** - Parse LanguageAgent spec
2. **Extract fields** - Get instructions, tools, models, persona
3. **Build prompt** - Fill synthesis template with extracted data
4. **Call LLM** - Send prompt to Claude/GPT-4
5. **Extract code** - Parse Ruby code from markdown response
6. **Validate** - Check syntax and security (AST validation)
7. **Write output** - Save to `agent.rb` or model-specific file

### Implementation

The synthesis functionality is now integrated directly into the `aictl` CLI:

```bash
aictl system synthesize [INSTRUCTIONS]
```

This command uses LanguageModel resources from your cluster to generate agent code.

## Adding New Test Cases

1. Create a new directory:
   ```bash
   mkdir synth/002
   ```

2. Copy the Makefile template:
   ```bash
   cp synth/001/Makefile synth/002/
   ```

3. Create `agent.yaml`:
   ```yaml
   apiVersion: langop.io/v1alpha1
   kind: LanguageAgent
   metadata:
     name: my-test-agent
   spec:
     instructions: |
       Your test instructions here
   ```

4. Run synthesis:
   ```bash
   cd synth/002
   make synthesize
   ```

5. Update top-level Makefile to include new test

## Example Test Cases

### 001 - Hello World
**Instructions**: "Say something in your logs"
**Expected**: Simple autonomous agent with single objective

### 002 - Scheduled Agent (Future)
**Instructions**: "Check website daily at noon"
**Expected**: Scheduled agent with cron expression

### 003 - Reactive Webhook (Future)
**Instructions**: "When webhook received, send email"
**Expected**: Reactive agent with webhook definition

### 004 - Multi-Step Workflow (Future)
**Instructions**: "Fetch data from API, analyze it, save results"
**Expected**: Agent with workflow steps and dependencies

## Relationship to `aictl system test-synthesis`

The `aictl system test-synthesis` command provides similar functionality but with different interface:

```bash
# CLI-based (existing command)
aictl system test-synthesis --instructions "Say something in your logs"

# YAML-based (this test suite)
cd synth/001 && make synthesize
```

**Benefits of YAML test suite:**
- ✅ Version controlled test cases
- ✅ Easy to compare model outputs side-by-side
- ✅ Repeatable regression testing
- ✅ Can specify full LanguageAgent spec (tools, models, etc.)

**Benefits of CLI command:**
- ✅ Quick one-off testing
- ✅ No file management
- ✅ Integrated with aictl workflow

Both are valuable for different use cases!

## Troubleshooting

### API Key Not Found

```
Error: No API key found. Set either:
  SYNTHESIS_ENDPOINT (for local/OpenAI-compatible)
  ANTHROPIC_API_KEY (for Claude)
  OPENAI_API_KEY (for GPT)
```

**Solution**: Set environment variables:
```bash
# For local endpoint (recommended)
export SYNTHESIS_ENDPOINT="http://localhost:1234/v1"
export SYNTHESIS_MODEL="your-model-name"

# OR for cloud APIs
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
```

### Synthesis Failed

```
Error: LLM call failed: ...
```

**Solution**: Check:
- API key is valid
- Network connectivity
- Model name is correct
- LLM service is available

### Validation Failed

```
Error: Security validation failed
```

**Solution**: The generated code contains dangerous methods. This is a synthesis quality issue - the template needs improvement or the LLM hallucinated unsafe code.

### Empty Output

```
Error: Empty code generated
```

**Solution**: The LLM didn't return code in the expected format. Check the prompt and template.

## Development Workflow

### Iterate on Template Changes

1. Edit template: `lib/language_operator/templates/examples/agent_synthesis.tmpl`
2. Test locally: `cd synth/001 && make clean && make synthesize`
3. Review output: `cat agent.rb`
4. Repeat until satisfied
5. Copy to operator: Update Go operator's embedded template

### Test DSL Changes

1. Add new DSL feature to schema
2. Update template to show example of new feature
3. Create test case exercising new feature
4. Run synthesis: `make synthesize`
5. Verify generated code uses new feature correctly

## Future Enhancements

- [ ] Automated comparison with expected output (golden files)
- [ ] CI/CD integration (run on every PR)
- [ ] Metrics tracking (synthesis quality over time)
- [ ] More test cases covering all DSL features
- [ ] Support for additional models (Gemini, etc.)
- [ ] Template A/B testing (compare different prompt versions)

## Related Commands

```bash
# View DSL schema
aictl system schema

# View synthesis template
aictl system synthesis-template

# Validate template
aictl system validate_template

# Test synthesis (CLI)
aictl system test-synthesis --instructions "..."
```

## Questions?

See the main project documentation:
- [Agent DSL Reference](../docs/dsl/agent-reference.md)
- [Best Practices](../docs/dsl/best-practices.md)
- [CLAUDE.md](../CLAUDE.md) - AI context document
