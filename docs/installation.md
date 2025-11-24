# Installation Guide

Get started with Language Operator by installing the CLI and setting up your first cluster.

## Prerequisites

- Ruby >= 3.2.0
- Kubernetes cluster (local or remote)
- `kubectl` configured with cluster access

## Install the CLI

### Using RubyGems

```bash
gem install language-operator
```

### Verify Installation

```bash
aictl version
```

You should see the aictl version and operator status information.

## Initial Setup

### 1. Check System Status

```bash
aictl status
```

This command shows:
- CLI version
- Kubernetes connectivity
- Language Operator installation status

### 2. Run Quickstart Wizard

For first-time users, the quickstart wizard guides you through setup:

```bash
aictl quickstart
```

The wizard will:
- Configure your first cluster
- Install Language Operator to Kubernetes
- Set up basic models and personas
- Create a sample agent

### 3. Manual Setup (Alternative)

If you prefer manual configuration:

```bash
# Create cluster configuration
aictl cluster create my-cluster

# Switch to the cluster
aictl use my-cluster

# Install Language Operator
aictl install

# Verify installation
aictl status
```

## Kubernetes Setup

### Local Development (minikube/kind)

```bash
# Start minikube
minikube start

# Or start kind cluster
kind create cluster --name language-operator

# Configure aictl
aictl cluster create local --kubeconfig ~/.kube/config
aictl use local
```

### Production Clusters

```bash
# Configure cluster with specific context
aictl cluster create production \
  --kubeconfig /path/to/kubeconfig \
  --context production-context

aictl use production
```

## Model Configuration

Language Operator requires language model access. Configure your preferred provider:

### OpenAI

```bash
export OPENAI_API_KEY="sk-your-api-key"
aictl model create openai-gpt4 --provider openai --model gpt-4-turbo
```

### Anthropic (Claude)

```bash
export ANTHROPIC_API_KEY="sk-your-api-key"  
aictl model create claude-sonnet --provider anthropic --model claude-3-sonnet
```

### Local Models (Ollama)

```bash
# Start Ollama locally
ollama serve

# Configure local model
aictl model create local-llama --provider ollama --model llama3
```

## Verification

### Test Your Setup

```bash
# Check overall status
aictl status

# List models
aictl model list

# Create a test agent
aictl agent create test-agent

# View agent status  
aictl agent list
aictl agent inspect test-agent
```

### Sample Output

```bash
$ aictl status

Language Operator Status
========================

CLI Version:     0.1.30
Cluster:         my-cluster (✓ connected)
Operator:        v0.1.30 (✓ installed)
Models:          2 configured
Agents:          1 running

✓ System ready
```

## Shell Completion (Optional)

Enable command completion for better CLI experience:

### Bash

```bash
echo 'eval "$(aictl completion bash)"' >> ~/.bashrc
source ~/.bashrc
```

### Zsh

```bash
echo 'eval "$(aictl completion zsh)"' >> ~/.zshrc
source ~/.zshrc
```

### Fish

```bash
aictl completion fish | source
```

## Troubleshooting

### Common Issues

**Command not found: aictl**
- Ensure Ruby gem bin directory is in PATH
- Run `gem env` to check installation paths

**Cannot connect to Kubernetes**
- Verify `kubectl` works: `kubectl get nodes`
- Check kubeconfig: `echo $KUBECONFIG`
- Ensure cluster context is correct

**Language Operator not found**
- Run `aictl install` to install to current cluster
- Check installation: `kubectl get pods -n language-operator`

**Model configuration issues**
- Verify API keys are set correctly
- Test model connectivity: `aictl model test my-model`

### Getting Help

- Check command help: `aictl --help`
- View logs: `aictl agent logs my-agent`
- Report issues: [GitHub Issues](https://github.com/language-operator/language-operator-gem/issues)

## Next Steps

- **[Quickstart Guide](quickstart.md)** - Create your first agent
- **[How Agents Work](how-agents-work.md)** - Understand the synthesis process
- **[CLI Reference](cli-reference.md)** - Complete command documentation