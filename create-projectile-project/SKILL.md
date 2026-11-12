---
name: create-projectile-project
description: Skill to create directories and register them as known Projectile projects
tools: [Bash, Write, Eval]
---

# Create Projectile Project Skill

Use this skill to immediately create a new directory and register it as a known Projectile project, ready for development work.

## Quick Setup Command

```bash
mkdir PROJECT_NAME && cd PROJECT_NAME
```

## Usage Patterns

**Process for new project creation:**

1. **Bash** - Create directory and navigate
   - Command: `mkdir new-project && new-project`

2. **Eval** - Register with Projectile
   - Code: `(projectile-add-known-project "full/path")`

## Complete Workflow

### Example Usage
```
Create a new Rails project
skill: "create-projectile-project" 
args: "/home/user/dev/rails-blog"
```

### Behind the Scenes
1. Uses `mkdir -p` for deep directory creation
2. Automatically normalizes absolute paths
3. Adds to `projectile-known-projects` list
4. Assigns `default-directory` for Emacs context

### Verification
After creation, immediately verify with:
- `SPC p p` (Doom) - shows new project
- `C-c p p` (vanilla) - standard projectile menu

## Edge Cases Handled

- Existing directories (no duplication)
- Nested directory creation
- Path normalization across OS
- Doom + projectile integration

## One-liner Function

```elisp
(defun quick-project (name)
  (interactive "sProject name: ")
  (let ((path (expand-file-name name default-directory)))
    (make-directory path t)
    (projectile-add-known-project path)
    (switch-to-buffer (find-file path))
    (message "Created project: %s" path)))
```
