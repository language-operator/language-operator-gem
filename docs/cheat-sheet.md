# langop Cheat Sheet

Quick reference for the `langop` command-line interface.

## General Commands

```bash
langop --help                          # Show general help
langop version                         # Display langop and operator version information  
langop status                          # Show system status and cluster overview
langop quickstart                      # Launch interactive setup wizard for first-time users
langop completion bash                 # Install bash shell completions
langop completion zsh                  # Install zsh shell completions
langop completion fish                 # Install fish shell completions
```

## Cluster Management

```bash
langop cluster create <name>           # Create a new language cluster
langop cluster list                    # List all configured clusters
langop cluster current                 # Show current active cluster
langop cluster inspect <name>          # Show detailed cluster information
langop cluster delete <name>           # Delete a cluster
langop use <cluster>                   # Switch to a different cluster
```

## Agent Management  

```bash
langop agent create "<description>"    # Create agent from natural language description
langop agent create --wizard           # Create agent using interactive wizard
langop agent list                      # List all agents in current cluster
langop agent inspect <name>            # Show detailed agent information
langop agent delete <name>             # Delete an agent
langop agent versions <name>           # Show ConfigMap versions for agent learning history
```

## Agent Operations

```bash
langop agent logs <name>               # View agent execution logs
langop agent logs <name> -f            # Follow agent logs in real-time  
langop agent code <name>               # Show synthesized agent code
langop agent workspace <name>          # Access agent's persistent workspace
langop agent learning status <name>    # Show agent learning optimization status
langop agent learning enable <name>    # Enable automatic learning for agent
langop agent learning disable <name>   # Disable automatic learning for agent
```

## Model Management

```bash
langop model create <name>             # Create model using interactive wizard
langop model create <name> --provider openai --model gpt-4  # Create model with specific config
langop model list                      # List all available models
langop model inspect <name>            # Show detailed model information
langop model delete <name>             # Delete a model
langop model edit <name>               # Edit model configuration in YAML
langop model test <name>               # Test model connectivity and basic functionality
```

## Tool Management

```bash
langop tool install <name>             # Install a tool from registry
langop tool search <query>             # Search available tools in registry
langop tool list                       # List installed tools
langop tool inspect <name>             # Show detailed tool information and MCP capabilities
langop tool delete <name>              # Delete a tool
langop tool test <name>                # Test tool health and connectivity
```

## Persona Management

```bash
langop persona create <name>           # Create persona using interactive editor
langop persona create <name> --from <existing>  # Create persona based on existing one
langop persona list                    # List all available personas
langop persona show <name>             # Display full persona details and system prompt
langop persona edit <name>             # Edit persona definition in YAML editor
langop persona delete <name>           # Delete a persona
```

## Installation & Deployment

```bash
langop install                         # Install language-operator to cluster using Helm
langop install --dry-run               # Preview installation without applying changes
langop upgrade                         # Upgrade existing operator installation
langop uninstall                       # Remove operator from cluster
```

## System Utilities

```bash
langop system schema                   # Display current DSL JSON schema
langop system validate-template <file> # Validate agent template file syntax
langop system synthesize <template>    # Synthesize agent code from template
langop system synthesis-template <name> # Show synthesis template used for agent
langop system exec <agent> -- <cmd>    # Execute command inside agent pod
```

## Common Options

All commands support these common options:

```bash
--cluster <name>                      # Override current cluster context
--dry-run                             # Preview changes without applying
--force                               # Skip confirmation prompts
--help                                # Show command-specific help
```

## Examples

### Quick Start
```bash
# First-time setup
langop quickstart                      # Interactive setup wizard
langop install                         # Install operator to cluster
langop cluster create production       # Create your first cluster

# Create and deploy an agent
langop agent create "monitor my website and alert me if it goes down"
```

### Daily Operations
```bash
# Check system status
langop status                          # Overview of cluster and resources
langop agent list                      # See all running agents
langop agent logs my-agent -f          # Monitor agent activity

# Manage resources
langop model list                      # Available AI models
langop tool install github             # Add new capabilities
langop persona create helper --from technical-writer  # Customize agent personalities
```

### Development & Debugging
```bash
# Inspect resources  
langop agent inspect my-agent          # Detailed agent status and configuration
langop agent code my-agent             # View synthesized code
langop agent workspace my-agent        # Access persistent data

# Troubleshooting
langop model test gpt-4                # Verify model connectivity
langop tool test github                # Check tool health
langop system validate-template agent.yaml  # Validate configuration files
```

### Multi-Cluster Management
```bash
# Working with multiple environments
langop cluster create staging
langop cluster create production  
langop use staging                      # Switch contexts
langop agent list --all-clusters       # View agents across all clusters
```

## Quick Tips

- Use `--dry-run` to preview changes before applying them
- Add `--help` to any command for detailed usage information
- Agent descriptions in quotes support natural language
- Use `--wizard` flag for interactive guidance on complex operations
- Commands auto-complete with shell completions installed

---

For complete documentation, see: [Language Operator Documentation](../README.md)