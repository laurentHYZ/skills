# boat.dev API notes (verified against the live API)

Base `https://boat.dev/api/v1`, `Authorization: Bearer boat_…`. Every response is
`{ok, type, …}`; failures add `status`, `code`, `message`, `requestId`. `ok:false` comes with
an HTTP status ≥ 400, so check the status, not just the body.

## Endpoints actually used here

| Call | Notes |
|---|---|
| `GET /me`, `GET /limits` | identity, `canStart`, `starts.{minute,hour,day}.remaining`, `planIncluded.vmHoursRemaining` |
| `POST /sandboxes` | body `{from?, ttlSeconds?, type?, name?, env?}`; `ttlSeconds:null` = no auto-stop. Send `Idempotency-Key` or a lost 5xx can bill twice |
| `GET /sandboxes/{id}` | `.sandbox.state` ∈ provisioning, provisioned, cloning, ready, idle, running, archiving, archived, error |
| `POST /sandboxes/{id}/resume` | body `{ttlSeconds?}`, or `{failFast:true}` to refuse queuing instead of waiting |
| `POST /sandboxes/{id}/stop` | 202 `sandbox.stopping`; poll until `archived`. Stopped = `archived` in the API, "stopped" in the CLI |
| `DELETE /sandboxes/{id}` | needs header `X-Ascii-Confirm-Delete: <id>`; 202 `sandbox.deleting`, not cancellable |
| `GET /sandboxes/{id}/usage` | `{seconds, dollars, running}` |
| `PATCH /sandboxes/{id}` | `{name}` (≤120 chars, unicode ok) or `{ttlSeconds}` to extend |
| `POST /sandboxes/{id}/commands` | `{command, timeoutSeconds?, detached?, stream?}`; sync default 30 s, max 600 s; detached → `processId`, no limit |
| `PUT /sandboxes/{id}/files` | **JSON body** `{path, content}` — not a query param, not raw body |
| `GET /sandboxes/{id}/files?path=…` | `{size, content, encoding}` |
| `POST /sandboxes/{id}/host` | `{port, public?}` → `{url}` `https://…-8000.on.boat.dev` |
| `POST /sandboxes/{id}/desktop` | query `?theme=dark` (only `dark` or `light`; `auto`/other → 400 `invalid_theme`) or `?vnc=1`; body `{publicAccess?}`; returns `desktopUrl` |
| `POST /saved-snapshots` | `{name, sandboxId}` → 202 `snapshot.saved.saving`; poll `GET /saved-snapshots/{name}` for `.snapshot.status == ready` |
| `GET /saved-snapshots` | payload key is **`.snapshots`**, not `.savedSnapshots` |
| `DELETE /saved-snapshots/{name}` | |
| `POST /api-keys/scoped` | `{name, actions[], sandboxes[] | "*", environments[], ttl}`; secret returned once |
| `DELETE /api-keys/{id}` | revoke |
| `POST /sandboxes/{id}/prompt` | `{provider, prompt, new?|conversationId?, model?}`; read `GET /sandboxes/{id}/events` |

Not usable with a scoped key without the matching action: `GET /provider-models` returned
`403 api_key_action_forbidden` for an admin key built from `/api-keys/scoped` — treat that
endpoint as best-effort.

## Gotchas that cost real time

1. **`jq -r` on a string keeps the quotes.** `jq -r .sandbox.id` is fine, but piping a
   quoted value without `-r` gives `"bx_…"` and every URL built from it 404s. Extract scalars
   with `jq -r`, always.
2. **`--ids`-style machine output must go to stdout only.** A friendly "5 sandboxes so far"
   message on stdout became a sandbox id in a downstream loop. Send human chatter to stderr.
3. **Validate ids before calling the API.** `^(bx|box)_[A-Za-z0-9]+$`. Anything else is a
   CSV column shift; skip it with a warning instead of failing the whole run.
4. **Idempotency keys are global per account per body.** Deriving the key from the email
   alone breaks the moment a flag changes (`--ttl`, `--type`): 409 `idempotency_key_reused`.
   Derive it from email + canonical request body.
5. **`archiving` is not `archived`.** Resuming a box caught mid-stop fails. Wait for
   `archived`, then resume.
6. **Desktop URLs are short-lived.** 10 minutes to open; an open stream survives that. List
   and info responses never cache one, so fetch fresh on each use.
7. **`theme=dark` styles boat's viewer only.** Content darkness comes from inside the box:
   `gsettings set org.gnome.desktop.interface color-scheme prefer-dark` and
   `gtk-theme Adwaita-dark`, plus a dark wallpaper at `~/.config/boat/wallpaper.png` (the
   `ascii-desktop` shell repaints when that file changes).
8. **Text size is five independent knobs**, not one: gsettings `font-name` +
   `text-scaling-factor`, `Xft.dpi` in `~/.Xresources` (then `xrdb -merge`), Openbox titlebar
   `<size>` in `/usr/local/share/ascii-desktop/openbox.xml` (+ `openbox --reconfigure`,
   **never** `--replace` — it kills the session), and Chrome's
   `--force-device-scale-factor=N`. Chrome's flag is per launch, so re-apply after a resume.
9. **opencode config must be merged, not replaced.** `~/.config/opencode/opencode.json` holds
   the `mcp.computer` block that gives the agent eyes and hands on the desktop. Set
   `model` / `small_model` keys with a JSON merge.
10. **Model ids inside a box need the router prefix**: `openrouter/deepseek/deepseek-v4.1-flash-1017`.
    Without it: `Error: The requested model is not supported`.
11. **CRLF and BOM**: files edited on Windows work if parsed with `csv` + `utf-8-sig`; a naive
    `cut -d,` loop does not.
12. **Per-box keys named `box-machine`** appear in the key list; they belong to the sandbox and
    vanish when it is deleted. Don't revoke them by hand.
13. **`--all` is dangerous**: it resumes every stopped sandbox in the account, including old
    experiments. Prefer a CSV.

## Costs (for sanity checks)

`small` 2 vCPU/4 GB $0.018/h · `default` 4/8 $0.036/h · `large` 8/16 $0.072/h ·
`xlarge` 16/32 $0.20/h (needs the $100 plan). A 2 h lesson with 5 `small` boxes ≈ $0.18.
A full month of one `default` box ≈ $26.

## Relationship to the CLI

Everything here is also reachable with the CLI (`boat new`, `boat exec <id>`, `boat stop`,
`boat resume`, `boat rename`, `boat snapshot`, `boat desktop`), except: `boat resume` takes
one id at a time, and `boat list` shows `stopped` where the API says `archived`.
