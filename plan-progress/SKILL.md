---
name: plan-progress
description: Check progress of plan.md files in the current project
---

# Plan Progress Slash Command

This command analyzes `plan.md` files in the current project to show progress based on checked checkboxes.

## How to use
Type `/plan-progress` with optional directory path as argument. If no argument, uses current directory.

## Finding plan.md
The command searches for `plan.md` in the current directory and parent directories up to the home directory.

## Progress calculation
- Total checkboxes: lines matching `- [ ]`, `* [ ]`, `+ [ ]` or their checked versions
- Completed checkboxes: lines matching `- [x]`, `* [x]`, `+ [x]`
- Progress percentage: (completed / total) * 100

## Current context
You invoked this command with arguments: `$ARGUMENTS`

## Progress report
!`bash /home/laurent/.claude/skills/plan-progress/plan-progress.sh "$ARGUMENTS"`