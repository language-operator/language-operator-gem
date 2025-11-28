# Schema Changelog

This file tracks changes to the Language Operator Agent DSL schema.

## Schema Versioning

The schema version is tied directly to the gem version and follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version: Breaking changes to DSL structure or behavior
- **MINOR** version: New features, backward-compatible additions
- **PATCH** version: Bug fixes, documentation improvements

## Version History

### 0.1.64 (2025-11-27)

**Learning Status & Observability Improvements**

This release enhances the learning status tracking and observability features for agents.

**New Features:**
- Added semantic OpenTelemetry attributes for learning status tracking
- Implemented Kubernetes event emission for agent-operator communication
- Real execution metrics from learning status ConfigMap integration

**Improvements:**
- Enhanced `aictl agent learning-status` command with color-coded boxes and better clarity
- Changed terminology from "Runs Completed" to "Runs Processed"
- Improved learning status display formatting with cyan highlighted boxes
- Restructured learning status into two clear informational boxes

**Bug Fixes:**
- Handle empty string `lastExecution` in ConfigMap data
- Fixed SigNoz Query Builder v5 select fields usage
- Fixed K8s::Resource annotations handling in learning status command
- Resolved hanging tests and improved test output visibility

**Test Improvements:**
- Added comprehensive aictl smoke test playbook
- Removed obsolete learning adapter specs
- Fixed OpenTelemetry mocking in task executor event emission test

### 0.1.34 (2025-11-14)

**DSL v1: Task/Main Primitives Added**

This release adds support for the new DSL v1 pattern with task/main primitives while maintaining backward compatibility with the workflow/step pattern.

**New Features:**
- Added `task()` DSL method to AgentDefinition for defining organic functions
- Task definitions support neural (instructions), symbolic (code block), and hybrid implementations
- Tasks stored in `@tasks` hash on AgentDefinition
- Full input/output schema validation via TaskDefinition

**Improvements:**
- Added deprecation warning to `workflow()` method
- Updated schema to include task definitions
- Added comprehensive test coverage for task registration

**Deprecated:**
- `workflow` and `step` pattern (use `task` and `main` instead)
- Migration guide available in requirements/proposals/dsl-v1.md

**Backward Compatibility:**
- Existing workflow-based agents continue to work
- Both task and workflow can coexist in same agent during migration
- No breaking changes to existing code

### 0.1.30 (2025-11-12)

**Initial schema artifact generation**

This is the first release with auto-generated schema artifacts included in the gem package.

**Schema Features:**
- Complete JSON Schema v7 for Agent DSL
- OpenAPI 3.0.3 specification for agent HTTP endpoints
- Agent configuration properties (name, description, persona, mode, schedule, objectives)
- Workflow definitions with step dependencies
- Constraint definitions (budgets, rate limits, timeouts)
- Output destinations (workspace, Slack, email)
- Webhook definitions with authentication
- MCP server configuration
- Chat endpoint configuration (OpenAI-compatible)
- Tool and parameter definitions

**API Endpoints Documented:**
- `GET /health` - Health check
- `GET /ready` - Readiness check
- `POST /v1/chat/completions` - OpenAI-compatible chat endpoint
- `GET /v1/models` - List available models

**Safe Methods:**
- Agent DSL methods validated via `Agent::Safety::ASTValidator`
- Tool DSL methods for parameter definitions
- Helper methods for HTTP, Shell, validation, and utilities

---

## Future Versions

### Template for New Entries

```markdown
### X.Y.Z (YYYY-MM-DD)

**Summary of changes**

**Breaking Changes:**
- Description of any breaking changes

**New Features:**
- New DSL methods or capabilities added
- New endpoint specifications

**Improvements:**
- Schema validation enhancements
- Documentation updates

**Bug Fixes:**
- Schema corrections
- Type definition fixes

**Deprecated:**
- Features marked for removal in future versions
```

---

## Schema Validation

The schema can be used for:
- **Template Validation** - Ensuring synthesized agent code is valid
- **Documentation Generation** - Auto-generating reference docs
- **IDE Support** - Providing autocomplete and IntelliSense
- **CLI Introspection** - Runtime validation of agent definitions

## Schema Artifacts

Generated artifacts are stored in this directory:
- `agent_dsl_schema.json` - JSON Schema v7 specification
- `agent_dsl_openapi.yaml` - OpenAPI 3.0.3 specification

These are regenerated automatically during the build process via:
```bash
rake schema:generate
```
