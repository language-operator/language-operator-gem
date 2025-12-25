# Persona-Driven System Prompts

Language Operator v0.1.71+ introduces **persona-driven system prompts** that transform agents from generic chatbots into context-aware entities with deep understanding of their identity, role, environment, and operational state.

## Overview

Traditional AI agents respond with generic outputs lacking awareness of their purpose or context. With persona-driven prompts, agents become intelligent entities that:

- **Know their identity**: Name, role, and specific purpose
- **Understand their environment**: Cluster, namespace, operational mode  
- **Track operational state**: Uptime, status, capabilities, tools available
- **Provide contextual responses**: References to their actual function and situation

## Quick Example

**Before (Generic Response):**
```
User: "hello" 
Agent: "Hello! How can I assist you today?"
```

**After (Identity-Aware Response):**
```
User: "hello"
Agent: "Hello! I'm say-something, running in the code-games cluster. 
       I've been active for 3 hours now, helping log interesting messages 
       and interactions. How can I assist you today?"
```

## Configuration

### Basic Usage

Enable identity awareness in your chat endpoint:

```ruby
agent "support-bot" do
  description "Customer support assistant"
  mode :reactive

  as_chat_endpoint do
    system_prompt "You are a helpful customer support assistant"
    
    # Enable persona-driven prompts
    identity_awareness do
      enabled true
      prompt_template :standard
      context_injection :standard
    end
  end
end
```

### Template Levels

Choose how much context to inject into system prompts:

#### `:minimal` - Basic Identity Only
```ruby
identity_awareness do
  enabled true
  prompt_template :minimal
end
```

**Generated prompt includes:**
- Agent name and cluster location
- Basic operational status

#### `:standard` - Balanced Context (Default)
```ruby
identity_awareness do
  enabled true
  prompt_template :standard  # Default
end
```

**Generated prompt includes:**
- Agent identity (name, role, mode)
- Basic operational context (uptime, cluster, status)
- Behavioral guidelines

#### `:detailed` - Full Context with Capabilities
```ruby
identity_awareness do
  enabled true
  prompt_template :detailed
end
```

**Generated prompt includes:**
- Complete identity and operational context
- Available tools and capabilities
- Workspace status and environment details
- Detailed behavioral guidelines

#### `:comprehensive` - Maximum Context
```ruby
identity_awareness do
  enabled true
  prompt_template :comprehensive
end
```

**Generated prompt includes:**
- All available metadata
- Environment specifications
- Complete capability listing
- Full behavioral framework

### Context Injection Levels

Control how much operational context appears in ongoing conversations:

```ruby
identity_awareness do
  enabled true
  context_injection :standard  # Options: :none, :minimal, :standard, :detailed
end
```

- **`:none`** - No conversation context injection
- **`:minimal`** - Basic status only
- **`:standard`** - Agent name, mode, uptime, status
- **`:detailed`** - Full operational metrics

## Implementation Details

### Architecture

The persona-driven prompt system consists of:

1. **MetadataCollector** - Gathers agent runtime and configuration data
2. **PromptBuilder** - Generates dynamic prompts from templates and metadata  
3. **ChatEndpointDefinition** - Enhanced with identity awareness configuration
4. **WebServer** - Integrates dynamic prompts into conversation handling

### Available Metadata

Agents can access the following runtime information:

```ruby
{
  identity: {
    name: "support-bot",
    description: "Customer support assistant", 
    persona: "helpful-assistant",
    mode: "reactive",
    version: "0.1.71"
  },
  runtime: {
    uptime: "3h 45m",
    started_at: "2024-01-15T10:30:00Z",
    workspace_available: true,
    mcp_servers_connected: 2
  },
  environment: {
    cluster: "production", 
    namespace: "support",
    kubernetes_enabled: true,
    telemetry_enabled: true
  },
  operational: {
    status: "ready",
    ready: true,
    mode: "reactive"
  },
  capabilities: {
    total_tools: 5,
    tools: [
      { server: "github-tools", tool_count: 3 },
      { server: "slack-tools", tool_count: 2 }
    ],
    llm_provider: "anthropic",
    llm_model: "claude-3-haiku"
  }
}
```

