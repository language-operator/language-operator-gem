# CLI Command Refactoring Plan

## Overview

Refactoring large command files into smaller, more maintainable modules organized by subdirectories.

## Current State

### File Sizes (Lines of Code)
- `agent.rb`: **1,942 lines** ⚠️
- `system.rb`: **1,259 lines** ⚠️
- `tool.rb`: 644 lines
- `install.rb`: 395 lines
- `model.rb`: 360 lines
- `cluster.rb`: 358 lines
- `persona.rb`: 320 lines

## Target Structure

### 1. Agent Commands (`lib/language_operator/cli/commands/agent/`)

```
agent/
├── base.rb                              # Thor command registration (list, inspect, create, delete)
├── workspace.rb                         # Workspace management ✅ DONE
├── optimize.rb                          # Neural→Symbolic optimization
├── rollback.rb                          # Version rollback
├── code_operations.rb                   # Code viewing & editing
├── logs.rb                              # Log streaming
├── lifecycle.rb                         # pause, resume
└── helpers/
    ├── cluster_llm_client.rb            # LLM client for synthesis ✅ DONE
    ├── code_parser.rb                   # Parse agent code
    ├── synthesis_watcher.rb             # Watch synthesis status
    └── optimization_helper.rb           # Optimization utilities
```

**Commands extracted:**
- ✅ `workspace` → `workspace.rb` (command + 3 private methods)
- 🔲 `optimize` → `optimize.rb` (1 command + ~10 helpers)
- 🔲 `rollback` → `rollback.rb` (1 command + 3 helpers)
- 🔲 `code` + `edit` → `code_operations.rb`
- 🔲 `logs` → `logs.rb`
- 🔲 `pause` + `resume` → `lifecycle.rb`

**Estimated savings:** ~1,200 lines from base.rb

---

### 2. System Commands (`lib/language_operator/cli/commands/system/`)

```
system/
├── base.rb                              # Thor command registration
├── schema.rb                            # Schema export
├── validate_template.rb                 # Template validation
├── synthesize.rb                        # Code synthesis
├── exec.rb                              # Execute agent in pod
├── synthesis_template.rb                # Template export
└── helpers/
    ├── template_loader.rb               # Load templates
    ├── template_validator.rb            # Validate templates
    ├── llm_client.rb                    # LLM synthesis calls
    ├── pod_manager.rb                   # Pod lifecycle
    └── go_template.rb                   # Template rendering
```

**Commands extracted:**
- 🔲 `schema` → `schema.rb`
- 🔲 `validate_template` → `validate_template.rb`
- 🔲 `synthesize` → `synthesize.rb`
- 🔲 `exec` → `exec.rb`
- 🔲 `synthesis-template` → `synthesis_template.rb`

**Estimated savings:** ~900 lines from base.rb

---

### 3. Tool Commands (`lib/language_operator/cli/commands/tool/`)

```
tool/
├── base.rb                              # list, inspect, delete
├── install.rb                           # Tool installation
└── helpers/
    └── registry_client.rb               # Tool registry
```

**Estimated savings:** ~300 lines from base.rb

---

### 4. Model Commands (`lib/language_operator/cli/commands/model/`)

```
model/
├── base.rb                              # list, inspect, delete
├── create.rb                            # Model creation/wizard
└── helpers/
    └── wizard_helper.rb                 # Model creation wizard
```

**Estimated savings:** ~200 lines from base.rb

---

## Implementation Strategy

### Phase 1: Agent Commands ✅ IN PROGRESS
1. ✅ Create directory structure
2. ✅ Extract `workspace.rb` module
3. ✅ Extract `helpers/cluster_llm_client.rb`
4. 🔲 Extract `helpers/code_parser.rb`
5. 🔲 Extract `helpers/synthesis_watcher.rb`
6. 🔲 Extract `optimize.rb` module
7. 🔲 Extract `rollback.rb` module
8. 🔲 Extract `code_operations.rb` module
9. 🔲 Extract `logs.rb` module
10. 🔲 Extract `lifecycle.rb` module
11. 🔲 Create `base.rb` with remaining commands (create, list, inspect, delete)
12. 🔲 Update `main.rb` to require `agent/base.rb`

### Phase 2: System Commands
1. 🔲 Create directory structure
2. 🔲 Extract helper modules
3. 🔲 Extract command modules
4. 🔲 Create base.rb
5. 🔲 Update main.rb

### Phase 3: Tool Commands
1. 🔲 Create directory structure
2. 🔲 Extract install.rb
3. 🔲 Create base.rb
4. 🔲 Update main.rb

### Phase 4: Model Commands
1. 🔲 Create directory structure
2. 🔲 Extract create.rb
3. 🔲 Create base.rb
4. 🔲 Update main.rb

### Phase 5: Testing & Cleanup
1. 🔲 Run full test suite
2. 🔲 Fix any broken imports
3. 🔲 Update documentation
4. 🔲 Delete old monolithic files

---

## Module Pattern

All extracted commands use Ruby's `included` hook pattern:

```ruby
module LanguageOperator
  module CLI
    module Commands
      module Agent
        module CommandName
          def self.included(base)
            base.class_eval do
              desc 'command NAME', 'Description'
              option :flag, type: :string
              def command(name)
                # Implementation
              end

              private

              def helper_method
                # Helpers
              end
            end
          end
        end
      end
    end
  end
end
```

Usage in `base.rb`:
```ruby
class Agent < BaseCommand
  include Agent::Workspace
  include Agent::Optimize
  include Agent::Rollback
  # ... etc
end
```

---

## Benefits

### Navigation
- **Before:** Scroll through 2,000 line files
- **After:** Open focused ~200 line modules

### Testing
- **Before:** Test entire command class
- **After:** Test individual command modules in isolation

### Reusability
- **Before:** Duplicate helper code across commands
- **After:** Shared helpers in dedicated modules

### Cognitive Load
- **Before:** Understand entire command surface area
- **After:** Focus on one command at a time

---

## Progress Tracker

| Phase | Status | Lines Extracted | Files Created |
|-------|--------|----------------|---------------|
| Agent - Structure | ✅ Complete | 0 | 4 dirs |
| Agent - Workspace | ✅ Complete | ~270 | 1 file |
| Agent - Helpers | ✅ Complete | ~400 | 4 files |
| Agent - Optimize | ✅ Complete | ~290 | 1 file |
| Agent - Rollback | ✅ Complete | ~195 | 1 file |
| Agent - Code Ops | ✅ Complete | ~100 | 1 file |
| Agent - Logs | ✅ Complete | ~85 | 1 file |
| Agent - Lifecycle | ✅ Complete | ~90 | 1 file |
| Agent - Base | ✅ Complete | ~280 | 1 file |
| Agent - Testing | ✅ Complete | N/A | N/A |
| System | 🔲 Pending | ~900 est | 0 files |
| Tool | 🔲 Pending | ~300 est | 0 files |
| Model | 🔲 Pending | ~200 est | 0 files |

**Total Progress:** ~1,710 / ~2,900 lines (59% for Agent commands)**

---

## Next Steps

1. Complete Agent helpers extraction:
   - `code_parser.rb`
   - `synthesis_watcher.rb`
   - `optimization_helper.rb`

2. Extract Agent command modules:
   - `optimize.rb` (largest, most complex)
   - `rollback.rb`
   - `code_operations.rb`
   - `logs.rb`
   - `lifecycle.rb`

3. Create `agent/base.rb` with core commands

4. Test agent commands work correctly

5. Proceed to System, Tool, Model commands
