# langop CLI Reference

Complete reference for the `langop` command-line interface.

## Global Commands

### `langop status`
Show system status and overview of the current cluster.

```bash
langop status
```

### `langop version`
Display langop version and operator installation status.

```bash
langop version
```

## Cluster Management

### `langop cluster`
Manage Kubernetes clusters for Language Operator.

```bash
# Create a new cluster configuration
langop cluster create my-cluster

# List configured clusters  
langop cluster list

# Switch active cluster context
langop use my-cluster

# Remove cluster configuration
langop cluster delete my-cluster
```

## Agent Management

### `langop agent`
Create, deploy, and manage agents.

```bash
# Create a new agent
langop agent create my-agent

# List agents in current cluster
langop agent list

# Get detailed agent information
langop agent inspect my-agent

# View agent logs
langop agent logs my-agent

# Delete an agent
langop agent delete my-agent

# Work with agent code
langop agent workspace my-agent
```

## Model Management

### `langop model`
Manage language models in the cluster.

```bash
# Create a new model resource
langop model create

# List available models
langop model list

# Test model connectivity
langop model test my-model
```

## Persona Management

### `langop persona`
Manage agent personas and system prompts.

```bash
# Create a new persona
langop persona create

# List available personas
langop persona list

# View persona details
langop persona inspect my-persona

# Delete a persona
langop persona delete my-persona
```

## Tool Management

### `langop tool`
Manage MCP tool servers.

```bash
# Deploy a tool server
langop tool deploy ./my-tool

# List tool deployments
langop tool list

# Test tool connectivity
langop tool test my-tool

# View tool logs
langop tool logs my-tool

# Search for tools
langop tool search database

# Install a tool from registry
langop tool install calculator
```

## System Utilities

### `langop system`
System-level operations and utilities.

```bash
# Validate system templates
langop system validate-template

# Work with synthesis templates
langop system synthesis-template

# Synthesize agent code
langop system synthesize

# Execute system commands
langop system exec
```

## Setup and Installation

### `langop quickstart`
Interactive wizard for first-time setup.

```bash
langop quickstart
```

### `langop install`
Install Language Operator to a Kubernetes cluster.

```bash
langop install
```

### `langop upgrade`
Upgrade Language Operator installation.

```bash
langop upgrade
```

### `langop uninstall`
Remove Language Operator from cluster.

```bash
langop uninstall
```

## Shell Completion

### `langop completion`
Install shell completion for langop.

```bash
# Bash completion
langop completion bash

# Zsh completion  
langop completion zsh

# Fish completion
langop completion fish
```

To install completion:

```bash
# Bash (add to ~/.bashrc)
eval "$(langop completion bash)"

# Zsh (add to ~/.zshrc)  
eval "$(langop completion zsh)"

# Fish
langop completion fish | source
```

## Common Workflows

### Creating Your First Agent

```bash
# 1. Set up cluster
langop quickstart

# 2. Create an agent
langop agent create my-agent

# 3. Check status
langop agent list
langop agent inspect my-agent

# 4. View logs
langop agent logs my-agent -f
```

### Working with Models

```bash
# 1. Create a model
langop model create

# 2. Test connectivity
langop model test my-model

# 3. List models
langop model list
```

### Tool Server Development

```bash
# 1. Deploy your tool
langop tool deploy ./my-custom-tools

# 2. Test tool functionality
langop tool test my-custom-tools

# 3. Monitor logs
langop tool logs my-custom-tools -f
```

## Environment Variables

langop respects these environment variables:

- `KUBECONFIG` - Path to Kubernetes config file
- `AICTL_CLUSTER` - Default cluster name
- `AICTL_LOG_LEVEL` - Log level (debug, info, warn, error)
- `NO_COLOR` - Disable colored output

## Exit Codes

- `0` - Success
- `1` - General error
- `2` - Configuration error
- `3` - Connection error
- `4` - Resource not found
- `5` - Permission denied

## Getting Help

All commands support the `--help` flag for detailed usage:

```bash
langop --help
langop agent --help
langop agent create --help
```