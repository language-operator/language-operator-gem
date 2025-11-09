# Chat Endpoint Guide

Complete guide to exposing agents as OpenAI-compatible chat completion endpoints.

## Table of Contents

- [Overview](#overview)
- [Basic Configuration](#basic-configuration)
- [System Prompt](#system-prompt)
- [Model Parameters](#model-parameters)
- [API Endpoints](#api-endpoints)
- [Streaming Support](#streaming-support)
- [Authentication](#authentication)
- [Usage Examples](#usage-examples)
- [Integration with OpenAI SDK](#integration-with-openai-sdk)
- [Complete Examples](#complete-examples)
- [Best Practices](#best-practices)

## Overview

Language Operator agents can expose OpenAI-compatible chat completion endpoints, allowing them to be used as drop-in replacements for LLM APIs in existing applications.

### What is a Chat Endpoint?

A chat endpoint transforms an agent into an API-compatible language model that:
- Accepts OpenAI-format chat completion requests
- Supports both streaming and non-streaming responses
- Provides model listing via `/v1/models`
- Returns usage statistics (token counts)
- Works with existing OpenAI SDKs and tools

### Use Cases

- **Domain-specific models**: Create specialized "models" for specific tasks
- **Agent as a service**: Expose agents to other applications
- **LLM proxy**: Add custom logic, caching, or rate limiting
- **Testing**: Use agents as mock LLM endpoints
- **Integration**: Connect agents to LangChain, AutoGPT, etc.

## Basic Configuration

Define a chat endpoint using the `as_chat_endpoint` block:

```ruby
agent "github-expert" do
  description "GitHub API and workflow expert"
  mode :reactive

  as_chat_endpoint do
    system_prompt "You are a GitHub expert assistant"
    temperature 0.7
    max_tokens 2000
  end
end
```

**Key points:**
- Agent automatically switches to `:reactive` mode
- Endpoints are automatically created at `/v1/chat/completions` and `/v1/models`
- Agent processes chat messages and returns completions
- Works with existing OpenAI client libraries

## System Prompt

The system prompt defines the agent's behavior and expertise. It's prepended to every conversation.

### Basic System Prompt

```ruby
as_chat_endpoint do
  system_prompt "You are a helpful customer service assistant"
end
```

### Detailed System Prompt

Use heredoc for multi-line prompts:

```ruby
as_chat_endpoint do
  system_prompt <<~PROMPT
    You are a GitHub expert assistant with deep knowledge of:
    - GitHub API and workflows
    - Pull requests, issues, and code review
    - GitHub Actions and CI/CD
    - Repository management and best practices

    Provide helpful, accurate answers about GitHub topics.
    Keep responses concise but informative.
  PROMPT
end
```

### System Prompt Best Practices

**Be specific about expertise:**
```ruby
system_prompt <<~PROMPT
  You are a Kubernetes troubleshooting expert specializing in:
  - Pod scheduling and resource issues
  - Network policy debugging
  - Storage and volume problems
  - Performance optimization
PROMPT
```

**Include behavioral guidelines:**
```ruby
system_prompt <<~PROMPT
  You are a financial analyst assistant.

  Guidelines:
  - Base all analysis on factual data
  - Clearly distinguish facts from interpretations
  - Use industry-standard terminology
  - Never provide investment advice
  - Always cite sources when referencing data
PROMPT
```

**Set tone and style:**
```ruby
system_prompt <<~PROMPT
  You are a friendly technical support agent.

  Communication style:
  - Use clear, simple language
  - Be patient and encouraging
  - Provide step-by-step instructions
  - Offer to clarify if anything is unclear
PROMPT
```

## Model Parameters

Configure LLM behavior with standard OpenAI parameters.

### Temperature

Controls randomness in responses (0.0 - 2.0):

```ruby
as_chat_endpoint do
  temperature 0.7  # Balanced creativity and consistency
end
```

**Guidelines:**
- `0.0` - Deterministic, focused responses (good for factual tasks)
- `0.5-0.7` - Balanced (default for most use cases)
- `1.0+` - More creative and varied (good for brainstorming)

### Max Tokens

Maximum tokens in the response:

```ruby
as_chat_endpoint do
  max_tokens 2000  # Limit response length
end
```

**Guidelines:**
- Set based on expected response length
- Consider cost implications
- Default: 2000 tokens

### Top P (Nucleus Sampling)

Alternative to temperature for controlling randomness (0.0 - 1.0):

```ruby
as_chat_endpoint do
  top_p 0.9  # Consider top 90% probability mass
end
```

**Note:** Use either `temperature` or `top_p`, not both.

### Frequency Penalty

Reduces repetition of token sequences (-2.0 to 2.0):

```ruby
as_chat_endpoint do
  frequency_penalty 0.5  # Discourage repetition
end
```

**Guidelines:**
- `0.0` - No penalty (default)
- `0.5-1.0` - Moderate reduction in repetition
- Higher values: Stronger penalty against repetition

### Presence Penalty

Encourages talking about new topics (-2.0 to 2.0):

```ruby
as_chat_endpoint do
  presence_penalty 0.6  # Encourage topic diversity
end
```

### Stop Sequences

Tokens that stop generation:

```ruby
as_chat_endpoint do
  stop ["\n\n", "END", "###"]  # Stop on these sequences
end
```

### Model Name

Custom model identifier returned in API responses:

```ruby
as_chat_endpoint do
  model "github-expert-v1"  # Custom model name
end
```

**Default:** Agent name (e.g., `"github-expert"`)

### Complete Parameter Configuration

```ruby
as_chat_endpoint do
  system_prompt "You are a helpful assistant"

  # Model identification
  model "my-custom-model-v1"

  # Sampling parameters
  temperature 0.7
  top_p 0.9

  # Length controls
  max_tokens 2000
  stop ["\n\n\n"]

  # Repetition controls
  frequency_penalty 0.5
  presence_penalty 0.6
end
```

## API Endpoints

Chat endpoints expose OpenAI-compatible HTTP endpoints.

### POST /v1/chat/completions

Chat completion endpoint (streaming and non-streaming).

**Request format:**
```json
{
  "model": "github-expert-v1",
  "messages": [
    {"role": "user", "content": "How do I create a pull request?"}
  ],
  "stream": false
}
```

**Response format (non-streaming):**
```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "github-expert-v1",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "To create a pull request on GitHub..."
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 15,
    "completion_tokens": 45,
    "total_tokens": 60
  }
}
```

### GET /v1/models

List available models.

**Request:**
```bash
GET /v1/models
```

**Response:**
```json
{
  "object": "list",
  "data": [
    {
      "id": "github-expert-v1",
      "object": "model",
      "created": 1677652288,
      "owned_by": "language-operator"
    }
  ]
}
```

### Health Check Endpoints

**GET /health** - Health check
```bash
curl http://localhost:8080/health
# Returns: {"status":"healthy"}
```

**GET /ready** - Readiness check
```bash
curl http://localhost:8080/ready
# Returns: {"status":"ready"}
```

## Streaming Support

Chat endpoints support Server-Sent Events (SSE) for streaming responses.

### Enabling Streaming

Set `stream: true` in the request:

```bash
curl -N -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "github-expert-v1",
    "messages": [{"role": "user", "content": "Explain GitHub Actions"}],
    "stream": true
  }'
```

### Streaming Response Format

Responses are sent as SSE events:

```
data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1677652288,"model":"github-expert-v1","choices":[{"index":0,"delta":{"content":"To"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1677652288,"model":"github-expert-v1","choices":[{"index":0,"delta":{"content":" create"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1677652288,"model":"github-expert-v1","choices":[{"index":0,"delta":{"content":" a"},"finish_reason":null}]}

...

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1677652288,"model":"github-expert-v1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

**Key points:**
- Each chunk contains a delta with new content
- Final chunk includes `finish_reason: "stop"`
- Stream ends with `data: [DONE]`

### Streaming vs Non-Streaming

**Non-streaming (default):**
- Complete response returned at once
- Simpler to consume
- Higher perceived latency
- Better for batch processing

**Streaming (`stream: true`):**
- Response sent incrementally
- Lower perceived latency
- Better user experience
- More complex to consume

## Authentication

While the chat endpoint examples above don't show authentication, you can combine chat endpoints with webhooks for authentication:

```ruby
agent "secure-chat-agent" do
  mode :reactive

  # Chat endpoint
  as_chat_endpoint do
    system_prompt "You are a helpful assistant"
    temperature 0.7
  end

  # Webhook for custom routes (can add auth)
  webhook "/authenticated" do
    method :post

    authenticate do
      verify_api_key(
        header: 'X-API-Key',
        secret: ENV['API_KEY']
      )
    end

    on_request do |context|
      # Custom authenticated logic
    end
  end
end
```

**Note:** Standard OpenAI SDK clients expect the `/v1/chat/completions` endpoint. For production deployments, add authentication at the infrastructure level (API gateway, ingress controller, etc.).

## Usage Examples

### Using curl (Non-streaming)

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "github-expert-v1",
    "messages": [
      {"role": "user", "content": "How do I create a pull request?"}
    ]
  }'
```

### Using curl (Streaming)

```bash
curl -N -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "github-expert-v1",
    "messages": [
      {"role": "user", "content": "Explain GitHub Actions"}
    ],
    "stream": true
  }'
```

### Multi-turn Conversation

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "github-expert-v1",
    "messages": [
      {"role": "user", "content": "What is a pull request?"},
      {"role": "assistant", "content": "A pull request is a way to propose changes..."},
      {"role": "user", "content": "How do I review one?"}
    ]
  }'
```

### With System Message

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "github-expert-v1",
    "messages": [
      {"role": "system", "content": "You are an expert in GitHub Actions."},
      {"role": "user", "content": "How do I set up CI/CD?"}
    ]
  }'
```

## Integration with OpenAI SDK

Chat endpoints are compatible with OpenAI client libraries.

### Python

```python
from openai import OpenAI

# Point client to your agent
client = OpenAI(
    api_key="not-needed",  # Not used, but required by SDK
    base_url="http://localhost:8080/v1"
)

# Non-streaming
response = client.chat.completions.create(
    model="github-expert-v1",
    messages=[
        {"role": "user", "content": "How do I create a PR?"}
    ]
)
print(response.choices[0].message.content)

# Streaming
stream = client.chat.completions.create(
    model="github-expert-v1",
    messages=[
        {"role": "user", "content": "Explain GitHub Actions"}
    ],
    stream=True
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="")
```

### JavaScript/TypeScript

```javascript
import OpenAI from 'openai';

const client = new OpenAI({
  apiKey: 'not-needed',
  baseURL: 'http://localhost:8080/v1',
});

// Non-streaming
const response = await client.chat.completions.create({
  model: 'github-expert-v1',
  messages: [
    { role: 'user', content: 'How do I create a PR?' }
  ],
});
console.log(response.choices[0].message.content);

// Streaming
const stream = await client.chat.completions.create({
  model: 'github-expert-v1',
  messages: [
    { role: 'user', content: 'Explain GitHub Actions' }
  ],
  stream: true,
});

for await (const chunk of stream) {
  if (chunk.choices[0]?.delta?.content) {
    process.stdout.write(chunk.choices[0].delta.content);
  }
}
```

### Ruby

```ruby
require 'openai'

client = OpenAI::Client.new(
  access_token: "not-needed",
  uri_base: "http://localhost:8080/v1/"
)

# Non-streaming
response = client.chat(
  parameters: {
    model: "github-expert-v1",
    messages: [
      { role: "user", content: "How do I create a PR?" }
    ]
  }
)
puts response.dig("choices", 0, "message", "content")

# Streaming
client.chat(
  parameters: {
    model: "github-expert-v1",
    messages: [
      { role: "user", content: "Explain GitHub Actions" }
    ],
    stream: proc do |chunk, _bytesize|
      print chunk.dig("choices", 0, "delta", "content")
    end
  }
)
```

### LangChain Integration

```python
from langchain_openai import ChatOpenAI

# Use agent as LangChain LLM
llm = ChatOpenAI(
    model="github-expert-v1",
    openai_api_key="not-needed",
    openai_api_base="http://localhost:8080/v1"
)

# Use in LangChain chains
from langchain.chains import LLMChain
from langchain.prompts import PromptTemplate

prompt = PromptTemplate(
    input_variables=["topic"],
    template="Explain {topic} in GitHub"
)

chain = LLMChain(llm=llm, prompt=prompt)
result = chain.run(topic="pull requests")
print(result)
```

## Complete Examples

### GitHub Expert Agent

```ruby
agent "github-expert" do
  description "GitHub API and workflow expert"
  mode :reactive

  as_chat_endpoint do
    system_prompt <<~PROMPT
      You are a GitHub expert assistant with deep knowledge of:
      - GitHub API and workflows
      - Pull requests, issues, and code review
      - GitHub Actions and CI/CD
      - Repository management and best practices

      Provide helpful, accurate answers about GitHub topics.
      Keep responses concise but informative.
    PROMPT

    model "github-expert-v1"
    temperature 0.7
    max_tokens 2000
  end

  constraints do
    timeout '30s'
    requests_per_minute 30
    daily_budget 1000  # $10/day
  end
end
```

### Customer Support Agent

```ruby
agent "customer-support" do
  description "Friendly customer support assistant"
  mode :reactive

  as_chat_endpoint do
    system_prompt <<~PROMPT
      You are a friendly customer support representative.

      Guidelines:
      - Be empathetic and understanding
      - Provide clear, step-by-step solutions
      - Ask clarifying questions when needed
      - Escalate to human support for complex issues
      - Always maintain a professional, helpful tone

      Available topics:
      - Account management
      - Billing and payments
      - Technical troubleshooting
      - Product features and usage
    PROMPT

    model "support-assistant-v1"
    temperature 0.8  # Slightly more conversational
    max_tokens 1500
    presence_penalty 0.6  # Encourage topic variety
  end

  constraints do
    timeout '15s'  # Quick responses for support
    requests_per_minute 60
    hourly_budget 500
    daily_budget 5000

    # Safety
    blocked_topics ['violence', 'hate-speech']
  end
end
```

### Technical Documentation Assistant

```ruby
agent "docs-assistant" do
  description "Technical documentation expert"
  mode :reactive

  as_chat_endpoint do
    system_prompt <<~PROMPT
      You are a technical documentation assistant specializing in API documentation.

      Your expertise:
      - REST API design and documentation
      - OpenAPI/Swagger specifications
      - Authentication and authorization patterns
      - Rate limiting and pagination
      - Error handling best practices

      When answering:
      - Provide code examples when relevant
      - Explain concepts clearly with examples
      - Reference industry standards (REST, OpenAPI, etc.)
      - Include best practices and gotchas
      - Format responses with proper markdown
    PROMPT

    model "docs-expert-v1"
    temperature 0.5  # More consistent/factual
    max_tokens 3000  # Longer for detailed explanations
    frequency_penalty 0.3  # Reduce repetition in docs
  end

  constraints do
    timeout '45s'
    requests_per_minute 20
    daily_budget 2000
  end
end
```

### Code Review Assistant

```ruby
agent "code-reviewer" do
  description "Automated code review assistant"
  mode :reactive

  as_chat_endpoint do
    system_prompt <<~PROMPT
      You are a senior software engineer conducting code reviews.

      Focus areas:
      - Code correctness and logic errors
      - Security vulnerabilities
      - Performance issues
      - Code style and best practices
      - Test coverage
      - Documentation quality

      Review approach:
      - Be constructive and specific
      - Explain the "why" behind suggestions
      - Prioritize issues by severity
      - Suggest concrete improvements
      - Acknowledge good practices

      Format reviews with:
      - Summary of overall code quality
      - Specific issues with line references
      - Suggested improvements
      - Security concerns (if any)
    PROMPT

    model "code-reviewer-v1"
    temperature 0.3  # Consistent, focused reviews
    max_tokens 4000  # Detailed reviews
    frequency_penalty 0.5  # Avoid repetitive comments
  end

  constraints do
    timeout '1m'  # Allow time for thorough review
    requests_per_hour 50
    daily_budget 3000
  end
end
```

### SQL Query Helper

```ruby
agent "sql-helper" do
  description "SQL query assistance and optimization"
  mode :reactive

  as_chat_endpoint do
    system_prompt <<~PROMPT
      You are a database expert specializing in SQL query writing and optimization.

      Expertise:
      - SQL syntax (PostgreSQL, MySQL, SQLite)
      - Query optimization and performance
      - Index design
      - Join strategies
      - Aggregation and window functions
      - Common table expressions (CTEs)

      When helping:
      - Write clean, readable SQL
      - Explain query logic
      - Suggest optimizations
      - Warn about performance pitfalls
      - Include comments in complex queries
      - Consider different SQL dialects
    PROMPT

    model "sql-expert-v1"
    temperature 0.4  # Precise for SQL
    max_tokens 2500
    stop ["```\n\n"]  # Stop after code block
  end

  constraints do
    timeout '30s'
    requests_per_minute 40
    daily_budget 1500
  end
end
```

## Best Practices

### System Prompt Design

1. **Be specific about expertise** - Define clear areas of knowledge
2. **Include guidelines** - Specify how the agent should respond
3. **Set boundaries** - Define what the agent should/shouldn't do
4. **Provide context** - Explain the agent's role and purpose
5. **Use examples** - Show expected behavior in the prompt

### Parameter Tuning

1. **Temperature**
   - Lower (0.0-0.3) for factual, consistent responses
   - Medium (0.5-0.7) for balanced interactions
   - Higher (0.8-1.0) for creative, varied responses

2. **Max Tokens**
   - Set based on expected response length
   - Consider cost implications
   - Balance between completeness and efficiency

3. **Penalties**
   - Use `frequency_penalty` to reduce repetition
   - Use `presence_penalty` to encourage topic diversity
   - Start low (0.0-0.5) and adjust based on behavior

### Performance

1. **Set appropriate timeouts** - Balance thoroughness and responsiveness
2. **Use streaming for long responses** - Better user experience
3. **Cache responses** - When appropriate for repeated queries
4. **Monitor token usage** - Track costs and optimize prompts

### Cost Management

1. **Set budget constraints** - Use `daily_budget` and `hourly_budget`
2. **Limit max_tokens** - Prevent unexpectedly long responses
3. **Monitor usage** - Track requests and token consumption
4. **Optimize prompts** - Shorter system prompts reduce costs

```ruby
constraints do
  hourly_budget 100   # $1/hour
  daily_budget 1000   # $10/day
  requests_per_minute 30
end
```

### Security

1. **Don't expose credentials** - Never include API keys in prompts
2. **Validate inputs** - Sanitize user messages
3. **Filter outputs** - Use `blocked_patterns` for PII
4. **Add authentication** - Use API gateway or webhook auth
5. **Rate limit** - Prevent abuse with `requests_per_minute`

### Testing

1. **Test with OpenAI SDK** - Verify compatibility
2. **Test streaming** - Ensure SSE works correctly
3. **Test error cases** - Handle malformed requests
4. **Test conversation history** - Multi-turn interactions
5. **Load test** - Verify performance under load

### Monitoring

1. **Track usage metrics** - Requests, tokens, costs
2. **Monitor latency** - Response time distribution
3. **Log errors** - Capture and analyze failures
4. **Monitor quality** - Track user feedback
5. **Alert on anomalies** - Unusual usage patterns

## See Also

- [Agent Reference](agent-reference.md) - Complete agent DSL reference
- [MCP Integration](mcp-integration.md) - Tool server capabilities
- [Webhooks](webhooks.md) - Reactive agent configuration
- [Best Practices](best-practices.md) - Production deployment patterns
