#!/usr/bin/env bash
# boat-class.sh — give each student in a CSV their own sandbox, prepared and ready.
#
#   boat-class.sh students.csv                 # create one sandbox per row
#   boat-class.sh students.csv --limit 2       # only the first 2 rows (cheap test)
#   boat-class.sh students.csv --dry-run       # show the plan, create nothing
#   boat-class.sh students.csv --ttl 7200      # auto-stop after 2 h (default 3 h)
#   boat-class.sh students.csv --type default  # 4 vCPU instead of small
#   boat-class.sh students.csv --desktop       # also dark theme + 1.4x text + Chrome
#   boat-class.sh students.csv --out class.csv # where to write the result table
#   boat-class.sh students.csv --model openrouter/deepseek/deepseek-v4.1-flash-1017
#                                              # set the opencode default model on every box
#   boat-class.sh students.csv --model <id> --no-verify   # skip the 1-token smoke test
#
# The next day, use the same CSV with --start / --stop:
#   boat-class.sh students.csv --start         # resume every box in the class
#   boat-class.sh students.csv --start --ttl 7200 --desktop   # + fresh desktop URLs
#   boat-class.sh students.csv --stop          # stop them all (keeps the disk 14 days)
#   boat-class.sh students.csv --ids           # just print the sandbox ids
#   boat-class.sh students.csv --stop --snapshot end-of-day   # permanent snapshot first
# --start/--stop read the result table (<students>-sandboxes.csv) when it exists,
# and otherwise match boxes by first name / email.
#
# Input CSV: a header with firstname, lastname, email, phone (order free, , or ; )
# Output CSV: the same columns + sandbox id, ssh host, desktop URL.
#
# Safe to re-run: the idempotency key of each row is derived from its email, so a
# second run returns the same sandboxes instead of creating (and billing) new ones.
# Respects the plan's start limit: paces creates at ~1 per 6 s (10/min).

set -Eeuo pipefail

API="${BOAT_API_BASE:-https://boat.dev/api/v1}"
KEY_FILE="${BOAT_KEY_FILE:-$HOME/.secrets/boat.key}"
TEMPLATE="opencode-class"
TTL=10800; TYPE=""; LIMIT=0; DRY=0; DESKTOP=0; OUT=""; CSV=""; PACE=6
MODEL=""; VERIFY=1; MODE=""; SNAP=""

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --template) TEMPLATE="${2:?}"; shift 2 ;;
    --ttl)      TTL="${2:?}"; shift 2 ;;
    --type)     TYPE="${2:?}"; shift 2 ;;
    --limit)    LIMIT="${2:?}"; shift 2 ;;
    --pace)     PACE="${2:?}"; shift 2 ;;
    --out)      OUT="${2:?}"; shift 2 ;;
    --model)    MODEL="${2:?--model needs a model id}"; shift 2 ;;
    --no-verify) VERIFY=0; shift ;;
    --desktop)  DESKTOP=1; shift ;;
    --dry-run|-n) DRY=1; shift ;;
    --start)    MODE=start; shift ;;
    --ids)      MODE=ids; shift ;;
    --stop)     MODE=stop; shift ;;
    --snapshot) SNAP="${2:?--snapshot needs a name}"; shift 2 ;;
    -h|--help)  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    -*)         die "unknown option: $1 (try --help)" ;;
    *)          CSV="$1"; shift ;;
  esac
done
[[ -n $CSV ]] || die "give a CSV file (try --help)"
[[ -r $CSV ]] || die "cannot read $CSV"
[[ -n ${BOAT_API_KEY:-} ]] || { [[ -r $KEY_FILE ]] || die "no BOAT_API_KEY and no $KEY_FILE"; BOAT_API_KEY=$(tr -d '[:space:]' <"$KEY_FILE"); }

