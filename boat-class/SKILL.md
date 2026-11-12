---
name: boat-class
description: Spin up one boat.dev sandbox per participant from a CSV or a table (names, emails, phones), hand out a dark desktop with opencode preconfigured, then start and stop the whole cohort. Use when someone wants to provision per-person sandboxes, run a workshop or class of coding agents, or bulk create/start/stop boat sandboxes.
tools: [Bash, Read, Write, Edit]
---

# boat-class

Give every participant in a table their own boat.dev sandbox: full Ubuntu VM, opencode
installed and logged in, dark 1.4x desktop, a public URL if they need one. One command to
create, one to start, one to stop.

All paths below are relative to this skill directory. The scripts also live in `~/bin` if
the user has installed them there; prefer `~/bin/boat-class.sh` when it exists, otherwise
run the copies in `scripts/`.

## Prerequisites (check before doing anything)

```bash
# 1. the CLI and a key
command -v boat || curl -fsSL https://boat.dev/install | sh
test -r ~/.secrets/boat.key || echo "NO KEY — ask the user to store one (see below)"
curl -sS https://boat.dev/api/v1/limits \
  -H "Authorization: Bearer $(cat ~/.secrets/boat.key)" | jq -c '{canStart,starts}'
```

`canStart` must be `true`. The key is read from `$BOAT_API_KEY` or `~/.secrets/boat.key`
(chmod 600). Never put the key in a command line, a chat message, or a file in a repo.

## The three commands

```bash
S=~/.claude/skills/boat-class/scripts        # or ~/bin if installed there

# 1. CREATE — one box per row (do this once per cohort)
$S/boat-class.sh participants.csv --desktop --ttl 7200 \
  --model openrouter/deepseek/deepseek-v4.1-flash-1017

# 2. START — before each session (resumes, dark theme, Chrome, fresh desktop URLs)
$S/boat-class.sh participants.csv --start --desktop --ttl 7200

# 3. STOP — after each session (billing stops, disk kept 14 days)
$S/boat-class.sh participants.csv --stop
```

`--start`/`--stop` read `participants-sandboxes.csv` (written by step 1) when it exists, and
otherwise match boxes by first name or email. All three are idempotent: re-running create
returns the same sandboxes, re-running start leaves running boxes alone.

## The participant CSV

Only `firstname`, `lastname` and `email` are required; order is free, `,` or `;` both work,
and CRLF from a Windows editor is fine.

```csv
firstname,lastname,email,phone
Ada,Lovelace,ada@example.com,+44 20 7946 0000
Grace,Hopper,grace@example.com,+1 202 555 0143
```

Output table adds `sandbox_id`, `sandbox_name`, `ssh_endpoint`, `desktop_url`.

## Useful variations

```bash
$S/boat-class.sh p.csv --limit 2          # cheap smoke test: first 2 rows only
$S/boat-class.sh p.csv --dry-run          # plan only, creates nothing
$S/boat-class.sh p.csv --ids              # print the sandbox ids
$S/boat-class.sh p.csv --type default     # 4 vCPU / 8 GB instead of small (2/4)
$S/boat-class.sh p.csv --template NAME    # start from your own saved snapshot
$S/boat-class.sh p.csv --model <id> --no-verify   # skip the one-token smoke test
$S/boat-class.sh p.csv --stop --snapshot end-of-term  # permanent copy, then stop
$S/boat-start.sh --all                    # every stopped sandbox in the account
```

## Before you hand out links

- Desktop URLs carry a token that a stranger can use to control that screen, and they
  expire 10 minutes after being issued. Print them right before the session: re-run
  `--start --desktop`, or `boat-desktop.sh <id>` for one box.
- Do not paste desktop URLs into a public channel or a ticket.

## Rules that prevent surprise bills

1. Stop before you walk away: `--stop`. A `small` box is $0.018/h, `default` $0.036/h.
2. Always pass `--ttl` on create and on start: it is the backstop when you forget. Max 30
   days on a paid plan.
3. Watch the start limit: 12/min, 60/h, 200/day on the $20 plan. The script paces itself;
   more than ~12 boxes means it takes minutes, which is normal.
4. Check the state at any time: `boat list`, or `curl …/limits` for hours left.

## Troubleshooting (all seen in practice)

| Symptom | Cause | Fix |
|---|---|---|
| `cannot read 30 (bad id, or not your sandbox?)` / `HTTP 404 not_found` | a stray or shifted row in the result CSV; the "id" is a fragment | `awk -F, 'NF!=8 {print NR": "$0}' participants-sandboxes.csv` then delete those lines |
| `409 idempotency_key_reused` | same Idempotency-Key, different request body | fixed: the key is md5(email + body), so a flag change gets a new key |
| `409 machine_not_running` on commands | sandbox is stopped | `--start` it first |
| `403 api_key_action_forbidden` / `api_key_sandbox_forbidden` | scoped key lacks the action, or that sandbox | use a `ci` or `admin` preset key, or a key scoped to the box |
| `desktop_not_ready`, or empty desktop URL | stream needs a few seconds after resume | script retries 6x/3s; also `machine_not_running` means resume first |
| Smoke test fails: `The requested model is not supported` | model id wrong or not routed | check the exact id; opencode needs the `openrouter/` prefix inside a boat box |
| opencode has no desktop tools | an `opencode.json` was replaced instead of merged | the model helper merges keys, never rewrites the file |

More detail, including exact API shapes and the endpoint quirks worth knowing:
`references/boat-api-notes.md`.

## What each participant gets

- `small` box: 2 vCPU / 4 GB / 12 GB disk, Ubuntu 24.04, passwordless sudo, Docker
- opencode 1.19+ installed and logged in, default model set, `~/work/README.md` cheat sheet
  plus a personal `WELCOME.md`
- dark desktop (Adwaita-dark, 1.4x text, opencode's `mcp.computer` desktop tools intact)
- SSH: `ssh -p <port> user@<host>` from the `ssh_endpoint` column
- Their files survive stop and resume; the desktop apps do not (relaunch Chrome)
