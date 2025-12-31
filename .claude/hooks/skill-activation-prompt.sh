#!/bin/bash
set -e

# Determine project directory - use CLAUDE_PROJECT_DIR if set, otherwise current directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Navigate to the hooks directory where tsx is installed
cd "$PROJECT_DIR/.claude/hooks"

# Execute the TypeScript hook with stdin piped through
cat | npx tsx skill-activation-prompt.ts