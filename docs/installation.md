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
langop version
```

You should see the langop version and operator status information.

## Initial Setup

### 1. Check System Status

```bash
langop status
```

This command shows:
- CLI version
- Kubernetes connectivity
- Language Operator installation status

### 2. Run Quickstart Wizard

For first-time users, the quickstart wizard guides you through setup:

```bash
langop quickstart
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
langop cluster create my-cluster

# Switch to the cluster
langop use my-cluster

# Install Language Operator
langop install

# Verify installation
langop status
```

## Kubernetes Setup

### Local Development (minikube/kind)

```bash
# Start minikube
minikube start

# Or start kind cluster
kind create cluster --name language-operator

# Configure langop
langop cluster create local --kubeconfig ~/.kube/config
langop use local
```

### Production Clusters

```bash
# Configure cluster with specific context
langop cluster create production \
  --kubeconfig /path/to/kubeconfig \
  --context production-context

langop use production
```

## Model Configuration

Language Operator requires language model access. Configure your preferred provider:

### OpenAI

```bash
export OPENAI_API_KEY="sk-your-api-key"
langop model create openai-gpt4 --provider openai --model gpt-4-turbo
```

### Anthropic (Claude)

```bash
export ANTHROPIC_API_KEY="sk-your-api-key"  
langop model create claude-sonnet --provider anthropic --model claude-3-sonnet
```

### Local Models (Ollama)

```bash
# Start Ollama locally
ollama serve

# Configure local model
langop model create local-llama --provider ollama --model llama3
```

## Verification

### Test Your Setup

```bash
# Check overall status
langop status

# List models
langop model list

# Create a test agent
langop agent create test-agent

# View agent status  
langop agent list
langop agent inspect test-agent
```

### Sample Output

```bash
$ langop status

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
echo 'eval "$(langop completion bash)"' >> ~/.bashrc
source ~/.bashrc
```

### Zsh

```bash
echo 'eval "$(langop completion zsh)"' >> ~/.zshrc
source ~/.zshrc
```

### Fish

```bash
langop completion fish | source
```

## Troubleshooting

### Common Issues

**Command not found: langop**
- Ensure Ruby gem bin directory is in PATH
- Run `gem env` to check installation paths

**Cannot connect to Kubernetes**
- Verify `kubectl` works: `kubectl get nodes`
- Check kubeconfig: `echo $KUBECONFIG`
- Ensure cluster context is correct

**Language Operator not found**
- Run `langop install` to install to current cluster
- Check installation: `kubectl get pods -n language-operator`

**Model configuration issues**
- Verify API keys are set correctly
- Test model connectivity: `langop model test my-model`

### Getting Help

- Check command help: `langop --help`
- View logs: `langop agent logs my-agent`
- Report issues: [GitHub Issues](https://github.com/language-operator/language-operator-gem/issues)

## Next Steps

- **[Quickstart Guide](quickstart.md)** - Create your first agent
- **[How Agents Work](how-agents-work.md)** - Understand the synthesis process
- **[CLI Reference](cli-reference.md)** - Complete command documentation