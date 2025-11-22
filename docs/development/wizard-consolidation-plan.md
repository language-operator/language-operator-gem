# Wizard Consolidation Plan

## Overview

Consolidate the duplicate wizard implementations from `lib/language_operator/ux/` into `lib/language_operator/cli/wizards/` and remove the `ux` folder entirely.

## Current State

### Duplicate Implementations

**lib/language_operator/ux/** (Old pattern - 1600 total lines)
- `base.rb` (81 lines) - Base class with `@prompt = TTY::Prompt.new`, `@pastel = Pastel.new`
- `quickstart.rb` (594 lines) - Old quickstart wizard
- `create_agent.rb` (255 lines) - Old agent creation wizard
- `create_model.rb` (267 lines) - Model creation wizard
- `concerns/headings.rb` (90 lines) - Heading helpers
- `concerns/input_validation.rb` (146 lines) - Input validation helpers
- `concerns/provider_helpers.rb` (167 lines) - Provider-specific helpers

**lib/language_operator/cli/wizards/** (New pattern)
- `quickstart_wizard.rb` - Uses `UxHelper` ✅
- `agent_wizard.rb` - Uses `UxHelper` ✅

### Usage Points

Files requiring from `ux/`:
1. `lib/language_operator/cli/commands/agent.rb` - Uses `Ux::CreateAgent`
2. `lib/language_operator/cli/commands/model.rb` - Uses `Ux::CreateModel`
3. `lib/language_operator/cli/commands/quickstart.rb` - Uses `Ux::Quickstart`

## Problems with Current Structure

1. **Duplicate wizards**: Both `ux/quickstart.rb` and `cli/wizards/quickstart_wizard.rb` exist
2. **Duplicate wizards**: Both `ux/create_agent.rb` and `cli/wizards/agent_wizard.rb` exist
3. **Old pattern**: `Ux::Base` uses direct `Pastel.new` and `TTY::Prompt.new` (violates new UxHelper pattern)
4. **Tech debt**: The `ux/` folder predates the UxHelper refactor
5. **Confusing**: Two locations for wizards makes it unclear which to use

## Migration Plan

### Phase 1: Analyze and Extract Reusable Code

**Goal**: Identify unique functionality in old wizards that should be preserved

1. **Compare implementations**:
   - [ ] Diff `ux/quickstart.rb` vs `cli/wizards/quickstart_wizard.rb`
   - [ ] Diff `ux/create_agent.rb` vs `cli/wizards/agent_wizard.rb`
   - [ ] Identify any unique features in old implementations

2. **Extract concerns to cli/helpers**:
   - [ ] Review `ux/concerns/headings.rb` - Extract useful methods to new `cli/helpers/heading_helper.rb`
   - [ ] Review `ux/concerns/input_validation.rb` - Extract to `cli/helpers/validation_helper.rb`
   - [ ] Review `ux/concerns/provider_helpers.rb` - Extract to `cli/helpers/provider_helper.rb`
   - [ ] All new helpers should use `UxHelper` pattern (not direct instantiation)

3. **Document differences**:
   - [ ] Create comparison doc showing what's in old vs new wizards
   - [ ] Identify any regression risks

### Phase 2: Create Missing Wizard

**Goal**: Migrate model creation wizard to new location

1. **Create ModelWizard**:
   - [ ] Create `lib/language_operator/cli/wizards/model_wizard.rb`
   - [ ] Port functionality from `ux/create_model.rb`
   - [ ] Use `include Helpers::UxHelper` (not `Ux::Base`)
   - [ ] Extract any reusable logic to helpers
   - [ ] Add tests if they don't exist

### Phase 3: Update Command References

**Goal**: Switch commands to use new wizard locations

1. **Update agent command**:
   - [ ] Change `lib/language_operator/cli/commands/agent.rb`
   - [ ] Replace `require_relative '../../ux/create_agent'`
   - [ ] Replace `Ux::CreateAgent.execute(ctx)`
   - [ ] Use `Wizards::AgentWizard.new.run` instead

2. **Update model command**:
   - [ ] Change `lib/language_operator/cli/commands/model.rb`
   - [ ] Replace `require_relative '../../ux/create_model'`
   - [ ] Replace `Ux::CreateModel.execute(ctx)`
   - [ ] Use `Wizards::ModelWizard.new.run` instead

3. **Update quickstart command**:
   - [ ] Change `lib/language_operator/cli/commands/quickstart.rb`
   - [ ] Replace `require_relative '../../ux/quickstart'`
   - [ ] Replace `Ux::Quickstart.execute(ctx)`
   - [ ] Use `Wizards::QuickstartWizard.new.run` instead

### Phase 4: Testing

**Goal**: Ensure no regressions

1. **Manual testing**:
   - [ ] Test `aictl agent create` wizard flow
   - [ ] Test `aictl model create` wizard flow
   - [ ] Test `aictl quickstart` wizard flow
   - [ ] Verify all interactive prompts work
   - [ ] Verify all validation works

2. **Automated testing**:
   - [ ] Run full test suite: `bundle exec rspec`
   - [ ] Run linter: `bundle exec rubocop`
   - [ ] Ensure no RuboCop violations for UxHelper pattern

### Phase 5: Cleanup

**Goal**: Remove deprecated code

1. **Remove ux folder**:
   - [ ] Delete `lib/language_operator/ux/` directory entirely
   - [ ] Ensure no references remain: `grep -r "require.*ux/" lib/`
   - [ ] Ensure no references remain: `grep -r "Ux::" lib/`

2. **Update RuboCop config**:
   - [ ] Remove all `lib/language_operator/ux/base.rb` exclusions from `.rubocop.yml`
   - [ ] Clean up any ux-related comments

3. **Update documentation**:
   - [ ] Update `docs/architecture/` if it references ux folder
   - [ ] Update `CLAUDE.md` to remove ux folder references
   - [ ] Add migration notes to CHANGELOG.md

### Phase 6: Commit

**Goal**: Clean commit history

1. **Commit strategy**:
   ```bash
   # Commit 1: Add new helpers and ModelWizard
   git add lib/language_operator/cli/helpers/*_helper.rb
   git add lib/language_operator/cli/wizards/model_wizard.rb
   git commit -m "Add wizard helpers and ModelWizard"

   # Commit 2: Update command references
   git add lib/language_operator/cli/commands/*.rb
   git commit -m "Migrate commands to use cli/wizards instead of ux/"

   # Commit 3: Remove old ux folder
   git rm -r lib/language_operator/ux
   git add .rubocop.yml docs/
   git commit -m "Remove deprecated ux/ folder"
   ```

## Implementation Checklist

### Pre-work
- [ ] Create this plan document
- [ ] Review with team/user for approval

### Phase 1: Analysis (Est. 30 min)
- [ ] Compare quickstart implementations
- [ ] Compare agent implementations
- [ ] Extract concerns to helpers
- [ ] Document findings

### Phase 2: ModelWizard (Est. 45 min)
- [ ] Create model_wizard.rb
- [ ] Port functionality
- [ ] Test manually

### Phase 3: Update Commands (Est. 20 min)
- [ ] Update agent.rb
- [ ] Update model.rb
- [ ] Update quickstart.rb

### Phase 4: Testing (Est. 30 min)
- [ ] Manual wizard testing
- [ ] Run test suite
- [ ] Fix any issues

### Phase 5: Cleanup (Est. 15 min)
- [ ] Remove ux/ folder
- [ ] Update configs
- [ ] Update docs

### Phase 6: Commit (Est. 10 min)
- [ ] Create clean commits
- [ ] Push to GitHub
- [ ] Verify CI passes

## Success Criteria

✅ All wizards in `lib/language_operator/cli/wizards/`
✅ All wizards use `UxHelper` pattern (no direct `Pastel.new` or `TTY::Prompt.new`)
✅ No `lib/language_operator/ux/` folder
✅ All commands work correctly
✅ No RuboCop violations
✅ All tests pass
✅ CI passes
✅ No grep matches for `require.*ux/` or `Ux::` in lib/

## Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Old wizards have unique features | Medium | High | Careful diff and feature extraction |
| Breaking changes in commands | Low | High | Thorough manual testing before cleanup |
| Test failures | Low | Medium | Run tests frequently during migration |
| RuboCop violations | Low | Low | Run rubocop after each phase |

## Notes

- The new wizards already exist and use the correct pattern
- The old `Ux::Base` class violates our new UxHelper pattern
- This consolidation completes the UxHelper refactoring
- Estimated total time: ~2.5 hours
- Can be done incrementally over multiple sessions

## References

- UxHelper documentation: `docs/development/ux-helpers.md`
- Custom RuboCop cop: `.rubocop_custom/use_ux_helper.rb`
- Current wizards: `lib/language_operator/cli/wizards/`
- Old wizards: `lib/language_operator/ux/`
