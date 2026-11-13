#!/usr/bin/env bash
#
# sync.sh — centralize agent skills from this repo into every agent's scan dir.
#
# The repo (this checkout) is the single source of truth. Each agent scans its
# own directory (e.g. ~/.claude/skills, ~/.agents/skills, ~/.codex/skills) and
# does NOT recurse, so we expose every skill here as a per-skill symlink there.
#
# Usage:
#   ./sync.sh                     # link all skills into all enabled agent dirs
#   ./sync.sh link                # same
#   ./sync.sh adopt <name>        # move a real skill from an agent dir into the
#                                 # repo, then link it back
#   ./sync.sh status              # show what's linked / drifted / unadopted
#   ./sync.sh prune               # remove broken links pointing into this repo
#   ./sync.sh dirs                # print the agent dirs that will be synced
#
# Env overrides (colon-separated list of target agent dirs):
#   SKILL_DIRS="$HOME/.claude/skills:$HOME/.agents/skills" ./sync.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.cache/skills-sync-backups"

# ---- target agent dirs ------------------------------------------------------
# Only dirs that either exist already or whose parent agent home exists.
default_dirs() {
  local candidate
  for candidate in \
    "$HOME/.agents/skills" \
    "$HOME/.claude/skills" \
    "$HOME/.codex/skills" \
    "$HOME/.opencode/skill" \
    "$HOME/.codewhale/skills" \
    "$HOME/.deepseek/skills" \
    "$HOME/.hermes/skills" \
    "$HOME/.config/emacs/gptel-skills"; do
    [ -d "$candidate" ] && printf '%s\n' "$candidate"
  done
}

if [ -n "${SKILL_DIRS:-}" ]; then
  IFS=':' read -r -a TARGETS <<<"$SKILL_DIRS"
else
  mapfile -t TARGETS < <(default_dirs)
fi

# ---- helpers ----------------------------------------------------------------
log()  { printf '  %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }

# List skills in the repo: top-level dirs that contain SKILL.md (maxdepth 2).
repo_skills() {
  find "$REPO_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' \
    | while read -r p; do basename "$p"; done | sort
}

# List skills present in a given agent dir (dirs or symlinks with SKILL.md
# reachable, excluding broken links).
agent_skills() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null \
    | while read -r p; do
        [ -f "$p/SKILL.md" ] && basename "$p"
      done | sort
}

