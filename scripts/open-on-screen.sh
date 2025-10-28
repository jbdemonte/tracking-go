#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------
# open-on-screen-fullscreen.sh  (Wayland-aware)
# -----------------------------------------------
# Usage: ./open-on-screen-fullscreen.sh <url> [output_name] [browser_alias]
# - browser_alias accepted: chrome, chromium, brave, vivaldi, edge, firefox
# Behavior:
# - X11 (or FORCE_X11=1): place window on target output with wmctrl, then fullscreen
# - Wayland (default): launch in --kiosk (no window control under Wayland)
#
# Env:
#   FORCE_X11=1  -> Under Wayland, run browser via XWayland and use wmctrl.
#
# NOTE: Comments in English as requested.

die() { echo "Error: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found. Install it first."; }
have() { command -v "$1" >/dev/null 2>&1; }

URL="${1:-}"
TARGET_OUT="${2:-}"          # e.g., HDMI-2 or DP-1; if empty, first connected
USER_BROWSER_ALIAS="${3:-}"  # e.g., chrome | brave | edge | firefox | chromium | vivaldi

[[ -n "${URL}" ]] || die "Usage: $0 <url> [output_name] [browser_alias]"

SESSION_TYPE="${XDG_SESSION_TYPE:-}"
FORCE_X11="${FORCE_X11:-0}"

is_wayland=0
[[ "${SESSION_TYPE}" == "wayland" ]] && is_wayland=1

# ---------- Alias -> (binary, wm_class) ----------
map_alias() {
  local alias="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$alias" in
    "" ) echo "" ""; return 0;;
    chrome|google-chrome|chrome-browser|google-chrome-stable) echo "google-chrome google-chrome";;
    brave|brave-browser)                                      echo "brave-browser brave-browser";;
    edge|microsoft-edge)                                      echo "microsoft-edge microsoft-edge";;
    vivaldi)                                                  echo "vivaldi vivaldi";;
    chromium|chromium-browser)                                echo "chromium chromium";;
    firefox)                                                  echo "firefox firefox";;
    * ) echo "$alias" "$alias";;
  esac
}

# ---------- Pick browser ----------
PREFERRED_BROWSERS=( google-chrome chromium chromium-browser brave-browser vivaldi microsoft-edge firefox )

CHOSEN="" CLASS_MATCH=""
if [[ -n "$USER_BROWSER_ALIAS" ]]; then
  read -r BIN CCLASS < <(map_alias "$USER_BROWSER_ALIAS")
  [[ -n "$BIN" ]] || die "Invalid browser alias."
  have "$BIN" || die "Requested browser '$USER_BROWSER_ALIAS' mapped to '$BIN' but not found in PATH."
  CHOSEN="$BIN"; CLASS_MATCH="$CCLASS"
else
  for b in "${PREFERRED_BROWSERS[@]}"; do
    if have "$b"; then
      CHOSEN="$b"
      case "$b" in
        google-chrome) CLASS_MATCH="google-chrome" ;;
        brave-browser) CLASS_MATCH="brave-browser" ;;
        microsoft-edge) CLASS_MATCH="microsoft-edge" ;;
        vivaldi) CLASS_MATCH="vivaldi" ;;
        chromium|chromium-browser) CLASS_MATCH="chromium" ;;
        firefox) CLASS_MATCH="firefox" ;;
        *) CLASS_MATCH="$b" ;;
      esac
      break
    fi
  done
  [[ -n "$CHOSEN" ]] || die "No supported browser found (tried: ${PREFERRED_BROWSERS[*]})."
fi

# ---------- Profiles per output ----------
BASE_PROF="$HOME/.browser-per-output"
mkdir -p "$BASE_PROF"
SAFE_OUT="$(echo "${TARGET_OUT:-default}" | tr '/' '_' )"
PROFILE_DIR="$BASE_PROF/${CHOSEN}_${SAFE_OUT}"
mkdir -p "$PROFILE_DIR"

# ---------- Firefox auto media allow ----------
prepare_firefox_userjs() {
  local pdir="$1"
  mkdir -p "$pdir"
  cat > "$pdir/user.js" <<'EOF'
user_pref("media.navigator.permission.disabled", true);
user_pref("permissions.default.camera", 1);
user_pref("permissions.default.microphone", 1);
user_pref("media.navigator.streams.fake", false);
EOF
}

# ---------- Should we use X11 control path? ----------
use_x11_ctrl=0
if (( FORCE_X11 == 1 )); then
  use_x11_ctrl=1
elif (( is_wayland == 0 )); then
  use_x11_ctrl=1
fi

# ---------- If using X11 control: need xrandr & wmctrl ----------
if (( use_x11_ctrl == 1 )); then
  need xrandr
  need wmctrl
  if ! xrandr --query >/dev/null 2>&1; then
    warn "xrandr can't open display. Falling back to Wayland-safe kiosk mode."
    use_x11_ctrl=0
  fi
