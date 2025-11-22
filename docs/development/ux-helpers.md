# UX Helpers Guide

## Overview

All CLI components in the Language Operator gem use **centralized UX helpers** to ensure consistency and prevent code duplication.

**NEVER create your own instances of `Pastel` or `TTY::Prompt`**. Instead, use the `UxHelper` module.

## Quick Start

### For Commands (inheriting from BaseCommand)

Commands automatically get UX helpers - just use them:

```ruby
class MyCommand < BaseCommand
  def execute
    # pastel and prompt are already available
    puts pastel.green("Success!")
    name = prompt.ask("What's your name?")
  end
end
```

### For Formatters and Other Classes

Include the `UxHelper` module:

```ruby
module LanguageOperator
  module CLI
    module Formatters
      class MyFormatter
        include Helpers::UxHelper

        def format(message)
          pastel.cyan(message)
        end
      end
    end
  end
end
```

### For Class Methods

Use `extend` instead of `include`:

```ruby
module LanguageOperator
  module CLI
    class MyUtility
      extend Helpers::UxHelper

      class << self
        def show_error(msg)
          puts pastel.red(msg)
        end
      end
    end
  end
end
```

## Available Helpers

### `pastel` - Terminal Colors

Provides colorized output using the Pastel gem:

```ruby
# Basic colors
pastel.red("Error message")
pastel.green("Success")
pastel.yellow("Warning")
pastel.cyan("Info")

# Styles
pastel.bold("Important")
pastel.dim("Less important")
pastel.italic("Emphasis")

# Combined styles
pastel.bold.white("Header")
pastel.red.bold("Critical Error")
```

### `prompt` - Interactive Input

Provides interactive user prompts using TTY::Prompt:

```ruby
# Simple question
name = prompt.ask("What's your name?")

# Yes/no confirmation
if prompt.yes?("Continue?")
  # Do something
end

# Select from options
choice = prompt.select("Choose:", %w[option1 option2 option3])

# Multi-select
selections = prompt.multi_select("Pick items:", %w[item1 item2 item3])
```

### `spinner` - Loading Indicators

Provides animated spinners for long-running operations:

```ruby
# Basic spinner
spin = spinner("Loading...")
spin.auto_spin
# do work
spin.success("Done!")

# Manual control
spin = spinner("Processing...")
spin.run do |spinner|
  sleep 2
  spinner.success("Complete!")
end

# Different formats
spin = spinner("Downloading...", format: :dots2)
spin = spinner("Building...", format: :line)
spin = spinner("Testing...", format: :pipe)

# Error handling
spin = spinner("Deploying...")
spin.auto_spin
begin
  # risky operation
  spin.success("Deployed!")
rescue => e
  spin.error("Failed: #{e.message}")
end
```

### `table` - Formatted Tables

Creates beautiful formatted tables for structured data:

```ruby
# Basic table
data = [
  ['agent-1', 'running', '2h'],
  ['agent-2', 'stopped', '5m'],
  ['agent-3', 'pending', '1m']
]
puts table(['Name', 'Status', 'Uptime'], data)

# Unicode box drawing (default)
puts table(['ID', 'Value'], data)
# ┌────┬───────┐
# │ ID │ Value │
# ├────┼───────┤
# │ 1  │ foo   │
# │ 2  │ bar   │
# └────┴───────┘

# ASCII style
puts table(['ID', 'Value'], data, style: :ascii)
# +----+-------+
# | ID | Value |
# +----+-------+
# | 1  | foo   |
# | 2  | bar   |
# +----+-------+
```

### `box` - Framed Messages

Creates framed boxes for important messages:

```ruby
# Simple box
puts box("Deployment successful!")

# With title
puts box(
  "Agent has been created and deployed to the cluster.",
  title: "Success"
)

# Different border styles
puts box("Warning!", border: :thick)
puts box("Note:", border: :light)
puts box("Error!", border: :light)

# Custom styling
puts box(
  "Important message",
  title: "Alert",
  style: { border: { fg: :red } },
  padding: 2
)

# Multi-line content
puts box(<<~MSG, title: "Next Steps")
  1. Monitor logs: aictl agent logs my-agent
  2. Check status: aictl agent inspect my-agent
  3. View metrics: aictl agent metrics my-agent
MSG
```

## Why Use UxHelper?

### Single Source of Truth
- All TTY components initialized in one place
- Easy to configure globally (e.g., disable colors for CI)
- Consistent behavior across the entire CLI

