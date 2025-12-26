---
name: thor-cli-development
description: Thor-based CLI development patterns for the aictl command-line interface
---

# Thor CLI Development Patterns

## Purpose

Provides consistent patterns for building the `aictl` CLI using Thor framework, including command structure, argument parsing, output formatting, and user experience patterns.

## When to Use This Skill

Automatically activates when:
- Creating or modifying CLI commands in `lib/language_operator/cli/commands/`
- Working with Thor command definitions
- Implementing interactive wizards
- Adding new subcommands to aictl
- Working with command-line argument parsing and validation
- Formatting CLI output (tables, progress, etc.)

## Quick Start

### New Command Checklist

- [ ] Create command class in `lib/language_operator/cli/commands/`
- [ ] Register command in `lib/language_operator/cli/main.rb`
- [ ] Add comprehensive help text with examples
- [ ] Implement input validation and error handling
- [ ] Add progress indicators for long-running operations
- [ ] Write RSpec tests in `spec/language_operator/cli/commands/`
- [ ] Update shell completions if needed

### Command Structure Checklist

- [ ] Inherit from appropriate base class
- [ ] Use descriptive `desc` and `long_desc`
- [ ] Define options with types and defaults
- [ ] Validate inputs early
- [ ] Use consistent output formatting
- [ ] Handle errors gracefully with helpful messages

## Core Principles

### 1. Thor Command Hierarchy

```ruby
# lib/language_operator/cli/main.rb
module LanguageOperator::CLI
  class Main < Thor
    desc 'agent SUBCOMMAND ...ARGS', 'Manage agents'
    subcommand 'agent', Commands::Agent
    
    desc 'model SUBCOMMAND ...ARGS', 'Manage language models'
    subcommand 'model', Commands::Model
  end
end

# Commands are organized by domain:
# agent/    - Agent lifecycle management
# model/    - Language model operations  
# tool/     - Tool management
# cluster/  - Kubernetes cluster operations
```

### 2. Command Class Pattern

```ruby
module LanguageOperator::CLI::Commands
  class Agent < Thor
    include CLI::Helpers::ClusterContext
    include CLI::Helpers::ValidationHelper
    
    desc 'create NAME', 'Create a new agent'
    long_desc <<~DESC
      Create a new autonomous agent with the specified name.
      
      The agent will be deployed to the current Kubernetes cluster
      and configured with the specified mode and schedule.
      
      Examples:
        aictl agent create my-agent
        aictl agent create scheduler --mode scheduled --schedule "0 */6 * * *"
    DESC
    option :mode, type: :string, default: 'autonomous',
           desc: 'Agent execution mode (autonomous, scheduled, reactive)'
    option :schedule, type: :string,
           desc: 'Cron schedule for scheduled agents'
    
    def create(name)
      # 1. Validate inputs
      validate_agent_name!(name)
      validate_cluster_connection!
      
      # 2. Interactive wizard if needed
      wizard = Wizards::AgentWizard.new
      config = wizard.run(name, options)
      
      # 3. Progress indication
      spinner = TTY::Spinner.new("[:spinner] Creating agent...")
      spinner.auto_spin
      
      # 4. Main operation
      builder = Kubernetes::ResourceBuilder.new
      manifest = builder.build_agent(config)
      client = Kubernetes::Client.new
      result = client.apply_resource(manifest)
      
      spinner.success
      
      # 5. Success output
      say_status(:success, "Agent '#{name}' created", :green)
      display_agent_info(result)
      
    rescue LanguageOperator::ValidationError => e
      say_error("Validation failed: #{e.message}")
      exit(1)
    rescue LanguageOperator::NetworkError => e
      say_error("Network error: #{e.message}")
      exit(1)
    end
    
    private
    
    def validate_agent_name!(name)
      return if name.match?(/\A[a-z0-9-]+\z/)
      raise ValidationError, "Invalid agent name: #{name}. Use lowercase letters, numbers, and hyphens."
    end
    
    def display_agent_info(result)
      table = TTY::Table.new(
        header: ['Property', 'Value'],
        rows: [
          ['Name', result.metadata.name],
          ['Mode', result.spec.mode],
          ['Status', result.status&.phase || 'Creating']
        ]
      )
      puts table.render(:ascii)
    end
  end
end
```

### 3. Input Validation Patterns

```ruby
# Validate required arguments
def create(name)
  if name.nil? || name.empty?
    say_error("Agent name is required")
    invoke(:help, ['create'])
    exit(1)
  end
  # ... rest of implementation
end

# Validate option combinations
def deploy(name)
  if options[:mode] == 'scheduled' && options[:schedule].nil?
    say_error("Schedule is required for scheduled agents")
    say("Example: aictl agent deploy #{name} --mode scheduled --schedule '0 */6 * * *'")
    exit(1)
  end
end

# Validate environment dependencies
def status
  validate_cluster_connection!
  validate_agent_exists!(options[:agent])
end
```

### 4. Output Formatting Standards

```ruby
# Success messages
say_status(:success, "Operation completed", :green)

# Error messages  
say_error("Something went wrong: #{error.message}")

# Info messages
say_status(:info, "Checking cluster status...", :cyan)

# Tables for structured data
table = TTY::Table.new(
  header: ['Name', 'Status', 'Mode'],
  rows: agents.map { |a| [a.name, a.status, a.mode] }
)
puts table.render(:ascii, padding: [0, 1])

# Progress indicators
spinner = TTY::Spinner.new("[:spinner] Processing...")
spinner.auto_spin
# ... operation ...
spinner.success("✓ Done!")
```

## Common Patterns

### Pattern 1: Interactive Wizard