# Does the symlink ultimately resolve into $REPO_DIR? (follows chains, so a
# pre-existing link -> another agent dir -> repo also counts.)
is_repo_link() {
  local link="$1" target
  [ -L "$link" ] || return 1
  target="$(readlink -f "$link" 2>/dev/null || true)"
  case "$target" in "$REPO_DIR"/*) return 0 ;; *) return 1 ;; esac
}

# Is $1 a symlink at all (including dangling)?
is_any_link() { [ -L "$1" ]; }

# Back up a real (non-symlink) skill dir before we replace it with a link.
backup_real() {
  local dst="$1" name
  name="$(basename "$dst")"
  mkdir -p "$BACKUP_DIR"
  local dest="$BACKUP_DIR/$name.$(date +%Y%m%d%H%M%S)"
  cp -a "$dst" "$dest" && log "backed up $dst -> $dest"
}

# ---- commands ---------------------------------------------------------------
cmd_dirs() {
  echo "Repo:  $REPO_DIR"
  echo "Agent dirs to sync:"
  for t in "${TARGETS[@]}"; do echo "  - $t"; done
}

cmd_link() {
  mapfile -t skills < <(repo_skills)
  if [ ${#skills[@]} -eq 0 ]; then
    err "no skills found in repo ($REPO_DIR)"; exit 1
  fi
  local force=0
  [ "${FORCE:-0}" = "1" ] && force=1
  echo "Linking ${#skills[@]} skill(s) from $REPO_DIR"
  local conflicts=0
  for dir in "${TARGETS[@]}"; do
    mkdir -p "$dir"
    log "→ $dir"
    for name in "${skills[@]}"; do
      local src="$REPO_DIR/$name" dst="$dir/$name"
      if is_any_link "$dst"; then
        if is_repo_link "$dst"; then
          : # already resolves into the repo -- fine
        elif [ $force -eq 1 ]; then
          ln -sfn "$src" "$dst"; log "  relinked $name (was -> $(readlink "$dst"))"
        else
          warn "  $name: symlink -> $(readlink "$dst") (not the repo; use FORCE=1 to relink)"
          conflicts=$((conflicts + 1))
        fi
      elif [ -e "$dst" ]; then
        # a real dir/file. If it is identical to the repo copy, safe to replace.
        if [ -d "$dst" ] && diff -rq "$src" "$dst" >/dev/null 2>&1; then
          backup_real "$dst" && rm -rf "$dst" && ln -s "$src" "$dst"
          log "  replaced identical copy with link: $name"
        elif [ $force -eq 1 ]; then
          backup_real "$dst" && rm -rf "$dst" && ln -s "$src" "$dst"
          log "  backed up + relinked $name"
        else
          warn "  $name: real dir differs from repo — run: $0 adopt $name  (or FORCE=1 to back up & relink)"
          conflicts=$((conflicts + 1))
        fi
      else
        ln -s "$src" "$dst"
      fi
    done
  done
  if [ $conflicts -gt 0 ]; then
    warn "$conflicts conflict(s) — see above (nothing overwritten)"
  else
    ok "all skills linked"
  fi
}

cmd_adopt() {
  local name="${1:-}"
  [ -n "$name" ] || { err "usage: $0 adopt <skill-name>"; exit 1; }
  local src="" dir
  for dir in "${TARGETS[@]}"; do
    if [ -e "$dir/$name" ] && [ ! -L "$dir/$name" ] && [ -f "$dir/$name/SKILL.md" ]; then
      src="$dir/$name"; break
    fi
  done
  if [ -z "$src" ]; then
    err "could not find a real '$name' skill in: ${TARGETS[*]}"
    exit 1
  fi
  if [ -e "$REPO_DIR/$name" ]; then
    err "$REPO_DIR/$name already exists in repo; refusing to overwrite"
    exit 1
  fi
  echo "Adopting $src → $REPO_DIR/$name"
  cp -a "$src" "$REPO_DIR/$name"
  # replace the original copy with a symlink
  rm -rf "$src"
  ln -s "$REPO_DIR/$name" "$src"
  ok "adopted $name (verify: git -C $REPO_DIR status)"
  echo "Now run: $0 link   (to link $name into the other agent dirs)"
}

cmd_prune() {
  local dir n=0
  for dir in "${TARGETS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' link; do
      if [ ! -e "$link" ] && is_repo_link "$link"; then
        rm -f "$link"; log "pruned dangling: $link"; n=$((n + 1))
      fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type l -print0)
  done
  ok "pruned $n dangling link(s)"
}

cmd_status() {
  echo "Repo: $REPO_DIR"
  echo
  echo "Skills in repo ($(repo_skills | wc -l | tr -d ' ')):"
  repo_skills | sed 's/^/  /'
  for dir in "${TARGETS[@]}"; do
    echo
    echo "Agent dir: $dir"
    if [ ! -d "$dir" ]; then echo "  (missing)"; continue; fi
    local linked=0 unlinked=0 unadopted=0
    for name in $(repo_skills | tr '\n' ' '); do
      if is_repo_link "$dir/$name"; then linked=$((linked + 1)); else unlinked=$((unlinked + 1)); fi
    done
    while read -r name; do
      [ -z "$name" ] && continue
      is_repo_link "$dir/$name" || unadopted=$((unadopted + 1))
    done < <(agent_skills "$dir")
    echo "  linked: $linked   missing-link: $unlinked   unadopted(local-only): $(comm -23 <(agent_skills "$dir") <(repo_skills) | wc -l | tr -d ' ')"
    comm -23 <(agent_skills "$dir") <(repo_skills) | sed 's/^/    + /'
  done
}

case "${1:-link}" in
  link|"") cmd_link ;;
  adopt)   shift; cmd_adopt "$@" ;;
  status)  cmd_status ;;
  prune)   cmd_prune ;;
  dirs)    cmd_dirs ;;
  *) echo "usage: $0 {link|adopt <name>|status|prune|dirs}"; exit 1 ;;
esac
