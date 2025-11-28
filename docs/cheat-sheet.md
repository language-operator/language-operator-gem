# aictl Cheat Sheet

Quick reference for the `aictl` command-line interface.

## General Commands

```bash
aictl --help                          # Show general help
aictl version                         # Display aictl and operator version information  
aictl status                          # Show system status and cluster overview
aictl quickstart                      # Launch interactive setup wizard for first-time users
aictl completion bash                 # Install bash shell completions
aictl completion zsh                  # Install zsh shell completions
aictl completion fish                 # Install fish shell completions
```

## Cluster Management

```bash
aictl cluster create <name>           # Create a new language cluster
aictl cluster list                    # List all configured clusters
aictl cluster current                 # Show current active cluster
aictl cluster inspect <name>          # Show detailed cluster information
aictl cluster delete <name>           # Delete a cluster
aictl use <cluster>                   # Switch to a different cluster
```

## Agent Management  

```bash
aictl agent create "<description>"    # Create agent from natural language description
aictl agent create --wizard           # Create agent using interactive wizard
aictl agent list                      # List all agents in current cluster
aictl agent inspect <name>            # Show detailed agent information
aictl agent delete <name>             # Delete an agent
aictl agent versions <name>           # Show ConfigMap versions for agent learning history
```

## Agent Operations

```bash
aictl agent logs <name>               # View agent execution logs
aictl agent logs <name> -f            # Follow agent logs in real-time  
aictl agent code <name>               # Show synthesized agent code
aictl agent workspace <name>          # Access agent's persistent workspace
aictl agent learning status <name>    # Show agent learning optimization status
aictl agent learning enable <name>    # Enable automatic learning for agent
aictl agent learning disable <name>   # Disable automatic learning for agent
```

## Model Management

```bash
aictl model create <name>             # Create model using interactive wizard
aictl model create <name> --provider openai --model gpt-4  # Create model with specific config
aictl model list                      # List all available models
aictl model inspect <name>            # Show detailed model information
aictl model delete <name>             # Delete a model
aictl model edit <name>               # Edit model configuration in YAML
aictl model test <name>               # Test model connectivity and basic functionality
```

## Tool Management

```bash
aictl tool install <name>             # Install a tool from registry
aictl tool search <query>             # Search available tools in registry
aictl tool list                       # List installed tools
aictl tool inspect <name>             # Show detailed tool information and MCP capabilities
aictl tool delete <name>              # Delete a tool
aictl tool test <name>                # Test tool health and connectivity
```

## Persona Management

```bash
aictl persona create <name>           # Create persona using interactive editor
aictl persona create <name> --from <existing>  # Create persona based on existing one
aictl persona list                    # List all available personas
aictl persona show <name>             # Display full persona details and system prompt
aictl persona edit <name>             # Edit persona definition in YAML editor
aictl persona delete <name>           # Delete a persona
```

## Installation & Deployment

```bash
aictl install                         # Install language-operator to cluster using Helm
aictl install --dry-run               # Preview installation without applying changes
aictl upgrade                         # Upgrade existing operator installation
aictl uninstall                       # Remove operator from cluster
```

## System Utilities

```bash
aictl system schema                   # Display current DSL JSON schema
aictl system validate-template <file> # Validate agent template file syntax
aictl system synthesize <template>    # Synthesize agent code from template
aictl system synthesis-template <name> # Show synthesis template used for agent
aictl system exec <agent> -- <cmd>    # Execute command inside agent pod
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
aictl quickstart                      # Interactive setup wizard
aictl install                         # Install operator to cluster
aictl cluster create production       # Create your first cluster

# Create and deploy an agent
aictl agent create "monitor my website and alert me if it goes down"
```

### Daily Operations
```bash
# Check system status
aictl status                          # Overview of cluster and resources
aictl agent list                      # See all running agents
aictl agent logs my-agent -f          # Monitor agent activity

# Manage resources
aictl model list                      # Available AI models
aictl tool install github             # Add new capabilities
aictl persona create helper --from technical-writer  # Customize agent personalities
```

### Development & Debugging
```bash
# Inspect resources  
aictl agent inspect my-agent          # Detailed agent status and configuration
aictl agent code my-agent             # View synthesized code
aictl agent workspace my-agent        # Access persistent data

# Troubleshooting
aictl model test gpt-4                # Verify model connectivity
aictl tool test github                # Check tool health
aictl system validate-template agent.yaml  # Validate configuration files
```

### Multi-Cluster Management
```bash
# Working with multiple environments
aictl cluster create staging
aictl cluster create production  
aictl use staging                      # Switch contexts
aictl agent list --all-clusters       # View agents across all clusters
```

## Quick Tips

- Use `--dry-run` to preview changes before applying them
- Add `--help` to any command for detailed usage information
- Agent descriptions in quotes support natural language
- Use `--wizard` flag for interactive guidance on complex operations
- Commands auto-complete with shell completions installed

---

For complete documentation, see: [Language Operator Documentation](../README.md)