```ruby
module LanguageOperator::CLI::Wizards
  class AgentWizard
    include CLI::Helpers::UserPrompts
    
    def run(name, options = {})
      say_header("Agent Creation Wizard")
      
      config = AgentConfig.new(name)
      
      # Mode selection
      config.mode = options[:mode] || select_mode
      
      # Schedule if needed
      if config.mode == 'scheduled'
        config.schedule = options[:schedule] || prompt_for_schedule
      end
      
      # Model selection
      config.model = select_model
      
      # Confirmation
      display_summary(config)
      return config if yes?("Create agent with these settings?")
      
      say("Agent creation cancelled", :yellow)
      exit(0)
    end
    
    private
    
    def select_mode
      prompt.select(
        "Select execution mode:",
        {
          "Autonomous" => :autonomous,
          "Scheduled" => :scheduled, 
          "Reactive" => :reactive
        }
      )
    end
    
    def prompt_for_schedule
      prompt.ask(
        "Enter cron schedule:",
        default: "0 */6 * * *",
        validate: ->(input) { CronParser.new(input).valid? }
      )
    end
  end
end
```

### Pattern 2: Error Handling with Context

```ruby
# Global error handler in base command
module LanguageOperator::CLI
  class BaseCommand < Thor
    def self.exit_on_failure?
      true
    end
    
    private
    
    def say_error(message)
      say("ERROR: #{message}", :red)
    end
    
    def handle_kubernetes_error(error)
      case error
      when K8s::Error::NotFound
        say_error("Resource not found. Check if the agent exists.")
        say("Run 'aictl agent list' to see available agents.")
      when K8s::Error::Unauthorized  
        say_error("Access denied. Check your cluster permissions.")
        say("Run 'aictl cluster status' to verify connection.")
      else
        say_error("Kubernetes error: #{error.message}")
        say("Check cluster connectivity and try again.")
      end
    end
  end
end
```

### Pattern 3: Subcommand Registration

```ruby
# lib/language_operator/cli/main.rb
module LanguageOperator::CLI
  class Main < Thor
    desc 'version', 'Show version information'
    def version
      say("aictl version #{LanguageOperator::VERSION}")
    end
    
    desc 'status', 'Show cluster and agent status'
    def status
      Commands::Status.new.invoke(:all)
    end
    
    # Subcommands
    register(Commands::Agent, 'agent', 'agent SUBCOMMAND', 'Manage agents')
    register(Commands::Model, 'model', 'model SUBCOMMAND', 'Manage models') 
    register(Commands::Tool, 'tool', 'tool SUBCOMMAND', 'Manage tools')
    register(Commands::Cluster, 'cluster', 'cluster SUBCOMMAND', 'Manage clusters')
  end
end
```

### Pattern 4: Configuration and Context

```ruby
module LanguageOperator::CLI::Helpers
  module ClusterContext
    def current_cluster
      @current_cluster ||= begin
        context = Kubernetes::Client.new.current_context
        ClusterConfig.new(context)
      end
    end
    
    def validate_cluster_connection!
      current_cluster.validate_connection!
    rescue LanguageOperator::NetworkError => e
      say_error("Cannot connect to cluster: #{e.message}")
      say("Check your kubeconfig and cluster status.")
      exit(1)
    end
    
    def with_cluster_context(&block)
      say_status(:info, "Using cluster: #{current_cluster.name}", :cyan)
      yield(current_cluster)
    end
  end
end
```

## Resource Files

For detailed information, see:
- [Command Templates](resources/command-templates.md) - Boilerplate for new commands
- [Testing CLIs](resources/testing-patterns.md) - RSpec patterns for CLI testing
- [User Experience](resources/ux-patterns.md) - Consistent user experience guidelines

## Anti-Patterns to Avoid

❌ **Missing help text** - Always provide `desc` and examples
❌ **Silent failures** - Show clear error messages and exit codes
❌ **Inconsistent output** - Use standardized formatting helpers
❌ **No input validation** - Validate early and show helpful errors
❌ **Long-running without feedback** - Use progress indicators
❌ **Poor error recovery** - Provide actionable suggestions

## Quick Reference

| Command Element | Pattern |
|----------------|---------|
| Command definition | `desc 'name ARGS', 'Description'` |
| Options | `option :name, type: :string, default: 'value'` |
| Validation | `validate_something!(value)` |
| Success output | `say_status(:success, message, :green)` |
| Error output | `say_error(message)` |
| Tables | `TTY::Table.new(header: [...], rows: [...])` |
| Progress | `TTY::Spinner.new("[:spinner] Message...")` |
| User input | `prompt.ask/select/yes?` |

## Testing Patterns

```ruby
# spec/language_operator/cli/commands/agent_spec.rb
RSpec.describe LanguageOperator::CLI::Commands::Agent do
  subject(:command) { described_class.new }
  
  let(:kubernetes_client) { instance_double(LanguageOperator::Kubernetes::Client) }
  
  before do
    allow(LanguageOperator::Kubernetes::Client).to receive(:new).and_return(kubernetes_client)
    allow($stdout).to receive(:puts) # Suppress output during tests
  end
  
  describe '#create' do
    context 'with valid agent name' do
      it 'creates the agent successfully' do
        expect(kubernetes_client).to receive(:apply_resource).and_return(mock_agent)
        
        command.create('test-agent')
        
        expect($stdout).to have_received(:puts).with(/success/i)
      end
    end
    
    context 'with invalid agent name' do
      it 'shows validation error and exits' do
        expect { command.create('Invalid_Name') }.to raise_error(SystemExit)
      end
    end
  end
end
```

## Shell Completions

```bash
# completions/aictl.bash
_aictl() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    case "${prev}" in
        aictl)
            opts="agent model tool cluster status version help"
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
        agent)
            opts="create delete list inspect logs"
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
    esac
}

complete -F _aictl aictl
```