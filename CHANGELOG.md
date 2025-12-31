# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **BREAKING**: Renamed CLI binary from `aictl` to `langop`
  - Binary renamed: `bin/aictl` → `bin/langop`
  - Shell completions updated: `completions/aictl.*` → `completions/langop.*`
  - All documentation updated to reference `langop`
  - Migration required: Replace `aictl` with `langop` in scripts and automation

### Removed
- **BREAKING**: Removed deprecated DSL v0 (workflow/step model)
  - Deleted `WorkflowDefinition` and `StepDefinition` classes
  - Removed `workflow` method from agent definitions
  - Removed workflow execution logic from executor
  - Removed workflow/step schema definitions
  - Users must migrate to DSL v1 (task/main model)
  - See `requirements/proposals/dsl-v1.md` for migration guide
- Removed deprecated `lib/language_operator/ux/` directory
  - Consolidated wizards under `lib/language_operator/cli/wizards/`
  - Extracted reusable helpers to `lib/language_operator/cli/helpers/`
  - All wizards now use UxHelper pattern

### Changed
- Updated agent definition examples to use task/main pattern
- Updated JSON schema artifacts to reflect DSL v1 only
- Updated documentation to focus exclusively on task/main model
- Migrated all CLI commands to use new wizard implementations:
  - `aictl agent create` uses `Wizards::AgentWizard`
  - `aictl model create` uses `Wizards::ModelWizard`
  - `aictl quickstart` uses `Wizards::QuickstartWizard`

### Added
- **Schema Version Method**: Added `LanguageOperator::Dsl::Schema.version` method that returns the current schema version (linked to gem version)
- **Schema Versioning Documentation**: Added comprehensive `docs/dsl/SCHEMA_VERSION.md` documenting versioning policy, semantic version semantics for schema changes, compatibility rules, and deprecation policy
- **Schema Export CLI Commands**: New `aictl system schema` command for exporting DSL schema
  - Export as JSON Schema v7 (default): `aictl system schema`
  - Export as YAML: `aictl system schema --format yaml`
  - Export as OpenAPI 3.0.3 spec: `aictl system schema --format openapi`
  - Show version only: `aictl system schema --version`
- **Synthesis Template Management**: New `aictl system synthesis-template` command for managing code generation templates
  - Export agent synthesis template: `aictl system synthesis-template`
  - Export persona distillation template: `aictl system synthesis-template --type persona`
  - Export with JSON/YAML metadata: `aictl system synthesis-template --format json --with-schema`
  - Validate template syntax: `aictl system synthesis-template --validate`
- **Template Validation**: New `aictl system validate-template` command for validating synthesis templates
  - Validate custom templates: `aictl system validate-template --template /path/to/template.tmpl`
  - Validate bundled templates: `aictl system validate-template --type agent`
  - AST-based validation against DSL schema
  - Detailed violation reporting with line numbers
- **Synthesis Testing**: New `aictl system test-synthesis` command for testing agent code generation
  - Test synthesis from natural language: `aictl system test-synthesis --instructions "Monitor GitHub issues"`
  - Dry-run mode to preview prompts: `--dry-run`
  - Automatic temporal intent detection (scheduled vs autonomous)
  - LLM-powered code generation with validation
- **Schema Artifacts**: Auto-generated schema artifacts stored in `lib/language_operator/templates/schema/`
  - `agent_dsl_schema.json` - Complete JSON Schema v7 specification
  - `agent_dsl_openapi.yaml` - OpenAPI 3.0.3 API documentation
  - `CHANGELOG.md` - Schema version history
- **Safe Methods API**: New public methods on `LanguageOperator::Dsl::Schema`
  - `Schema.safe_agent_methods` - Returns array of safe agent DSL methods
  - `Schema.safe_tool_methods` - Returns array of safe tool DSL methods
  - `Schema.safe_helper_methods` - Returns array of safe helper methods
- Schema version method includes YARD documentation with examples
- Tests added for schema version access and validation
- Integration tests for all new CLI commands

### Changed
- **GitHub Migration**: Migrated project from self-hosted Forgejo to GitHub
  - Repository now hosted at: https://github.com/language-operator/language-operator-gem
  - Updated all infrastructure references to use public GitHub resources
  - Container images now use GitHub Container Registry (ghcr.io)
  - Helm charts now use GitHub Pages (https://language-operator.github.io/charts)
  - Tool registry now uses GitHub raw content URLs
  - Migrated CI/CD from Forgejo workflows to GitHub Actions
  - Better community access and collaboration

### Security
- **Removed hardcoded API token** from tool registry configuration
- Token authentication now uses environment variables (`GITHUB_TOKEN`)
- Improved security posture by eliminating embedded credentials

### Changed (Previous)
- **Gem Hosting Migration**: Switched primary gem hosting from self-hosted Forgejo registry to RubyGems.org
  - RubyGems.org is now the primary publishing target for better discoverability and easier installation
  - Forgejo registry remains as an optional fallback (publishes if `REGISTRY_TOKEN` secret is configured)
  - Updated CI workflow to prioritize RubyGems.org publishing
  - Added installation instructions and RubyGems badge to README.md
  - Users can now install via: `gem install language-operator`
- **License**: Updated gemspec license from MIT to FSL-1.1-Apache-2.0 to match LICENSE file
- **Repository Cleanup**: Removed `.rspec_status` from version control (already in .gitignore)

## [0.1.0] - 2025-11-05

### Added
- Initial release of language-operator Ruby gem
- `aictl` CLI tool for managing AI agents on Kubernetes
- DSL for defining agents, tools, and workflows
- Support for MCP (Model Context Protocol) servers
- Integration with multiple LLM providers (Anthropic, OpenAI, etc.)
- Kubernetes resource management for LanguageAgent, LanguageModel, and LanguagePersona CRDs
- Agent lifecycle management (create, list, describe, delete, logs, pause, resume)
- Tool scaffolding and management
- Persona management for agent behavior customization
- Cluster configuration and context switching
- Comprehensive test suite with unit and e2e tests
- RuboCop linting configuration
- Makefile for common development tasks

[Unreleased]: https://github.com/langop/language-operator/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/langop/language-operator/releases/tag/v0.1.0
