#!/bin/bash
set -e

# Navigate to the hooks directory where tsx is installed
cd "$CLAUDE_PROJECT_DIR/.claude/hooks"

# Execute the TypeScript hook with stdin piped through
cat | npx tsx skill-activation-prompt.ts