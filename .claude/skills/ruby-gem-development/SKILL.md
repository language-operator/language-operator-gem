---
name: ruby-gem-development
description: Ruby gem development patterns with bundler, RSpec, RuboCop, and Language Operator conventions
---

# Ruby Gem Development Patterns

## Purpose

Provides consistent patterns for developing the Language Operator Ruby gem, including testing, linting, packaging, and release practices.

## When to Use This Skill

Automatically activates when:
- Working with gem specification files (*.gemspec)
- Creating or modifying RSpec tests
- Running bundler commands
- Implementing new library features in `lib/`
- Working with Rakefile tasks
- Preparing releases or version bumps

## Quick Start

### New Feature Checklist

- [ ] Create feature code in `lib/language_operator/`
- [ ] Add comprehensive RSpec tests in `spec/`
- [ ] Update CHANGELOG.md with change
- [ ] Run `make lint` to check code style
- [ ] Run `make test` to verify functionality
- [ ] Update documentation if needed
- [ ] Bump version in `lib/language_operator/version.rb` (if needed)

### Testing Checklist

- [ ] Unit tests cover all public methods
- [ ] Integration tests for complex workflows
- [ ] Mock external dependencies (HTTP, Kubernetes)
- [ ] Use `let` blocks for test setup
- [ ] Follow `describe`/`context`/`it` hierarchy
- [ ] Test both success and failure paths

## Core Principles

### 1. Layered Architecture

```ruby
# lib/language_operator/
#   ├── cli/           # Command-line interface (Thor)
#   ├── dsl/           # Domain-specific language
#   ├── agent/         # Agent runtime
#   ├── client/        # LLM + MCP client
#   └── kubernetes/    # K8s integration

# Each layer has clear responsibilities:
# CLI → DSL → Agent → Client → External APIs
```

### 2. RSpec Testing Patterns

```ruby
# Good: Descriptive hierarchy
RSpec.describe LanguageOperator::Agent::Base do
  describe '#execute_goal' do
    context 'when goal is valid' do
      it 'executes successfully' do
        # Test implementation
      end
    end
    
    context 'when goal is invalid' do
      it 'raises TaskValidationError' do
        expect { agent.execute_goal('') }.to raise_error(
          LanguageOperator::Agent::TaskValidationError
        )
      end
    end
  end
end

# Use let blocks for setup
let(:agent) { described_class.new(config) }
let(:config) { instance_double(LanguageOperator::Client::Config) }
```

### 3. Error Handling Standards

```ruby
# Custom error hierarchy
module LanguageOperator
  class Error < StandardError; end
  class NetworkError < Error; end
  class ValidationError < Error; end
  class SecurityError < Error; end
end

# Raise with context
raise LanguageOperator::ValidationError, 
  "Invalid schedule format: #{schedule}"

# Handle gracefully
rescue LanguageOperator::NetworkError => e
  Logger.warn("Network issue, retrying: #{e.message}")
  retry_with_backoff
end
```

### 4. Gem Configuration

```ruby
# language-operator.gemspec
Gem::Specification.new do |spec|
  spec.name = 'language-operator'
  spec.version = LanguageOperator::VERSION
  spec.required_ruby_version = '>= 3.2.0'
  
  # Dependencies
  spec.add_dependency 'ruby_llm', '~> 1.8'
  spec.add_dependency 'thor', '~> 1.3'
  
  # Development dependencies
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.60'
end
```

## Common Patterns

### Pattern 1: CLI Command Structure

```ruby
module LanguageOperator::CLI::Commands
  class Agent < Thor
    desc 'create NAME', 'Create a new agent'
    option :mode, type: :string, default: 'autonomous'
    
    def create(name)
      # Validation
      validate_agent_name!(name)
      
      # Wizard for interactive setup
      wizard = Wizards::AgentWizard.new
      config = wizard.run(name, options)
      
      # Resource creation
      builder = Kubernetes::ResourceBuilder.new
      manifest = builder.build_agent(config)
      
      # Apply to cluster
      client = Kubernetes::Client.new
      client.apply_resource(manifest)
      
      say "Agent '#{name}' created successfully", :green
    end
    
    private
    
    def validate_agent_name!(name)
      return if name.match?(/\A[a-z0-9-]+\z/)
      raise ValidationError, "Invalid agent name: #{name}"
    end
  end
end
```