fi

# ---------- Resolve geometry (X11 path only) ----------
W=""; H=""; OFFSET_X=""; OFFSET_Y=""; GEOM=""
if (( use_x11_ctrl == 1 )); then
  if [[ -n "${TARGET_OUT}" ]]; then
    GEOM=$(xrandr | awk -v out="$TARGET_OUT" '$1==out && / connected/ {
      for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) { print $i; exit }
    }')
    [[ -n "${GEOM}" ]] || die "Display '$TARGET_OUT' not found or not connected."
  else
    GEOM=$(xrandr | awk '/ connected/ {
      for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) { print $i; exit }
    }')
    [[ -n "${GEOM}" ]] || die "No connected display found."
    TARGET_OUT=$(xrandr | awk '/ connected/ {print $1; exit}')
  fi
  WH="${GEOM%%+*}"
  OFFSET_X="${GEOM#*+}"; OFFSET_X="${OFFSET_X%%+*}"
  OFFSET_Y="${GEOM##*+}"
  W="${WH%x*}"
  H="${WH#*x}"
  echo "X11 control: target $TARGET_OUT => ${W}x${H}+${OFFSET_X}+${OFFSET_Y}"
else
  echo "Wayland-safe mode (no window control): launching kiosk."
fi

# ---------- Compose launch command ----------
LAUNCH_CMD=()
ENV_PREFIX=()

if (( use_x11_ctrl == 1 )) && (( is_wayland == 1 )); then
  # We are in Wayland but user asked X11 control -> force XWayland
  case "$CHOSEN" in
    firefox)
      ENV_PREFIX=(env MOZ_ENABLE_WAYLAND=0)
      ;;
    google-chrome|chromium|chromium-browser|brave-browser|vivaldi|microsoft-edge)
      LAUNCH_CMD+=(--ozone-platform=x11)
      ;;
  esac
fi

case "$CHOSEN" in
  firefox)
    prepare_firefox_userjs "$PROFILE_DIR"
    if (( use_x11_ctrl == 1 )); then
      # No --kiosk here: we need to move/resize before fullscreen
      BASE_ARGS=(--no-remote --profile "$PROFILE_DIR" --new-window "$URL")
    else
      BASE_ARGS=(--no-remote --profile "$PROFILE_DIR" --kiosk "$URL")
    fi
    ;;
  google-chrome|chromium|chromium-browser|brave-browser|vivaldi|microsoft-edge)
    COMMON_FLAGS=(
      --user-data-dir="$PROFILE_DIR"
      --use-fake-ui-for-media-stream
      --autoplay-policy=no-user-gesture-required
      --no-first-run --no-default-browser-check --disable-infobars
    )
    if (( use_x11_ctrl == 1 )); then
      BASE_ARGS=("${COMMON_FLAGS[@]}" --new-window "$URL")
    else
      BASE_ARGS=("${COMMON_FLAGS[@]}" --kiosk "$URL")
    fi
    ;;
  *)
    if (( use_x11_ctrl == 1 )); then
      BASE_ARGS=(--new-window "$URL")
    else
      BASE_ARGS=(--kiosk "$URL")
    fi
    ;;
esac

# Merge args if we had pre-added ozone flag
FULL_CMD=( "$CHOSEN" "${LAUNCH_CMD[@]}" "${BASE_ARGS[@]}" )

echo "Launching: ${ENV_PREFIX[*]} ${FULL_CMD[*]}"
# Launch & capture PID
"${ENV_PREFIX[@]}" "${FULL_CMD[@]}" >/dev/null 2>&1 & BROWSER_PID=$!

# ---------- X11 control: place window & fullscreen ----------
if (( use_x11_ctrl == 1 )); then
  # Find the window by PID to avoid collisions
  WIN_ID=""
  for i in {1..60}; do
    WIN_ID=$(wmctrl -lp | awk -v pid="$BROWSER_PID" '$3==pid {w=$1} END{print w}')
    [[ -n "$WIN_ID" ]] && break
    sleep 0.2
  done
  [[ -n "$WIN_ID" ]] || die "Could not find the browser window in time."

  # Move/resize then fullscreen
  wmctrl -ir "$WIN_ID" -e "0,${OFFSET_X},${OFFSET_Y},${W},${H}"
  wmctrl -ir "$WIN_ID" -b add,fullscreen || true

  # Optional fallback: send F11 if available
  if have xdotool; then
    xdotool windowactivate "$WIN_ID" key F11 || true
  fi

  echo "✅ Done: fullscreen on ${TARGET_OUT} at (${OFFSET_X},${OFFSET_Y}) ${W}x${H}"
else
  echo "✅ Done: launched in kiosk (Wayland-safe). Position cannot be controlled under Wayland."
fi