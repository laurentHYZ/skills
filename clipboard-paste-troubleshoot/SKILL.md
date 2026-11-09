---
name: clipboard-paste-troubleshoot
description: Use when copying between the Windows desktop and a WSL/GUI or terminal Emacs instance (or between tmux/herdr tabs) and paste yields stale, empty, or wrong text. Walks through the layered clipboard registers (Emacs kill-ring, tmux/herdr buffer, X/Wayland selection, wslg, Windows clipboard) and gives concrete tests and fixes. Trigger on "pastes old content", "paste does nothing", "clipboard doesn't work in Emacs", "copy from desktop, paste in WSL Emacs".
---

# Clipboard paste troubleshooting (Desktop ↔ WSL Emacs)

A "clipboard" is not one thing. Copy/paste crosses several independent
registers. A stale or empty paste almost always means the copy and paste sides
touched *different* registers.

## The register stack (know which one you're on)

| Layer | Owner | Notes |
|---|---|---|
| Emacs kill-ring | Emacs internal | `M-w`, `C-w`. Purely internal unless bridged out. |
| tmux / herdr paste buffer | multiplexer | `prefix ]` pastes *its* buffer, **not** the OS clipboard. |
| X11 selection | X server | `CLIPBOARD` vs `PRIMARY` are separate. |
| Wayland clipboard | compositor | wl-clipboard (`wl-copy`/`wl-paste`). |
| wslg bridge | WSLg | lets X/Wayland apps in WSL see the *Windows* clipboard. |
| Windows clipboard | Win32 | what Desktop apps and Windows Terminal use. |

Path on WSL: Windows clipboard ──wslg──▶ X/Wayland in WSL ──▶ GUI Emacs,
or ──▶ terminal Emacs *only if* it shells out to a CLI clipboard tool.

## Fast diagnosis

1. **Which register did the paste come from?** Paste into a scratch buffer in
   the target app, then compare:
   - `C-y` in Emacs → kill-ring
   - `prefix ]` in tmux/herdr → multiplexer buffer
   - `C-S-v` in terminal → OS clipboard
   Pick the one that has your *new* text; that's the side that's broken.
2. **Terminal Emacs + `M-w`:** `M-w` usually does **not** reach the OS
   clipboard. So `C-S-v` in another terminal pastes whatever was there before —
   exactly the "previously copied content" symptom. Fix: use terminal copy
   (`C-S-c` / mouse selection) or `M-x clipboard-kill-ring-save`.
3. **Multiplexer confusion:** tmux/herdr `prefix ]` never sees the OS
   clipboard. Use terminal paste (`C-S-v`), or sync tmux to the system clipboard.

## Concrete checks

```bash
# Is there an X/Wayland clipboard owner at all? (headless VPS = no)
echo "$DISPLAY $WAYLAND_DISPLAY"; xclip -o -selection clipboard 2>&1 | head
wl-paste 2>&1 | head

# Does WSL see the Windows clipboard?
powershell.exe -NoProfile -Command "Get-Clipboard" | head -5
# Push text to Windows clipboard from WSL:
printf 'hello' | clip.exe
```

- `Get-Clipboard` shows the text but Emacs doesn't → fix lives in Emacs
  (bridge missing) — see below.
- `Get-Clipboard` is *also* stale → the problem is upstream of WSL (browser,
  desktop app, or wslg), not Emacs.

## Fixes, by case

**GUI Emacs on WSL (wslg)** — x-select integration should work; verify
`(display-graphic-p)` is `t`, `select-enable-clipboard` is `t`, and WSLg's X is
reachable (`$DISPLAY` set, usually `:0`).

**Terminal Emacs (`emacs -nw`) in WSL / tmux / herdr** — Emacs cannot touch the
OS clipboard by itself. Bridge it:

```elisp
;; route kill/yank through wl-clipboard (GUI-less Wayland) or xclip
(setq select-enable-clipboard t)
(defun my/yank-from-os ()
  (interactive)
  (let ((txt (string-trim-right
              (shell-command-to-string
               (if (getenv "WAYLAND_DISPLAY") "wl-paste -n" "xclip -o -selection clipboard")))))
    (kill-new txt) (insert txt)))
(global-set-key (kbd "C-S-v") #'my/yank-from-os)
```

Or, cheap and always works: in WSL, `clip.exe` (write) and
`powershell.exe Get-Clipboard` (read) cross the boundary with no X/Wayland at
all — good fallback on a headless VPS where there is no clipboard owner
(bind `wl-copy` / `xclip -selection clipboard` to a kill function).

**tmux** — `set -g set-clipboard on` plus terminal OSC 52 support; paste with
`C-S-v` for OS clipboard, `prefix ]` for tmux buffer. Same idea for herdr.

**Avoid the round-trip** — when both sides are the same machine (VPS, tabs in
one session), just type/run the command directly in the other tab, or use
`vterm` in Emacs (`C-S-v` there goes through the terminal, not kill-ring).

## Rule of thumb

Copy side and paste side must use the **same register**. `M-w` → Emacs;
`prefix ]` → multiplexer; `C-S-v` → OS clipboard. If they don't match, the
paste is stale by design, not a bug.
