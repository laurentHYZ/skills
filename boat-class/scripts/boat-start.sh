#!/usr/bin/env bash
# boat-start.sh — bring sandboxes back from stopped, ready to hand out.
#
#   boat-start.sh bx_9nb423jq bx_bbxj75ns          # ids
#   boat-start.sh ~/boat-class/students-sandboxes.csv   # a class CSV
#   boat-start.sh students.csv --ttl 7200          # set auto-stop on resume
#   boat-start.sh --all                            # every stopped sandbox
#   boat-start.sh students-sandboxes.csv --desktop # + dark theme, Chrome, fresh URLs
#   boat-start.sh students-sandboxes.csv --dry-run # show the plan only
#   boat-start.sh students-sandboxes.csv --ids     # print ids, do nothing
#   boat-start.sh students-sandboxes.csv --theme light   # viewer theme (default dark)
#   boat-start.sh --all --job 5 --fail-fast        # 5 at a time, no queuing
#
# A class CSV may hold either a sandbox_id column (the result table written by
# boat-class.sh) or just the student rows: ids are then matched by name/email.
# Reads the key from $BOAT_API_KEY, else ~/.secrets/boat.key.

set -Eeuo pipefail

API="${BOAT_API_BASE:-https://boat.dev/api/v1}"
KEY_FILE="${BOAT_KEY_FILE:-$HOME/.secrets/boat.key}"
TTL=""; DESKTOP=0; DRY=0; IDS_ONLY=0; ALL=0; FAILFAST=0; WAIT=300; JOB=4; THEME=dark
CSVS=(); IDS=()
HERE=$(dirname "$0")

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { if (( ${IDS_ONLY:-0} == 1 )); then printf '    %s\n' "$*" >&2
         else printf '    \033[32m✔\033[0m %s\n' "$*"; fi; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --csv)       CSVS+=("${2:?}"); shift 2 ;;
    --all)       ALL=1; shift ;;
    --ttl)       TTL="${2:?}"; shift 2 ;;
    --desktop)   DESKTOP=1; shift ;;
    --fail-fast) FAILFAST=1; shift ;;
    --job|-j)    JOB="${2:?}"; shift 2 ;;
    --wait)      WAIT="${2:?}"; shift 2 ;;
    --theme)     THEME="${2:?}"; shift 2 ;;
    --dry-run|-n) DRY=1; shift ;;
    --ids)       IDS_ONLY=1; shift ;;
    -h|--help)   awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    -*)          die "unknown option: $1 (try --help)" ;;
    *)           if [[ -f $1 || $1 == *.csv ]]; then CSVS+=("$1"); else IDS+=("$1"); fi; shift ;;
  esac
done

[[ -n ${BOAT_API_KEY:-} ]] || { [[ -r $KEY_FILE ]] || die "no BOAT_API_KEY and no $KEY_FILE"; BOAT_API_KEY=$(tr -d '[:space:]' <"$KEY_FILE"); }

api() {   # api METHOD PATH [curl args…]
  local m=$1 p=$2 out http; shift 2
  out=$(mktemp)
  http=$(curl -sS -o "$out" -w '%{http_code}' -X "$m" "$API$p" \
          -H "Authorization: Bearer $BOAT_API_KEY" -H 'Accept: application/json' "$@") \
       || { rm -f "$out"; die "curl failed: $m $p"; }
  if (( http >= 300 )); then
    printf '    HTTP %s [%s] %s\n' "$http" "$(jq -r '.code // "?"' "$out" 2>/dev/null)" \
      "$(jq -r '.message // ""' "$out" 2>/dev/null)" >&2
    rm -f "$out"; return 2
  fi
  cat "$out"; rm -f "$out"
}

# ---------------------------------------------------------------- build the list: "id<TAB>label"
LINES=()
if (( ALL == 1 )); then
  while IFS=$'\t' read -r id name; do LINES+=("$id"$'\t'"$name"); done < <(api GET "/sandboxes?limit=200" |
    jq -r '.sandboxes[] | select(.state=="archived") | "\(.id)\t\(.name // "")"')
  ok "found ${#LINES[@]} stopped sandbox(es)"
