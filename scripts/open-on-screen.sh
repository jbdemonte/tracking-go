#!/usr/bin/env bash
# ============================================================
# open-on-screen.sh (X11 kiosk launcher)
# ------------------------------------------------------------
# Usage:
#   ./open-on-screen.sh <monitor_index> <browser> <url>
#
# Examples:
#   ./open-on-screen.sh 1 brave http://localhost:8080
#   ./open-on-screen.sh 2 chrome https://example.com
#   ./open-on-screen.sh 1 firefox https://mozilla.org
#
# Requirements: xrandr, wmctrl, xdotool
# ============================================================
set -euo pipefail

err(){ echo "[ERROR] $*" >&2; exit 1; }
info(){ echo "[INFO] $*" >&2; }

[[ $# -ge 3 ]] || err "Usage: $0 <monitor_index> <browser> <url>"
MON_IDX_1B="$1"; shift
BROWSER_IN="$1"; shift
URL="$1"; shift || true

# ------------------------------------------------------------
# Dependencies check
# ------------------------------------------------------------
for c in xrandr xdotool wmctrl; do
  command -v "$c" >/dev/null 2>&1 || err "$c not found (sudo apt install x11-xserver-utils xdotool wmctrl)"
done

# ------------------------------------------------------------
# Force X11 environment (avoid Wayland/Keyring issues)
# ------------------------------------------------------------
export -n WAYLAND_DISPLAY || true
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export OZONE_PLATFORM=x11
export MOZ_ENABLE_WAYLAND=0
export MOZ_DISABLE_WAYLAND=1

# ------------------------------------------------------------
# Monitor geometry detection via xrandr
# ------------------------------------------------------------
MON_CNT=$(xrandr --listmonitors | awk 'NR==1{print $2}')
(( MON_IDX_1B >= 1 && MON_IDX_1B <= MON_CNT )) || err "monitor_index out of range (1..$MON_CNT)"
MON_IDX_0B=$(( MON_IDX_1B - 1 ))

LINE=$(xrandr --listmonitors | awk -v idx="$MON_IDX_0B" 'NR>1 { split($1,a,":"); if (a[1]==idx){print; exit} }')
GEOM=$(awk '{print $(NF-1)}' <<<"$LINE")
NAME=$(awk '{print $NF}' <<<"$LINE")
read -r W H X Y < <(sed -E 's#([0-9]+)/[0-9]+x([0-9]+)/[0-9]+\+([0-9]+)\+([0-9]+)#\1 \2 \3 \4#' <<<"$GEOM")

info "Monitor[$MON_IDX_1B] = $NAME, geometry=${W}x${H}+${X}+${Y}"

# ------------------------------------------------------------
# Browser command builder
# ------------------------------------------------------------
PROFILE_DIR="$HOME/.kiosk-$BROWSER_IN-$MON_IDX_1B"
mkdir -p "$PROFILE_DIR"

# Find binary
case "$BROWSER_IN" in
  brave|brave-browser)
    BROWSER_BIN=$(command -v brave-browser || command -v brave || true)
    ;;
  chrome|google-chrome)
    BROWSER_BIN=$(command -v google-chrome || command -v google-chrome-stable || true)
    ;;
  chromium|chromium-browser)
    BROWSER_BIN=$(command -v chromium || command -v chromium-browser || true)
    ;;
  firefox)
    BROWSER_BIN=$(command -v firefox || true)
    ;;
  *)
    err "Unknown browser: $BROWSER_IN (supported: brave, chrome, chromium, firefox)"
    ;;
esac
[[ -n "$BROWSER_BIN" ]] || err "Browser not found: $BROWSER_IN"

# ------------------------------------------------------------
# Disable Brave P3A analytics banner (privacy prompt)
# ------------------------------------------------------------
if [[ "$BROWSER_IN" =~ ^(brave|brave-browser)$ ]]; then
  mkdir -p "$PROFILE_DIR/Default"
  cat >"$PROFILE_DIR/Local State" <<'JSON'
{
  "brave": {
    "p3a": {
      "enabled": false,
      "notice_acknowledged": true
    }
  }
}
JSON
  cat >"$PROFILE_DIR/Default/Preferences" <<'JSON'
{
  "brave": {
    "p3a": {
      "enabled": false,
      "notice_acknowledged": true
    }
  }
}
JSON
fi

# ------------------------------------------------------------
# Generate final browser command
# ------------------------------------------------------------
case "$BROWSER_IN" in
  brave|brave-browser)
    BROWSER_CMD="$BROWSER_BIN \
      --kiosk --new-window --start-fullscreen \
      --no-first-run --no-default-browser-check --disable-infobars \
      --password-store=basic \
      --user-data-dir=\"$PROFILE_DIR\" \
      --ozone-platform=x11 \
      --disable-background-networking \
      --disable-component-update \
      --disable-sync \
      --disable-features=TranslateUI \
      --hide-crash-restore-bubble"
    ;;
  chrome|google-chrome|chromium|chromium-browser)
    BROWSER_CMD="$BROWSER_BIN \
      --kiosk --new-window --start-fullscreen \
      --no-first-run --no-default-browser-check --disable-infobars \
      --password-store=basic \
      --user-data-dir=\"$PROFILE_DIR\" \
      --ozone-platform=x11 \
      --disable-background-networking \
      --disable-component-update \
      --disable-sync \
      --disable-features=TranslateUI \
      --hide-crash-restore-bubble"
    ;;
  firefox)
    BROWSER_CMD="$BROWSER_BIN --kiosk --new-window --profile \"$PROFILE_DIR\" --no-remote"
    ;;
esac

# ------------------------------------------------------------
# Launch browser process
# ------------------------------------------------------------
info "Launching $BROWSER_IN on monitor $MON_IDX_1B..."
setsid bash -c "$BROWSER_CMD \"$URL\"" >/dev/null 2>&1 &
PID=$!

# ------------------------------------------------------------
# Wait for the browser window to appear
# ------------------------------------------------------------
WIN_ID=""
for _ in $(seq 1 40); do
  WIN_ID=$(xdotool search --onlyvisible --pid "$PID" 2>/dev/null | head -n1 || true)
  [[ -n "$WIN_ID" ]] && break
  for p in $(pgrep -P "$PID" || true); do
    WIN_ID=$(xdotool search --onlyvisible --pid "$p" 2>/dev/null | head -n1 || true)
    [[ -n "$WIN_ID" ]] && break
  done
  [[ -n "$WIN_ID" ]] && break
  sleep 0.5
done
[[ -n "$WIN_ID" ]] || err "Unable to detect browser window."

# ------------------------------------------------------------
# Move and resize window to target monitor
# ------------------------------------------------------------
wmctrl -i -r "$WIN_ID" -e "0,${X},${Y},${W},${H}" || true
wmctrl -i -r "$WIN_ID" -b add,fullscreen || true

info "✅ $BROWSER_IN launched on $NAME (${W}x${H})"