## Migration Guide

### Existing Agents

Persona-driven prompts are **backward compatible**. Existing agents continue working without changes.

To enable for existing agents:

```ruby
# Before
as_chat_endpoint do
  system_prompt "You are a GitHub expert"
  temperature 0.7
end

# After - Add identity awareness
as_chat_endpoint do
  system_prompt "You are a GitHub expert"
  
  identity_awareness do
    enabled true          # Enable the feature
    prompt_template :standard
    context_injection :standard  
  end
  
  temperature 0.7
end
```

### Gradual Adoption

1. **Start with `:minimal`** template to test basic identity awareness
2. **Upgrade to `:standard`** for balanced context
3. **Use `:detailed`** for rich conversational experiences
4. **Apply `:comprehensive`** only when maximum context is needed

### Disabling Features

```ruby
# Disable completely
identity_awareness do
  enabled false
end

# Disable conversation context only  
identity_awareness do
  enabled true
  prompt_template :standard
  context_injection :none
end
```

## Best Practices

### Template Selection

- **Customer-facing agents**: Use `:standard` or `:detailed`
- **Internal tools**: Use `:detailed` or `:comprehensive`  
- **Simple utilities**: Use `:minimal`
- **Legacy compatibility**: Use `enabled false`

### Performance Considerations

- Metadata collection is lightweight but cached
- Higher template levels increase token usage
- Context injection adds minimal overhead
- Templates are generated once per conversation

### Security

- No sensitive information (secrets, keys) included in prompts
- Environment details are cluster/namespace level only
- PII detection prevents accidental exposure

## Examples

### Complete Identity-Aware Agent

```ruby
LanguageOperator::Dsl.define do
  agent "customer-support" do
    description "24/7 customer support specialist for SaaS platform"
    mode :reactive

    as_chat_endpoint do
      system_prompt <<~PROMPT
        You are a knowledgeable customer support specialist with expertise in:
        - Account management and billing
        - Product features and troubleshooting  
        - Technical documentation and guides
        
        Provide helpful, accurate, and empathetic support to customers.
      PROMPT

      identity_awareness do
        enabled true
        prompt_template :detailed
        context_injection :standard
      end

      model "customer-support-v1"
      temperature 0.7
      max_tokens 2000
    end

    constraints do
      requests_per_minute 30
      daily_budget 1000
    end
  end
end
```

### Development vs Production Templates

```ruby
# Development - comprehensive context for debugging
identity_awareness do
  enabled true
  prompt_template :comprehensive
  context_injection :detailed
end

# Production - balanced context for performance
identity_awareness do
  enabled true  
  prompt_template :standard
  context_injection :standard
end
```

## Troubleshooting

### Common Issues

**Agent still gives generic responses:**
- Verify `enabled true` in identity_awareness block
- Check agent has proper name and description
- Ensure cluster environment variables are set

**Prompts too long/expensive:**
- Reduce template level (`:detailed` → `:standard` → `:minimal`)
- Disable context injection (`:none`)

**Missing environment context:**
- Verify Kubernetes environment variables
- Check cluster and namespace configuration
- Ensure agent has proper metadata access

### Debug Information

Enable debug logging to see generated prompts:

```bash
DEBUG=true ruby examples/identity_aware_chat_agent.rb
```

## API Reference

See the complete API documentation:
- [`ChatEndpointDefinition`](api/chat-endpoint-definition.md)
- [`MetadataCollector`](api/metadata-collector.md) 
- [`PromptBuilder`](api/prompt-builder.md)

---

**Next Steps:** Try the [identity-aware chat agent example](../examples/identity_aware_chat_agent.rb) to see persona-driven prompts in action.