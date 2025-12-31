# Language Operator Hooks

Event-driven automation for Claude Code in Language Operator development.

## Available Hooks

- [skill-activation-prompt](skill-activation-prompt.ts) - Automatically suggests relevant skills based on user prompts

## Setup

The hooks are pre-configured and should work automatically. If you encounter issues:

```bash
cd .claude/hooks
npm install
chmod +x *.sh
```

## How It Works

When you submit a prompt to Claude, the `UserPromptSubmit` hook runs and:

1. Analyzes your prompt for keywords and intent patterns
2. Matches against skill trigger rules in `../skills/skill-rules.json`
3. Displays recommendations like:

```
🎯 SKILL ACTIVATION CHECK
📚 RECOMMENDED SKILLS:
  → ruby-gem-development - Ruby gem development patterns
  → thor-cli-development - CLI development patterns

💡 ACTION: Consider using the Skill tool to activate relevant skills
```

## Testing

To test the hook manually:

```bash
cd .claude/hooks
echo '{"prompt": "create a gem feature", "cwd": ".", "session_id": "test", "transcript_path": "", "permission_mode": "ask"}' | npx tsx skill-activation-prompt.ts
```