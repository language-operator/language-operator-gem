# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