# ---------------------------------------------------------------- --start / --stop
# Hand off to boat-start.sh / boat-stop.sh, so there is one code path per action.
if [[ -n $MODE ]]; then
  HERE=$(dirname "$0")
  RESULT="${OUT:-${CSV%.csv}-sandboxes.csv}"
  if [[ -r $RESULT ]]; then LIST=$RESULT
  else
    warn "no result table at $RESULT — matching sandboxes by name/email"
    LIST=$CSV
  fi
  if [[ $MODE == ids ]]; then
    exec "$HERE/boat-start.sh" "$LIST" --ids
  elif [[ $MODE == start ]]; then
    args=("$LIST")
    [[ -n $TTL ]] && args+=(--ttl "$TTL")
    (( DESKTOP == 1 )) && args+=(--desktop)
    (( DRY == 1 )) && args+=(--dry-run)
    exec "$HERE/boat-start.sh" "${args[@]}"
  else
    mapfile -t ids < <("$HERE/boat-start.sh" "$LIST" --ids)
    [[ ${#ids[@]} -gt 0 ]] || die "no sandboxes found for $CSV"
    args=("${ids[@]}")
    [[ -n $SNAP ]] && args+=(--snapshot "$SNAP")
    (( DRY == 1 )) && args+=(--dry-run)
    exec "$HERE/boat-stop.sh" "${args[@]}"
  fi
fi

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

# ---------------------------------------------------------------- model helper
# Merges model/small_model into ~/.config/opencode/opencode.json. Merges, never
# replaces, so the stock mcp.computer block (desktop tools) survives.
SETMODEL=$(cat <<'SETMODEL_EOF'
import json, os, sys
m = sys.argv[1]
p = os.path.expanduser("~/.config/opencode/opencode.json")
d = json.load(open(p)) if os.path.exists(p) else {}
d["model"] = m
d["small_model"] = d.get("small_model") or m
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
print("model =", d["model"])
SETMODEL_EOF
)

# ---------------------------------------------------------------- read the CSV
# Normalise to TSV: firstname, lastname, email, phone (header names are matched
# case-insensitively and in any order; missing phone becomes empty).
STUDENTS=$(python3 - "$CSV" <<'PY'
import csv, sys
path = sys.argv[1]
raw = open(path, newline='', encoding='utf-8-sig').read()
delim = ';' if raw.count(';') > raw.count(',') else ','
rows = list(csv.reader(raw.splitlines(), delimiter=delim))
rows = [r for r in rows if any(c.strip() for c in r)]
if not rows: sys.exit("empty csv")
head = [c.strip().lower() for c in rows[0]]
def col(*names):
    for n in names:
        if n in head: return head.index(n)
    return None
i_f = col('firstname', 'first name', 'first', 'prenom', 'prénom')
i_l = col('lastname', 'last name', 'last', 'surname', 'name', 'nom')
i_m = col('email', 'e-mail', 'mail', 'courriel')
i_p = col('phone', 'phone number', 'tel', 'telephone', 'téléphone', 'mobile')
missing = [n for n, i in (('firstname', i_f), ('lastname', i_l), ('email', i_m)) if i is None]
if missing:
    sys.exit(f"csv is missing column(s): {', '.join(missing)} (found: {', '.join(head)})")
body = rows[1:]
if head == [c.strip().lower() for c in rows[0]] and not body:
    sys.exit("csv has only a header row")
for r in body:
    get = lambda i: (r[i].strip() if i is not None and i < len(r) else '')
    print('\t'.join([get(i_f), get(i_l), get(i_m), get(i_p)]))
PY
) || die "cannot parse $CSV"

mapfile -t LINES <<<"$STUDENTS"
[[ ${#LINES[@]} -gt 0 ]] || die "no student rows in $CSV"
(( LIMIT > 0 && LIMIT < ${#LINES[@]} )) && LINES=("${LINES[@]:0:$LIMIT}")

# ---------------------------------------------------------------- plan
say "plan"
ok "${#LINES[@]} student(s) from $CSV"
ok "template '$TEMPLATE' · type ${TYPE:-template default} · auto-stop $((TTL/60)) min · pace ${PACE}s"
[[ -n $MODEL ]] && ok "model override: $MODEL" || ok "model: whatever the template sets"
PRE=$(api GET "/sandboxes"?limit=1 >/dev/null 2>&1 || true)
CAN=$(api GET /limits | jq -r '.canStart')
REMAIN=$(api GET /limits | jq -r '.starts.minute.remaining')
[[ $CAN == true ]] || die "canStart=false — a plan limit blocks creates right now"
ok "starts left this minute: $REMAIN"
(( ${#LINES[@]} <= 12 )) || warn "more than 12 starts: it will pace itself over ~$(( ${#LINES[@]} * PACE / 60 )) min"

if [[ $DRY -eq 1 ]]; then
  printf '\n    %-12s %-14s %-30s %s\n' FIRSTNAME LASTNAME EMAIL PHONE
  for l in "${LINES[@]}"; do IFS=$'\t' read -r f n m p <<<"$l"; printf '    %-12s %-14s %-30s %s\n' "$f" "$n" "$m" "$p"; done
  say "dry run — nothing created"
  exit 0
fi

# ---------------------------------------------------------------- create
[[ -n $OUT ]] || OUT="${CSV%.csv}-sandboxes.csv"
printf 'firstname,lastname,email,phone,sandbox_id,ssh_endpoint,desktop_url\n' >"$OUT"
say "creating"
i=0; failed=0
for l in "${LINES[@]}"; do
  IFS=$'\t' read -r first last mail phone <<<"$l"
  i=$((i+1))
  label="$first $last"
  body=$(jq -cn --arg from "$TEMPLATE" --argjson ttl "$TTL" --arg name "$label" --arg type "$TYPE" '
    {from:$from, ttlSeconds:$ttl, name:$name} + (if $type == "" then {} else {type:$type} end)')

  # stable per-student key: same email + same body -> same sandbox on a re-run.
  # Changing a flag (--ttl, --type) yields a new key, so a re-run is not refused.
  idem="class-$(printf '%s\n%s' "${mail:-$label}" "$body" | tr 'A-Z' 'a-z' | md5sum | cut -c1-24)"

  if ! res=$(api POST /sandboxes -H 'Content-Type: application/json' \
             -H "Idempotency-Key: $idem" --data-binary "$body"); then
    warn "[$i/${#LINES[@]}] $label — create failed, skipping"; failed=$((failed+1)); continue
  fi
  id=$(jq -r '.sandbox.id' <<<"$res")
  printf '    [%d/%d] %-20s %s\n' "$i" "${#LINES[@]}" "$label" "$id"

  # wait for it, then personalise the workspace
  st=""
  for _ in $(seq 1 60); do
    st=$(api GET "/sandboxes/$id" | jq -r '.sandbox.state')
    case $st in ready|idle|running) break ;; error) break ;; esac
    sleep 2
  done
  if [[ $st == error ]]; then warn "  $id is in error state — skipping"; failed=$((failed+1)); continue; fi
  rowfail=0

  if [[ -n $MODEL ]]; then
    jq -cn --arg c "$SETMODEL" '{path:"/home/user/.boat/set-model.py",content:$c}' \
      | api PUT "/sandboxes/$id/files" -H 'Content-Type: application/json' --data-binary @- >/dev/null \
      || { warn "  could not upload the model helper"; failed=$((failed+1)); continue; }
    got=$(api POST "/sandboxes/$id/commands" -H 'Content-Type: application/json' \
            --data-binary "$(jq -cn --arg m "$MODEL" \
              '{command:("python3 ~/.boat/set-model.py " + ($m|@sh)), timeoutSeconds:60}')" \
          | jq -r '.stdout' | tr -d '\n') || { warn "  setting the model failed"; failed=$((failed+1)); continue; }
    ok "  $got"

    if [[ $VERIFY -eq 1 ]]; then
      smoke=$(api POST "/sandboxes/$id/commands" -H 'Content-Type: application/json' \
        --data-binary "$(jq -cn '{command:"cd ~/work && opencode run \"Reply with exactly: MODELOK\" 2>/dev/null", timeoutSeconds:180}')" \
        | jq -r '.stdout')
      if grep -q MODELOK <<<"$smoke"; then ok "  smoke test passed ($MODEL)"
      else warn "  smoke test FAILED — the model may not be available: $(head -c 120 <<<"$smoke")"
           failed=$((failed+1)); rowfail=1; fi
    fi
  fi

  readme=$(cat <<EOF
# Welcome, $first

Your sandbox is **$id**. You are on a full Ubuntu VM; \`opencode\` is installed and logged in.
Start here:

    cd ~/work && opencode

Type a task in plain English, \`Tab\` to switch Plan/Build, \`/help\` for commands.
Your files survive a stop and resume. \`~/work/README.md\` has the full cheat sheet.
EOF
)
  jq -cn --arg p "/home/user/work/WELCOME.md" --arg c "$readme" '{path:$p,content:$c}' \
    | api PUT "/sandboxes/$id/files" -H 'Content-Type: application/json' --data-binary @- >/dev/null || warn "  could not write WELCOME.md"

  ssh_ep=$(api GET "/sandboxes/$id" | jq -r '.sandbox.sshEndpoint // ""')

  if [[ $DESKTOP -eq 1 ]]; then
    "$(dirname "$0")/boat-desktop.sh" "$id" >/dev/null 2>&1 || warn "  desktop setup failed"
  fi
  durl=$(api POST "/sandboxes/$id/desktop" | jq -r '.desktopUrl // ""' 2>/dev/null || echo "")

  printf '%s,%s,%s,%s,%s,%s,%s\n' "$first" "$last" "$mail" "$phone" "$id" "$ssh_ep" "$durl" >>"$OUT"
  if [[ $rowfail -eq 0 ]]; then ok "  ready ($st)"; else warn "  box exists ($id) but MODEL VERIFY FAILED"; fi
  sleep "$PACE"
done

say "done"
ok "$(( ${#LINES[@]} - failed ))/${#LINES[@]} sandboxes ready · table: $OUT"
(( failed == 0 )) || warn "$failed row(s) failed — re-run the same command, it resumes"
printf '\n    stop them all later:  boat-stop.sh %s\n' "$(cut -d, -f5 "$OUT" | tail -n +2 | tr '\n' ' ')"
printf '    give students:        ssh <id>@boat.dev   or the desktop_url column\n'
printf '    desktop links expire after 10 min: re-run with --desktop to refresh\n'
