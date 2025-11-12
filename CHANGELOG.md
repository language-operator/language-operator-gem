# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Schema Version Method**: Added `LanguageOperator::Dsl::Schema.version` method that returns the current schema version (linked to gem version)
- **Schema Versioning Documentation**: Added comprehensive `docs/dsl/SCHEMA_VERSION.md` documenting versioning policy, semantic version semantics for schema changes, compatibility rules, and deprecation policy
- Schema version method includes YARD documentation with examples
- Tests added for schema version access and validation

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
