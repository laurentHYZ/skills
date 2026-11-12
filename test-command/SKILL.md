---
name: test-command
description: A test slash command to demonstrate slash command creation in Claude Code
---

# Test Slash Command

This is a test slash command created to demonstrate how to create custom slash commands in Claude Code.

## How to use
Type `/test-command` followed by any arguments you want to test.

## Current context
You invoked this command with arguments: `$ARGUMENTS`

## Available information
- Current directory: !`pwd`
- Git status (if in repo): !`git status 2>/dev/null || echo "Not a git repository"`
- Date and time: !`date`

## Instructions
1. Show the user the information above
2. Explain how this command was created
3. Offer to help create more custom slash commands

## Command creation notes
This command was created by:
1. Creating a directory at `~/.claude/skills/test-command/`
2. Adding this `SKILL.md` file with YAML frontmatter
3. The frontmatter includes:
   - `name`: test-command (becomes `/test-command`)
   - `description`: Tells Claude when to invoke automatically
4. The content includes:
   - Instructions for Claude
   - Dynamic context injection using backticks: \`!`command`\`
   - Argument substitution with `$ARGUMENTS`