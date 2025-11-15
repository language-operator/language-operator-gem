# Ux::Concerns

Reusable mixins for interactive UX flows.

## Available Concerns

### Headings

Provides consistent formatting for headings, step indicators, and banners.

```ruby
class MyFlow < Ux::Base
  include Concerns::Headings

  def execute
    heading('Welcome!', emoji: '🎉')
    step_heading(1, 3, 'First Step')
    subheading('Configuration')
    separator
  end
end
```

**Methods:**
- `heading(text, emoji: nil, width: 50)` - Display prominent heading with border
- `step_heading(current, total, title, width: 50)` - Display step indicator
- `subheading(text)` - Display simple subheading
- `separator(width: 50, char: '─')` - Display separator line
- `section(title, description: nil)` - Display section header with description

### ProviderHelpers

Common operations for LLM provider integration.

```ruby
class MyFlow < Ux::Base
  include Concerns::ProviderHelpers

  def execute
    result = test_provider_connection(:anthropic, api_key: 'sk-...')
    models = fetch_provider_models(:openai, api_key: 'sk-...')
    info = provider_info(:anthropic)
  end
end
```

**Methods:**
- `test_provider_connection(provider, api_key:, endpoint:)` - Test connection to provider
- `fetch_provider_models(provider, api_key:, endpoint:)` - Fetch available models
- `provider_info(provider)` - Get provider display info and documentation URLs

**Supported Providers:**
- `:anthropic` - Anthropic (Claude)
- `:openai` - OpenAI (GPT)
- `:openai_compatible` - OpenAI-compatible endpoints (Ollama, vLLM, LM Studio, etc)

### InputValidation

Common input validation and prompting helpers.

```ruby
class MyFlow < Ux::Base
  include Concerns::InputValidation

  def execute
    url = ask_url('Enter endpoint URL:')
    name = ask_k8s_name('Resource name:', default: 'my-resource')
    email = ask_email('Your email:')
    api_key = ask_secret('API key:')
    port = ask_port('Port:', default: 8080)
    confirmed = ask_yes_no('Continue?', default: true)
  end
end
```

**Methods:**
- `ask_url(question, default:, required:)` - Prompt for URL with validation
- `ask_k8s_name(question, default:)` - Prompt for Kubernetes resource name
- `ask_email(question, default:)` - Prompt for email address
- `ask_secret(question, required:)` - Prompt for masked input (API keys, passwords)
- `ask_port(question, default:)` - Prompt for port number (1-65535)
- `ask_yes_no(question, default:)` - Prompt for yes/no confirmation
- `ask_select(question, choices, per_page:)` - Prompt for selection from list
- `validate_k8s_name(name)` - Validate and normalize Kubernetes name
- `validate_url(url)` - Validate URL format

## Usage Guidelines

### When to Use Concerns

✅ **DO use concerns for:**
- Common formatting patterns used across multiple flows
- Repeated validation logic
- Shared provider/API operations
- Reusable UI components

❌ **DON'T use concerns for:**
- Flow-specific business logic
- One-off operations
- Complex state management

### Naming Convention

Concerns should be:
- Named as adjectives or capabilities (e.g., `Headings`, `ProviderHelpers`)
- Focused on a single responsibility
- Well-documented with examples

### Testing

Each concern should have corresponding specs in `spec/language_operator/ux/concerns/`.

## Creating New Concerns

1. Create file in `lib/language_operator/ux/concerns/my_concern.rb`
2. Define module under `LanguageOperator::Ux::Concerns`
3. Add YARD documentation with examples
4. Include in flows via `include Concerns::MyConcern`
5. Add tests in `spec/language_operator/ux/concerns/my_concern_spec.rb`
6. Update this README

## Example: Creating a New Concern

```ruby
# lib/language_operator/ux/concerns/kubernetes_helpers.rb
module LanguageOperator
  module Ux
    module Concerns
      # Mixin for Kubernetes resource operations
      module KubernetesHelpers
        def resource_exists?(type, name)
          ctx.client.get_resource(type, name, ctx.namespace)
          true
        rescue K8s::Error::NotFound
          false
        end
      end
    end
  end
end
```

Then use it:

```ruby
class CreateAgent < Base
  include Concerns::KubernetesHelpers

  def execute
    if resource_exists?('LanguageAgent', 'my-agent')
      puts "Agent already exists!"
    end
  end
end
```
