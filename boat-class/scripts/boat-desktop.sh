#!/usr/bin/env bash
# boat-desktop.sh — give one or more boat sandboxes a dark, readable desktop
# and open a web page in Chrome, then print the desktop URLs.
#
#   boat-desktop.sh <id> [id…]            # dark, 1.4x text, example.com
#   boat-desktop.sh <id> --scale 1.8      # bigger text
#   boat-desktop.sh <id> --light --scale 1
#   boat-desktop.sh <id> --url https://github.com
#   boat-desktop.sh <id> --accent '#f78166'
#   boat-desktop.sh <id> --resume         # resume it first if it is stopped
#   boat-desktop.sh <id> --delete         # stop + delete it afterwards
#
# Reads the key from $BOAT_API_KEY, else ~/.secrets/boat.key.
# Everything it changes lives on the sandbox disk, so it survives stop/resume
# except Chrome's --force-device-scale-factor, which is per launch: re-run this
# after a resume.

set -Eeuo pipefail

API="${BOAT_API_BASE:-https://boat.dev/api/v1}"
KEY_FILE="${BOAT_KEY_FILE:-$HOME/.secrets/boat.key}"
SCALE=1.4; URL="https://example.com"; THEME=dark; ACCENT="#58a6ff"
RESUME=0; DELETE=0; IDS=()

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --scale)  SCALE="${2:?}"; shift 2 ;;
    --url)    URL="${2:?}"; shift 2 ;;
    --light)  THEME=light; shift ;;
    --dark)   THEME=dark; shift ;;
    --accent) ACCENT="${2:?}"; shift 2 ;;
    --resume) RESUME=1; shift ;;
    --delete) DELETE=1; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *)  IDS+=("$1"); shift ;;
  esac