fi

for CSV in "${CSVS[@]:-}"; do
  [[ -z $CSV ]] && continue
  [[ -r $CSV ]] || die "cannot read $CSV"
  # Rows with an id are used as-is; rows without one are matched by name/email.
  LIST=""
  mapfile -t ROWS < <(python3 - "$CSV" <<'PY'
import csv, sys
raw = open(sys.argv[1], newline='', encoding='utf-8-sig').read()
delim = ';' if raw.count(';') > raw.count(',') else ','
rows = list(csv.DictReader(raw.splitlines(), delimiter=delim))
if not rows: sys.exit("empty csv")
head = {(k or '').strip().lower(): k for k in rows[0]}
def pick(*names):
    for n in names:
        if n in head: return head[n]
    return None
i_id = pick('sandbox_id', 'id', 'sandbox')
i_fn = pick('firstname', 'first name', 'sandbox_name')
i_ln = pick('lastname', 'last name')
i_mail = pick('email', 'e-mail', 'mail')
for r in rows:
    g = lambda k: (r.get(k) or '').strip() if k else ''
    sid, fn, ln, mail = g(i_id), g(i_fn), g(i_ln), g(i_mail)
    label = ' '.join(x for x in (fn, ln) if x) or mail or sid
    if sid:
        import re
        if re.fullmatch(r'(bx|box)_[A-Za-z0-9]+', sid):
            print(f"{sid}\t{label}")
        else:
            print(f"!\t{label}\t{sid}")
    else:
        print(f"?\t{label}\t{fn}\t{mail}")
PY
  ) || die "cannot parse $CSV"
  if printf '%s\n' "${ROWS[@]}" | grep -q '^?'; then LIST=$(api GET "/sandboxes?limit=200"); fi
  for r in "${ROWS[@]}"; do
    IFS=$'\t' read -r sid label fn mail <<<"$r"
    if [[ $sid == '!' ]]; then
      warn "row '${label:-?}' has a bad sandbox id '${fn}' — skipped (CSV column shift?)"; continue
    fi
    if [[ $sid != '?' ]]; then LINES+=("$sid"$'\t'"$label"); continue; fi
    id=$(jq -r --arg n "$label" --arg f "$fn" --arg m "$mail" '
      .sandboxes[] | select((.name // "") == $f or (.name // "") == $n) | .id' <<<"$LIST" | head -1)
    [[ -n $id ]] && LINES+=("$id"$'\t'"${label:-$id}") || warn "no sandbox found for $label"
  done
  ok "${#LINES[@]} sandbox(es) so far, from $CSV"
done

for id in "${IDS[@]:-}"; do [[ -n $id ]] && LINES+=("$id"$'\t'""); done
[[ ${#LINES[@]} -gt 0 ]] || die "nothing to start (give ids, a csv, or --all)"

if [[ $IDS_ONLY -eq 1 ]]; then
  for l in "${LINES[@]}"; do printf '%s\n' "${l%%$'\t'*}"; done; exit 0
fi

# ---------------------------------------------------------------- plan
say "plan"
ok "${#LINES[@]} sandbox(es)"
[[ -n $TTL ]] && ok "lifetime after resume: $((TTL/60)) min" || ok "lifetime: unchanged"
[[ $DESKTOP -eq 1 ]] && ok "desktop: dark theme + Chrome relaunch"
(( FAILFAST == 1 )) && ok "fail-fast: no queuing for a machine"
CAN=$(api GET /limits | jq -r '.canStart'); REM=$(api GET /limits | jq -r '.starts.minute.remaining')
[[ $CAN == true ]] || die "canStart=false — a plan limit blocks starts right now"
ok "starts left this minute: $REM"
(( ${#LINES[@]} <= REM )) || warn "more boxes than starts left this minute — pacing at $JOB at a time"

if [[ $DRY -eq 1 ]]; then
  for l in "${LINES[@]}"; do
    IFS=$'\t' read -r sid label <<<"$l"
    st=$(api GET "/sandboxes/$sid" | jq -r '.sandbox.state')
    printf '    %-13s %-20s %s\n' "$sid" "$label" "$st"
  done
  say "dry run — nothing resumed"; exit 0
fi

# ---------------------------------------------------------------- resume
say "starting"
resumed=(); failed=0; skipped=0
resume_one() {   # resume_one <id> -> prints one line
  local sid=$1 body='{}' st
  st=$(api GET "/sandboxes/$sid" | jq -r '.sandbox.state') || { printf '%-13s cannot read\n' "$sid"; return 1; }
  case $st in
    ready|idle|running) printf '%-13s already %s\n' "$sid" "$st"; return 0 ;;
    archived) ;;
    archiving|stopping)
      for _ in $(seq 1 30); do
        sleep 2; st=$(api GET "/sandboxes/$sid" | jq -r '.sandbox.state')
        [[ $st == archived ]] && break
      done
      [[ $st == archived ]] || { printf '%-13s stuck in %s\n' "$sid" "$st"; return 1; } ;;
    *) printf '%-13s is %s — skipped\n' "$sid" "$st"; return 2 ;;
  esac
  [[ -n $TTL ]] && body=$(jq -cn --argjson t "$TTL" '{ttlSeconds:$t}')
  local extra=()
  (( FAILFAST == 1 )) && body=$(jq -c --argjson t "${TTL:-0}" '. + {failFast:true} + (if $t>0 then {ttlSeconds:$t} else {} end)' <<<"$body")
  api POST "/sandboxes/$sid/resume" -H 'Content-Type: application/json' --data-binary "$body" >/dev/null 2>&1 \
    || { printf '%-13s resume failed\n' "$sid"; return 1; }
  for _ in $(seq 1 $(( WAIT / 2 ))); do
    st=$(api GET "/sandboxes/$sid" | jq -r '.sandbox.state')
    case $st in ready|idle|running) printf '%-13s resumed (%s)\n' "$sid" "$st"; return 0 ;;
                error) printf '%-13s error\n' "$sid"; return 1 ;; esac
    sleep 2
  done
  printf '%-13s still %s after %ss\n' "$sid" "$st" "$WAIT"; return 1
}

for ((i = 0; i < ${#LINES[@]}; i += JOB)); do
  pids=()
  for l in "${LINES[@]:i:JOB}"; do
    sid=${l%%$'\t'*}
    ( out=$(resume_one "$sid"); rc=$?; printf '    %s\n' "$out"; exit $rc ) & pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || failed=$((failed+1)); done
done

# ---------------------------------------------------------------- desktop
if (( DESKTOP == 1 )); then
  say "refreshing desktops (dark theme, Chrome, new URLs)"
  mapfile -t DESK < <(printf '%s\n' "${LINES[@]}" | cut -f1 | grep -E '^(bx|box)_[A-Za-z0-9]+$')
  "$HERE/boat-desktop.sh" "${DESK[@]}" || warn "desktop setup reported errors"
else
  say "desktop links"
  for l in "${LINES[@]}"; do
    sid=${l%%$'\t'*}; label=${l#*$'\t'}
    [[ $sid =~ ^(bx|box)_[A-Za-z0-9]+$ ]] || { warn "skipping bad id '$sid' (${label:-?})"; continue; }
    u=""
    for _ in $(seq 1 6); do
      u=$(api POST "/sandboxes/$sid/desktop?theme=$THEME" 2>/dev/null | jq -r '.desktopUrl // ""' || true)
      [[ -n $u ]] && break
      sleep 3
    done
    printf '    %-13s %-18s %s\n' "$sid" "$label" "${u:-<none>}"
  done
fi

say "done"
(( failed == 0 )) && ok "${#LINES[@]} sandbox(es) up" || warn "$failed sandbox(es) failed — re-run to retry"
