# skills

My personal agent skills, following the [agentskills.io](https://agentskills.io)
convention: **one directory per skill**, each containing at least a `SKILL.md`
with YAML frontmatter (`name`, `description`).

## Layout

```
skills/
├── clipboard-paste-troubleshoot/
│   └── SKILL.md
└── <another-skill>/
    ├── SKILL.md
    └── ...            # optional scripts / references the skill needs
```

## Adding a skill

```bash
mkdir -p new-skill
$EDITOR new-skill/SKILL.md
git add new-skill && git commit -m "add new-skill"
git push
```

`SKILL.md` frontmatter:

```yaml
---
name: my-skill            # short, kebab-case, matches the directory name
description: One or two sentences on when the agent should use this
             skill — include the trigger phrases people actually say.
---
```

## Using these skills

Clone to the location your agent scans, e.g. for `gptel-agent`
(`gptel-agent-skill-dirs`):

```bash
git clone git@github.com:laurentHYZ/skills.git ~/.claude/skills
# or ~/.agents/skills, ~/.opencode/skill, etc.
```

Or as a submodule inside a dotfiles repo:

```bash
git submodule add git@github.com:laurentHYZ/skills.git skills
```

## Contents

| Skill | Purpose |
|-------|---------|
| [`clipboard-paste-troubleshoot`](clipboard-paste-troubleshoot/SKILL.md) | Diagnose stale/empty paste between Windows ↔ WSL/GUI/terminal Emacs, tmux/herdr |
