# skills

Central store for my agent skills, following the [agentskills.io](https://agentskills.io)
convention: **one directory per skill**, each containing at least a `SKILL.md`
with YAML frontmatter (`name`, `description`).

This repo is the **single source of truth**. Agents scan their own directories
(`~/.claude/skills`, `~/.agents/skills`, `~/.codex/skills`, …) and do **not**
recurse, so each skill is exposed there as a **symlink** into one checkout of
this repo. Edit here → `git pull` / `git push` → every agent sees the update.

## Layout

```
~/code/skills/                 # THE checkout (clone once per machine)
├── sync.sh                    # link / adopt / status / prune helper
├── README.md
├── clipboard-paste-troubleshoot/
│   └── SKILL.md
├── <another-skill>/
│   ├── SKILL.md
│   └── ...                    # optional scripts / references
└── ...

~/.claude/skills/<skill>   ->  ~/code/skills/<skill>   (symlink)
~/.agents/skills/<skill>   ->  ~/code/skills/<skill>   (symlink)
~/.codex/skills/<skill>    ->  ~/code/skills/<skill>   (symlink)
```

## Setup (per machine)

```bash
gh repo clone laurentHYZ/skills ~/code/skills
cd ~/code/skills
./sync.sh status     # see what's linked / missing / unadopted
./sync.sh            # link every skill into every detected agent dir
```

`sync.sh` auto-detects these agent dirs (override with `SKILL_DIRS=...`):

`~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`,
`~/.opencode/skill`, `~/.codewhale/skills`, `~/.deepseek/skills`,
`~/.hermes/skills`.

## Daily workflow

```bash
cd ~/code/skills
git pull                 # pick up changes from other machines
./sync.sh                # re-link (idempotent; safe to run anytime)
# ... edit / add a skill ...
git add -A && git commit -m "update <skill>" && git push
```

`./sync.sh` is what to run after a pull (or a new skill) to keep links fresh;
because links point at the checkout, edits in place are usually already live.

## Adding a skill

```bash
mkdir -p ~/code/skills/new-skill
$EDITOR ~/code/skills/new-skill/SKILL.md
cd ~/code/skills && ./sync.sh && git add new-skill
git commit -m "add new-skill" && git push
```

## Adopting a skill that lives in an agent dir

Skills fetched by some other installer land as real files in e.g.
`~/.agents/skills`. Bring them into the repo and replace them with a link:

```bash
cd ~/code/skills
./sync.sh adopt my-skill   # moves ~/.agents/skills/my-skill → repo, links it back
./sync.sh                  # link it into the other agent dirs
git add my-skill && git commit -m "adopt my-skill" && git push
```

`./sync.sh status` lists **unadopted (local-only)** skills in each agent dir so
nothing gets left behind.

## Commands

| Command | What it does |
|---|---|
| `./sync.sh` / `./sync.sh link` | symlink every repo skill into every detected agent dir |
| `./sync.sh status` | show linked / missing / local-only skills per agent dir |
| `./sync.sh adopt <name>` | move a real skill from an agent dir into the repo + link it back |
| `./sync.sh prune` | remove broken symlinks that point into this repo |
| `./sync.sh dirs` | list the agent dirs that will be synced |

`SKILL.md` frontmatter convention:

```yaml
---
name: my-skill            # short, kebab-case, matches the directory name
description: One or two sentences on when the agent should use this
             skill — include the trigger phrases people actually say.
---
```

## Contents

Run `./sync.sh status` or `ls` for the current list. Vendored third‑party
skills (cloudflare, remotion, gsap, …) live here too; update them deliberately
when upstream changes rather than blind‑pulling.