### Pattern 2: DSL Definition Pattern

```ruby
module LanguageOperator::Dsl
  class AgentDefinition
    attr_reader :name, :mode, :schedule, :tools
    
    def initialize(name)
      @name = name
      @tools = []
      yield(self) if block_given?
    end
    
    def mode(value)
      @mode = validate_mode!(value)
    end
    
    def schedule(expression)
      @schedule = validate_cron!(expression)
    end
    
    def tool(name, &block)
      @tools << ToolDefinition.new(name, &block)
    end
    
    private
    
    def validate_mode!(mode)
      valid_modes = %i[autonomous scheduled reactive]
      return mode if valid_modes.include?(mode)
      raise ValidationError, "Invalid mode: #{mode}"
    end
  end
end
```

### Pattern 3: Test Organization

```ruby
# spec/language_operator/agent/base_spec.rb
RSpec.describe LanguageOperator::Agent::Base do
  subject(:agent) { described_class.new(config) }
  
  let(:config) do
    instance_double(
      LanguageOperator::Client::Config,
      agent_name: 'test-agent',
      mode: :autonomous
    )
  end
  
  describe '.new' do
    it 'initializes with config' do
      expect(agent.config).to eq(config)
    end
  end
  
  describe '#run' do
    context 'in autonomous mode' do
      before { allow(config).to receive(:mode).and_return(:autonomous) }
      
      it 'starts executor loop' do
        executor = instance_double(LanguageOperator::Agent::Executor)
        allow(LanguageOperator::Agent::Executor).to receive(:new).and_return(executor)
        expect(executor).to receive(:run_loop)
        
        agent.run
      end
    end
  end
end
```

## Resource Files

For detailed information, see:
- [Testing Patterns](resources/testing-patterns.md) - Comprehensive RSpec guidelines
- [Release Process](resources/release-process.md) - Version bumps and gem publishing
- [Code Style](resources/code-style.md) - RuboCop configuration and standards

## Anti-Patterns to Avoid

❌ **Mixing layers** - Don't put business logic in CLI classes
❌ **Missing tests** - No production code without corresponding specs  
❌ **Hardcoded values** - Use configuration and environment variables
❌ **Silent failures** - Always log and raise meaningful errors
❌ **Coupling to external services** - Use dependency injection and mocking
❌ **Inconsistent naming** - Follow Ruby conventions (snake_case, descriptive names)

## Quick Reference

| Need to... | Use this |
|-----------|----------|
| Run all tests | `make test` |
| Run integration tests | `make test-integration` |
| Check code style | `make lint` |
| Auto-fix style issues | `make lint-fix` |
| Build gem | `make build` |
| Install locally | `make install` |
| Generate docs | `make yard-docs` |
| Open console | `make console` |

## Version Management

```ruby
# lib/language_operator/version.rb
module LanguageOperator
  VERSION = '0.1.81'
end

# Follow semantic versioning:
# MAJOR.MINOR.PATCH
# - MAJOR: Breaking changes
# - MINOR: New features, backward compatible
# - PATCH: Bug fixes, backward compatible
```

## Release Checklist

- [ ] Update `VERSION` in `lib/language_operator/version.rb`
- [ ] Update `CHANGELOG.md` with changes
- [ ] Run full test suite: `make test-all`
- [ ] Check code style: `make lint`
- [ ] Build gem: `make build`
- [ ] Test installation: `make install`
- [ ] Commit and tag: `git tag v0.1.X`
- [ ] Push with tags: `git push --tags`
- [ ] Publish to RubyGems: `gem push language-operator-X.gem`