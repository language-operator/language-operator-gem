# Schema Versioning Policy

Language Operator DSL Schema uses semantic versioning linked directly to the gem version.

## Version Format

Schema versions follow [Semantic Versioning 2.0.0](https://semver.org/):

```
MAJOR.MINOR.PATCH
```

## Accessing Schema Version

### Programmatic Access

```ruby
require 'language_operator'

# Get schema version
LanguageOperator::Dsl::Schema.version
# => "0.1.30"

# Version is also included in JSON Schema output
schema = LanguageOperator::Dsl::Schema.to_json_schema
schema[:version]
# => "0.1.30"
```

### JSON Schema Output

When generating JSON Schema, the version is automatically included:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://github.com/language-operator/language-operator-gem/schema/agent-dsl.json",
  "title": "Language Operator Agent DSL",
  "version": "0.1.30",
  ...
}
```

## Version Semantics

The schema version is **identical** to the gem version (`LanguageOperator::VERSION`). Changes to the schema follow these rules:

### MAJOR Version (X.0.0)

Breaking changes that require updates to existing agent definitions:

**Examples:**
- Removing DSL methods (e.g., removing `schedule` method)
- Renaming required fields (e.g., `description` → `summary`)
- Changing parameter types incompatibly (e.g., `mode` from Symbol to String)
- Removing supported execution modes
- Changing workflow dependency resolution behavior
- Altering constraint validation rules in breaking ways

**Migration Required:** Users must update their agent definitions to match new schema.

**Breaking Change Indicators:**
- Methods removed from `SAFE_AGENT_METHODS`, `SAFE_TOOL_METHODS`, or `SAFE_HELPER_METHODS`
- Required fields added or changed
- Enum values removed
- Pattern validation tightened (existing valid values become invalid)

### MINOR Version (0.X.0)

Backward-compatible additions and enhancements:

**Examples:**
- Adding new DSL methods (e.g., new output destinations)
- Adding new optional fields (e.g., new constraint types)
- Adding new execution modes
- Expanding enums (e.g., adding authentication types)
- Adding new workflow features that don't affect existing workflows
- Relaxing validation patterns (more values become valid)
- Adding new helper methods

**Migration Required:** None. Existing agent definitions continue to work.

**Addition Indicators:**
- New methods added to safe method lists
- New optional properties in schema definitions
- New enum values
- New JSON Schema definitions
- Pattern validation relaxed

### PATCH Version (0.0.X)

Bug fixes and non-breaking improvements:

**Examples:**
- Fixing validation regex patterns that were too strict
- Correcting schema descriptions or documentation
- Fixing default values
- Improving error messages
- Performance optimizations in schema generation
- Documentation improvements

**Migration Required:** None. Fully backward compatible.

**Fix Indicators:**
- Pattern fixes (making existing valid definitions work correctly)
- Description clarifications
- Default value corrections
- Schema metadata updates

## Schema Evolution Examples

### Example: MAJOR Version Change (Breaking)

**Before (v0.1.x):**
```ruby
agent "my-agent" do
  mode :autonomous  # Symbol
  schedule "0 12 * * *"
end
```

**After (v1.0.0) - Hypothetical Breaking Change:**
```ruby
agent "my-agent" do
  mode "autonomous"  # Now requires String
  cron_schedule "0 12 * * *"  # Renamed method
end
```

**Impact:** Existing agent definitions fail validation. Users must update code.

### Example: MINOR Version Change (Addition)

**Before (v0.1.x):**
```ruby
agent "my-agent" do
  constraints do
    daily_budget 10.00
  end
end
```

**After (v0.2.0) - New Feature:**
```ruby
agent "my-agent" do
  constraints do
    daily_budget 10.00
    monthly_budget 250.00  # NEW: Added in 0.2.0
  end
end
```

**Impact:** None. Old definitions still valid. New feature available optionally.

### Example: PATCH Version Change (Fix)

**Before (v0.1.29):**
```ruby
# Bug: timeout pattern too strict, rejects "120s"
constraints do
  timeout "2m"  # Works
  # timeout "120s"  # Would fail validation
end
```

**After (v0.1.30) - Bug Fix:**
```ruby
# Fixed: timeout pattern now accepts both formats
constraints do
  timeout "2m"    # Still works
  timeout "120s"  # Now works too
end
```

**Impact:** None. Existing valid definitions unchanged. Previously invalid definitions may now work.

## Version Compatibility

### Agent Definition Compatibility

Agent definitions are compatible across:
- ✅ Same MAJOR version (e.g., 0.1.0 agent works with 0.1.30 gem)
- ✅ MINOR upgrades (e.g., 0.1.x agent works with 0.2.x gem)
- ❌ MAJOR upgrades (e.g., 0.x.x agent may not work with 1.x.x gem)

### JSON Schema Compatibility

Generated JSON Schemas are versioned. Consumers should:

1. **Check schema version** before validation:
   ```ruby
   schema = LanguageOperator::Dsl::Schema.to_json_schema
   if Gem::Version.new(schema[:version]) >= Gem::Version.new("0.2.0")
     # Use features from 0.2.0+
   end
   ```

2. **Pin gem versions** in production:
   ```ruby
   # Gemfile
   gem 'language-operator', '~> 0.1.0'  # Allow patch updates only
   ```

## Deprecation Policy

When planning MAJOR version changes:

1. **Deprecation warnings** added in MINOR version before removal
2. **Migration guides** provided in documentation
3. **Minimum deprecation period** of one MAJOR version cycle

Example timeline:
- v0.1.0: Feature X introduced
- v0.2.0: Feature X deprecated (warnings added, docs updated)
- v0.3.0: Still supported with warnings
- v1.0.0: Feature X removed (breaking change)

## Validation and Testing

### Schema Version Testing

The gem includes comprehensive tests ensuring:
- Schema version matches gem version
- Version is included in JSON Schema output
- Safe method lists are validated against ASTValidator constants

See: `spec/language_operator/dsl/schema_spec.rb`

### Breaking Change Detection

When submitting changes:

1. **Check if change is breaking** using checklist above
2. **Update version accordingly** in `lib/language_operator/version.rb`
3. **Document in CHANGELOG.md** under appropriate section
4. **Add migration guide** if MAJOR version bump
5. **Update this document** if versioning policy changes

## Related Documentation

- [Semantic Versioning Specification](https://semver.org/)
- [Agent DSL Reference](./agent-reference.md)
- [Best Practices](./best-practices.md)
- [CHANGELOG.md](../../CHANGELOG.md)

## Questions?

For questions about schema versioning:
- Open an issue: https://github.com/language-operator/language-operator-gem/issues
- Check existing discussions about schema changes
