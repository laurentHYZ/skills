#!/usr/bin/env bash
# boat-stop.sh — stop (snapshot + stop billing) or delete boat sandboxes, in bulk.
#
#   boat-stop.sh <id> [id…]                 # stop, keep the disk 14 days
#   boat-stop.sh <id> --snapshot my-name    # save a permanent saved snapshot first
#   boat-stop.sh <id> --delete              # stop, then delete it and its data
#   boat-stop.sh <id> --keep-running        # only do --snapshot, do not stop
#   boat-stop.sh <id> --dry-run             # show what would happen
#
# Reads the key from $BOAT_API_KEY, else ~/.secrets/boat.key.
# Prints the VM time each sandbox used before it stops.

set -Eeuo pipefail

API="${BOAT_API_BASE:-https://boat.dev/api/v1}"
KEY_FILE="${BOAT_KEY_FILE:-$HOME/.secrets/boat.key}"
DELETE=0; KEEP_RUNNING=0; SNAP=""; DRY=0; IDS=()

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --delete)       DELETE=1; shift ;;
    --snapshot)     SNAP="${2:?--snapshot needs a name}"; shift 2 ;;
    --keep-running) KEEP_RUNNING=1; shift ;;
    --dry-run|-n)   DRY=1; shift ;;
    -h|--help)      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)             die "unknown option: $1 (try --help)" ;;
    *)              IDS+=("$1"); shift ;;
  esac
done
[[ ${#IDS[@]} -gt 0 ]] || die "give at least one sandbox id (boat list --all)"

[[ -n ${BOAT_API_KEY:-} ]] || { [[ -r $KEY_FILE ]] || die "no BOAT_API_KEY and no $KEY_FILE"; BOAT_API_KEY=$(tr -d '[:space:]' <"$KEY_FILE"); }

api() {   # api METHOD PATH [curl args…] -> body on stdout, fails on HTTP >= 300
  local m=$1 p=$2 out http; shift 2
  out=$(mktemp)
  http=$(curl -sS -o "$out" -w '%{http_code}' -X "$m" "$API$p" \
          -H "Authorization: Bearer $BOAT_API_KEY" -H 'Accept: application/json' "$@") \
       || { rm -f "$out"; return 3; }
  if (( http >= 300 )); then
    printf '    HTTP %s [%s] %s\n' "$http" "$(jq -r '.code // "?"' "$out" 2>/dev/null)" \
      "$(jq -r '.message // ""' "$out" 2>/dev/null)" >&2
    rm -f "$out"; return 2
  fi
  cat "$out"; rm -f "$out"
}

wait_state() {   # wait_state <id> <wanted-state> [tries]
  local id=$1 want=$2 tries=${3:-30} st
  for _ in $(seq 1 "$tries"); do
    st=$(api GET "/sandboxes/$id" 2>/dev/null | jq -r '.sandbox.state // "?"')
    [[ $st == "$want" ]] && return 0
    sleep 2
  done
  return 1
}

for raw in "${IDS[@]}"; do
  id=$(printf '%s' "$raw" | tr -d '[:space:]\r')
  if [[ ! $id =~ ^(bx|box)_[A-Za-z0-9]+$ ]]; then
    warn "skipping '$raw' — not a sandbox id (expected bx_… or box_…); check the CSV for a shifted column or a stray row"
    continue
  fi
  say "$id"
  info=$(api GET "/sandboxes/$id") || die "cannot read $id (bad id, or not your sandbox?)"
  st=$(jq -r '.sandbox.state' <<<"$info")
  name=$(jq -r '.sandbox.name // "-"' <<<"$info")
  typ=$(jq -r '.sandbox.type // "?"' <<<"$info")
  ok "$name · $typ · state $st"

  if [[ -n $SNAP ]]; then
    if [[ $DRY -eq 1 ]]; then ok "would save snapshot '$SNAP'"; else
      api POST /saved-snapshots -H 'Content-Type: application/json' \
          -d "$(jq -cn --arg n "$SNAP" --arg id "$id" '{name:$n,sandboxId:$id}')" >/dev/null \
        || { warn "snapshot failed on $id — not stopping it"; continue; }
      for _ in $(seq 1 40); do
        s=$(api GET "/saved-snapshots/$SNAP" | jq -r '.snapshot.status // "?"')
        [[ $s == ready || $s == failed ]] && break; sleep 3
      done
      [[ $s == ready ]] && ok "saved snapshot '$SNAP' (never expires)" || { warn "snapshot is $s"; continue; }
    fi
    [[ $KEEP_RUNNING -eq 1 ]] && continue
  fi

  cost=$(api GET "/sandboxes/$id/usage" 2>/dev/null | jq -r '"\(.seconds)s / $\(.dollars)"' || echo "-")

  if [[ $st == archived ]]; then
    ok "already stopped (disk kept; $cost used)"
  elif [[ $DRY -eq 1 ]]; then
    ok "would stop ($cost used)"
  else
    api POST "/sandboxes/$id/stop" >/dev/null || { warn "stop refused or failed on $id"; continue; }
    if wait_state "$id" archived 30; then ok "stopped ($cost used)"; else warn "stop still in progress"; fi
  fi

  if [[ $DELETE -eq 1 ]]; then
    if [[ $DRY -eq 1 ]]; then ok "would delete"; continue; fi
    if api DELETE "/sandboxes/$id" -H "X-Ascii-Confirm-Delete: $id" >/dev/null; then
      ok "delete requested (202, cannot be cancelled)"
    else
      warn "delete failed on $id (is it still archiving? retry in a few seconds)"
    fi
  fi
done

say "done"
