# aictl CLI Reference

Complete reference for the `aictl` command-line interface.

## Global Commands

### `aictl status`
Show system status and overview of the current cluster.

```bash
aictl status
```

### `aictl version`
Display aictl version and operator installation status.

```bash
aictl version
```

## Cluster Management

### `aictl cluster`
Manage Kubernetes clusters for Language Operator.

```bash
# Create a new cluster configuration
aictl cluster create my-cluster

# List configured clusters  
aictl cluster list

# Switch active cluster context
aictl use my-cluster

# Remove cluster configuration
aictl cluster delete my-cluster
```

## Agent Management

### `aictl agent`
Create, deploy, and manage agents.

```bash
# Create a new agent
aictl agent create my-agent

# List agents in current cluster
aictl agent list

# Get detailed agent information
aictl agent inspect my-agent

# View agent logs
aictl agent logs my-agent

# Delete an agent
aictl agent delete my-agent

# Optimize agent performance
aictl agent optimize my-agent

# Work with agent code
aictl agent workspace my-agent

# Rollback agent to previous version
aictl agent rollback my-agent
```

## Model Management

### `aictl model`
Manage language models in the cluster.

```bash
# Create a new model resource
aictl model create

# List available models
aictl model list

# Test model connectivity
aictl model test my-model
```

## Persona Management

### `aictl persona`
Manage agent personas and system prompts.

```bash
# Create a new persona
aictl persona create

# List available personas
aictl persona list

# View persona details
aictl persona inspect my-persona

# Delete a persona
aictl persona delete my-persona
```

## Tool Management

### `aictl tool`
Manage MCP tool servers.

```bash
# Deploy a tool server
aictl tool deploy ./my-tool

# List tool deployments
aictl tool list

# Test tool connectivity
aictl tool test my-tool

# View tool logs
aictl tool logs my-tool

# Search for tools
aictl tool search database

# Install a tool from registry
aictl tool install calculator
```

## System Utilities

### `aictl system`
System-level operations and utilities.

```bash
# Validate system templates
aictl system validate-template

# Work with synthesis templates
aictl system synthesis-template

# Synthesize agent code
aictl system synthesize

# Execute system commands
aictl system exec
```

## Setup and Installation

### `aictl quickstart`
Interactive wizard for first-time setup.

```bash
aictl quickstart
```

### `aictl install`
Install Language Operator to a Kubernetes cluster.

```bash
aictl install
```

### `aictl upgrade`
Upgrade Language Operator installation.

```bash
aictl upgrade
```

### `aictl uninstall`
Remove Language Operator from cluster.

```bash
aictl uninstall
```

## Shell Completion

### `aictl completion`
Install shell completion for aictl.

```bash
# Bash completion
aictl completion bash

# Zsh completion  
aictl completion zsh

# Fish completion
aictl completion fish
```

To install completion:

```bash
# Bash (add to ~/.bashrc)
eval "$(aictl completion bash)"

# Zsh (add to ~/.zshrc)  
eval "$(aictl completion zsh)"

# Fish
aictl completion fish | source
```

## Common Workflows

### Creating Your First Agent

```bash
# 1. Set up cluster
aictl quickstart

# 2. Create an agent
aictl agent create my-agent

# 3. Check status
aictl agent list
aictl agent inspect my-agent

# 4. View logs
aictl agent logs my-agent -f
```

### Working with Models

```bash
# 1. Create a model
aictl model create

# 2. Test connectivity
aictl model test my-model

# 3. List models
aictl model list
```

### Tool Server Development

```bash
# 1. Deploy your tool
aictl tool deploy ./my-custom-tools

# 2. Test tool functionality
aictl tool test my-custom-tools

# 3. Monitor logs
aictl tool logs my-custom-tools -f
```

## Environment Variables

aictl respects these environment variables:

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
aictl --help
aictl agent --help
aictl agent create --help
```