done
[[ ${#IDS[@]} -gt 0 ]] || die "give at least one sandbox id (boat list)"

[[ -n ${BOAT_API_KEY:-} ]] || { [[ -r $KEY_FILE ]] || die "no BOAT_API_KEY and no $KEY_FILE"; BOAT_API_KEY=$(tr -d '[:space:]' <"$KEY_FILE"); }

api() {   # api METHOD PATH [curl args…] -> body; dies on HTTP >= 300
  local m=$1 p=$2 out http; shift 2
  out=$(mktemp)
  http=$(curl -sS -o "$out" -w '%{http_code}' -X "$m" "$API$p" \
          -H "Authorization: Bearer $BOAT_API_KEY" -H 'Accept: application/json' "$@") \
       || { rm -f "$out"; die "curl failed: $m $p"; }
  if (( http >= 300 )); then
    local c msg; c=$(jq -r '.code // "?"' "$out" 2>/dev/null); msg=$(jq -r '.message // ""' "$out" 2>/dev/null)
    rm -f "$out"; return 2
  fi
  cat "$out"; rm -f "$out"
}

# ---------------------------------------------------------------- what runs inside
# Kept in one heredoc so this file stays a single, self-contained command.
REMOTE=$(cat <<'REMOTE_EOF'
#!/usr/bin/env bash
# desktop-setup.sh SCALE URL THEME ACCENT  — run inside a boat sandbox
set -u
export DISPLAY=:0
SCALE="${1:-1.4}"; URL="${2:-https://example.com}"; THEME="${3:-dark}"; ACCENT="${4:-#58a6ff}"
px() { python3 -c "print(max(1,round($1*$SCALE)))"; }
UI=$(px 11); DPI=$(px 96); OBF=$(px 10)

if [[ $THEME == dark ]]; then
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
  WALL=/usr/share/backgrounds/Numbat_wallpaper_dimmed_3480x2160.png
else
  gsettings set org.gnome.desktop.interface color-scheme 'default'
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
  WALL=/usr/share/backgrounds/Fuji_san_by_amaral.png
fi

# text size: GTK, X resources, Openbox titles, terminal
gsettings set org.gnome.desktop.interface text-scaling-factor "$SCALE"
gsettings set org.gnome.desktop.interface font-name "Cantarell $UI"
gsettings set org.gnome.desktop.interface document-font-name "Cantarell $UI"
gsettings set org.gnome.desktop.interface monospace-font-name "DejaVu Sans Mono $UI"
gsettings set org.gnome.desktop.background picture-uri "file://$WALL"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALL"

printf 'Xft.dpi: %s\nXft.antialias: true\nXft.hinting: true\nXft.rgba: rgb\n' "$DPI" > ~/.Xresources
xrdb -merge ~/.Xresources

OBXML=/usr/local/share/ascii-desktop/openbox.xml
sudo test -f "$OBXML.orig" || sudo cp "$OBXML" "$OBXML.orig"
sudo sed -E -i "s|<size>[0-9]+</size>|<size>$OBF</size>|g" "$OBXML"
openbox --reconfigure 2>/dev/null || true

CFG=~/.config/ghostty/config.ghostty
mkdir -p ~/.config/ghostty; touch "$CFG"
sed -i '/^[[:space:]]*font-size[[:space:]]*=/d' "$CFG"
echo "font-size = $UI" >> "$CFG"

# dark wallpaper with a label, painted by the boat desktop shell
if [[ $THEME == dark ]]; then
  mkdir -p ~/.config/boat
  convert -size 1920x1080 gradient:'#0a0d12-#1b2130' \
    -fill "$ACCENT" -pointsize "$(px 60)" -gravity center -annotate +0-40 "$(hostname)" \
    -fill '#8b949e' -pointsize "$(px 22)" -gravity center -annotate +0+70 "dark desktop · $URL" \
    ~/.config/boat/wallpaper.png 2>/dev/null || true
fi

# Chrome: one flag scales tabs, address bar and page together
pkill -f '/opt/google/chrome/chrome' 2>/dev/null; sleep 2
nohup google-chrome --force-device-scale-factor="$SCALE" \
  --force-dark-mode --enable-features=WebContentsForceDark \
  --no-first-run --no-default-browser-check --disable-gcm-registration \
  --password-store=basic --disable-dev-shm-usage \
  --new-window "$URL" >/tmp/chrome.log 2>&1 &
sleep 7
wmctrl -r "Chromium" -b add,maximized_vert,maximized_horz 2>/dev/null || true

printf 'scale=%s theme=%s ui-font=%s dpi=%s titlebar=%s chrome=factor:%s window=%s\n' \
  "$SCALE" "$THEME" "$UI" "$DPI" "$OBF" "$SCALE" \
  "$(wmctrl -l | grep -ci chromium) chrome window(s)"
REMOTE_EOF
)

STAGE=0
cleanup() {
  local rc=$?; set +e
  if [[ $DELETE -eq 1 ]]; then
    local id
    for id in "${READY[@]:-}"; do
      [[ -z $id ]] && continue
      api POST "/sandboxes/$id/stop" >/dev/null 2>&1 || true
      for _ in $(seq 1 20); do
        [[ $(curl -sS "$API/sandboxes/$id" -H "Authorization: Bearer $BOAT_API_KEY" | jq -r '.sandbox.state // "?"') == archived ]] && break
        sleep 2
      done
      api DELETE "/sandboxes/$id" -H "X-Ascii-Confirm-Delete: $id" >/dev/null 2>&1 || true
      printf '    deleted %s\n' "$id"
    done
  fi
  exit $rc
}
trap cleanup EXIT INT TERM
READY=()

for id in "${IDS[@]}"; do
  say "$id"
  st=$(api GET "/sandboxes/$id" | jq -r '.sandbox.state') || die "cannot read $id (bad id, or not your sandbox?)"
  if [[ $st == archived ]]; then
    if [[ $RESUME -eq 1 ]]; then
      api POST "/sandboxes/$id/resume" >/dev/null || die "resume failed"
      ok "resuming…"
      for _ in $(seq 1 60); do
        st=$(api GET "/sandboxes/$id" | jq -r '.sandbox.state')
        case $st in ready|idle|running) break ;; esac
        sleep 2
      done
    else
      warn "$id is stopped — add --resume to bring it back"; continue
    fi
  fi
  case $st in
    ready|idle|running) ;;
    *) warn "$id is '$st' — not usable right now"; continue ;;
  esac
  ok "state: $st"

  # upload the setup script (JSON body: {"path":…,"content":…})
  jq -cn --arg p "/home/user/.boat/desktop-setup.sh" --arg c "$REMOTE" '{path:$p,content:$c}' \
    | api PUT "/sandboxes/$id/files" -H 'Content-Type: application/json' --data-binary @- >/dev/null
  ok "setup script uploaded"

  res=$(api POST "/sandboxes/$id/commands" -H 'Content-Type: application/json' \
        -d "$(jq -cn --arg s "$SCALE" --arg u "$URL" --arg t "$THEME" --arg a "$ACCENT" \
              '{command:("bash ~/.boat/desktop-setup.sh " + ($s|@sh) + " " + ($u|@sh) + " " + ($t|@sh) + " " + ($a|@sh)), timeoutSeconds:240}')") \
        || die "setup failed on $id"
  ok "$(jq -r '.stdout' <<<"$res" | tr -d '\n')"

  url=$(api POST "/sandboxes/$id/desktop?theme=$THEME" | jq -r '.desktopUrl') || { warn "no desktop URL (is the machine running?)"; continue; }
  printf '    \033[1m%s\033[0m\n' "$url"
  READY+=("$id")
done

say "done"
[[ ${#READY[@]} -gt 0 ]] && printf '    %d desktop(s) ready · open a URL within 10 minutes\n' "${#READY[@]}"
printf '    change size later: boat-desktop.sh %s --scale 1.8\n' "${READY[0]:-<id>}"
