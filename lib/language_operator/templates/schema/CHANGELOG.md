# Schema Changelog

This file tracks changes to the Language Operator Agent DSL schema.

## Schema Versioning

The schema version is tied directly to the gem version and follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version: Breaking changes to DSL structure or behavior
- **MINOR** version: New features, backward-compatible additions
- **PATCH** version: Bug fixes, documentation improvements

## Version History

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
