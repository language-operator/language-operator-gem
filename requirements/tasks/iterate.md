# Task

## Persona

Adopt the [ruby-engineer](../../../requirements/personas/ruby-engineer.md) persona while executing these instructions, please.

## Inputs

- id int -- A forgejo issue index ID.

## Background

This is a early-phase project that works exclusively in main.
Issues are found using the Forgejo MCP tools for this project:
- Owner: language-operator
- Repository: language-operator-gem

## Instructions

Follow these directions closely:

1. Use the ForgeJo tool to find the top issue for this repository.
2. Investigate if it's valid, or a mis-use of the intended feature.
3. **CRITICAL:** Switch to plan mode, and propose an implementation plan.  Await my feedback.
4. Add your implementation plan as a comment on the issue.
5. Implement the changes.
6. Run existing tests, and add new ones if necessary.  Remember to include CI. Remember the linter and that bundler will fail if it's out of sync with its lockfile.
7. **CRITICAL:** Test the actual functionality manually before committing. If it's a CLI command, run it. If it's library code, test it in the appropriate context. Never commit untested code.
8. Commit the change and push to origin.
9. **CRITICAL:** Halt while CI runs and await my feedback.
10. Comment on your solution in the ForgeJo issue.
11. Resolve the issue.

## Output

An implementation, test coverage, updated CI, and a closed ticket.