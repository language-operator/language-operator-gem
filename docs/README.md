# Language Operator Documentation

Complete guide to using Language Operator to build, deploy, and manage AI agents using natural language synthesis.

## Quick Start

```bash
# Install the CLI
gem install language-operator

# Interactive setup (recommended)
langop quickstart
```

**New to Language Operator?** Start with the [Installation Guide](installation.md) and [Quickstart Guide](quickstart.md).

## Table of Contents

### Getting Started
- **[Installation](installation.md)** - Install langop and configure your environment  
- **[Quickstart Guide](quickstart.md)** - Create your first agent in 5 minutes
- **[CLI Reference](cli-reference.md)** - Complete command documentation

### Core Concepts
- **[How Agents Work](how-agents-work.md)** - Understanding the synthesis process from description to working code
- **[Understanding Generated Code](understanding-generated-code.md)** - Reading and working with synthesized agent definitions
- **[Agent Optimization](agent-optimization.md)** - How agents learn patterns and improve performance over time

### Agent Capabilities  
- **[Using Tools](using-tools.md)** - How agents interact with external services through MCP
- **[Webhooks](webhooks.md)** - Creating reactive agents that respond to GitHub, Stripe, and custom events
- **[Chat Endpoints](chat-endpoints.md)** - Building conversational AI interfaces with OpenAI-compatible APIs

### Configuration & Management
- **[Constraints](constraints.md)** - Timeouts, budgets, rate limits, and resource constraints
- **[Best Practices](best-practices.md)** - Production patterns for reliable, cost-effective agents
- **[Schema Versioning](schema-versioning.md)** - Managing agent definition compatibility

### Advanced Topics
- **[Agent Internals](agent-internals.md)** - Deep dive into synthesis, optimization, and execution engine

## Available Commands

```bash
langop status              # Show system status
langop cluster            # Manage Kubernetes clusters
langop agent              # Create and manage agents  
langop model              # Manage language models
langop persona            # Manage agent personas
langop tool               # Manage MCP tool servers
langop system             # System utilities and templates
langop quickstart         # First-time setup wizard
```

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/language-operator/language-operator-gem/issues)
- **Discussions**: [GitHub Discussions](https://github.com/language-operator/language-operator/discussions)