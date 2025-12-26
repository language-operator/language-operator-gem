# Language Operator Skills

Domain-specific knowledge modules for Language Operator Ruby gem development.

## Available Skills

- [ruby-gem-development](ruby-gem-development/SKILL.md) - Ruby gem development patterns with bundler, RSpec, RuboCop, and Language Operator conventions
- [thor-cli-development](thor-cli-development/SKILL.md) - Thor-based CLI development patterns for the aictl command-line interface

## Skill Activation

Skills are automatically activated based on:
- **Keywords** in your prompts (e.g., "gem", "CLI", "Thor", "RSpec")
- **File patterns** when editing relevant files
- **Content patterns** when working with specific code structures

See [skill-rules.json](skill-rules.json) for detailed trigger configuration.

## Usage

To manually activate a skill:
```
Use the ruby-gem-development skill to help me implement a new feature
```

To see all available skills:
```
What skills are available for this project?
```