### Performance
- Memoized instances (created once per class instance)
- Reduces object allocation overhead

### Testing
- Mock once in the helper module
- All CLI components use the same mocked instance
- No need to stub in multiple places

### Maintainability
- Changes to TTY configuration happen in one file
- Easy to add new UX helpers (spinners, progress bars, etc.)
- Clear pattern for all developers and AI agents

## Migration from Direct Instantiation

### Before (Bad)

```ruby
class MyCommand < BaseCommand
  def execute
    pastel = Pastel.new  # ❌ Don't do this
    puts pastel.green("Success")
  end
end
```

### After (Good)

```ruby
class MyCommand < BaseCommand
  def execute
    # pastel already available via UxHelper
    puts pastel.green("Success")  # ✅ Use the helper
  end
end
```

## Migration from PastelHelper

`PastelHelper` is **deprecated** as of v0.1.30 and will be removed in v0.2.0.

### Before

```ruby
include Helpers::PastelHelper
puts pastel.green("Success")
```

### After

```ruby
include Helpers::UxHelper
puts pastel.green("Success")
prompt.ask("Name?")  # Now also available
```

## RuboCop Enforcement

A custom RuboCop cop (`LanguageOperator/UseUxHelper`) will detect and prevent direct instantiation:

```ruby
# This will trigger a RuboCop offense:
@pastel = Pastel.new
# Error: Avoid direct Pastel instantiation. Include `Helpers::UxHelper` and use the `pastel` method instead.

@prompt = TTY::Prompt.new
# Error: Avoid direct TTY::Prompt instantiation. Include `Helpers::UxHelper` and use the `prompt` method instead.
```

## Adding New UX Helpers

To add a new TTY component (e.g., `TTY::Spinner`), update `UxHelper`:

```ruby
# lib/language_operator/cli/helpers/ux_helper.rb
module UxHelper
  def pastel
    @pastel ||= Pastel.new
  end

  def prompt
    @prompt ||= TTY::Prompt.new
  end

  # Add new helper
  def spinner(message, format: :dots)
    TTY::Spinner.new("[:spinner] #{message}", format: format)
  end
end
```

Then use it everywhere:

```ruby
spinner("Loading...").auto_spin
# Do work
spinner.success("Done!")
```

## Examples

### Error Handler with Colors

```ruby
module Errors
  class Handler
    extend Helpers::UxHelper

    def self.handle_error(error)
      puts pastel.red("Error: #{error.message}")
      puts pastel.dim(error.backtrace.join("\n"))
    end
  end
end
```

### Interactive Wizard

```ruby
class SetupWizard
  include Helpers::UxHelper

  def run
    puts pastel.cyan("Welcome to setup!")

    name = prompt.ask("Project name?")
    env = prompt.select("Environment?", %w[development production])

    if prompt.yes?("Create #{name} in #{env}?")
      create_project(name, env)
      puts pastel.green("✓ Project created!")
    end
  end
end
```

### Formatted Output

```ruby
class StatusFormatter
  include Helpers::UxHelper

  def format(status)
    case status
    when :running
      pastel.green("● Running")
    when :stopped
      pastel.red("● Stopped")
    when :pending
      pastel.yellow("● Pending")
    end
  end
end
```

## Best Practices

1. **Always use `UxHelper`** - Never instantiate `Pastel` or `TTY::Prompt` directly
2. **Let BaseCommand handle it** - Commands get UxHelper automatically
3. **Use `include` for instance methods** - When you need `pastel` in instance methods
4. **Use `extend` for class methods** - When you need `pastel` in class methods
5. **Don't over-colorize** - Use colors for meaning (errors=red, success=green), not decoration
6. **Test without mocking** - The helpers are simple enough that tests can use real instances

## Troubleshooting

### "undefined method `pastel`"

You forgot to include the helper:

```ruby
class MyClass
  include Helpers::UxHelper  # Add this line

  def execute
    pastel.green("Now it works!")
  end
end
```

### "Pastel method chaining doesn't work"

Pastel requires proper method chaining:

```ruby
# ❌ Wrong
@pastel.green.bold("text")  # If @pastel is an instance variable

# ✅ Correct
pastel.green.bold("text")   # Use the helper method
```

### Colors don't show in CI/tests

Set `PASTEL_ENABLED=false` to disable colors:

```bash
PASTEL_ENABLED=false bundle exec rspec
```

---

**Remember:** One helper to rule them all. Use `UxHelper` for all terminal UI needs.
