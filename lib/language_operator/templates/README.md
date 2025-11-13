# Templates Directory

This directory contains templates used by the Language Operator gem for various code generation and synthesis tasks.

## Directory Structure

- **`examples/`** - Example synthesis templates for agent and persona generation
  - `agent_synthesis.tmpl` - Template for synthesizing agent definitions
  - `persona_distillation.tmpl` - Template for distilling persona configurations

- **`schema/`** - JSON Schema definitions and validation templates
  - Reserved for future schema artifacts and validation templates

## Usage

Templates in this directory are used by:
- The `aictl system synthesis-template` command for managing synthesis templates
- Agent synthesis and persona distillation features
- Schema validation and code generation tools

## Template Format

Templates use a simple variable substitution format compatible with the synthesis engine. Variables are typically specified in the template header and replaced during synthesis.
