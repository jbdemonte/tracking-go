#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# run-tracking.sh
# Launches the backend binary and opens the browser
# on HDMI-1 displaying http://localhost:8080
# -------------------------------------------------------

# Paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BIN="$BASE_DIR/out/face-pos-linux"    # Path to your compiled binary
APP_LOG="$BASE_DIR/face-pos.log"          # Log file for stdout/stderr
SCRIPT_DIR="$BASE_DIR/scripts"
BROWSER_SCRIPT="$SCRIPT_DIR/open-on-screen.sh"

# Browser & screen config
BROWSER_URL="http://localhost:8080"       # URL to open

BROWSER_URL_LEFT="$BROWSER_URL?side=left"
BROWSER_URL_RIGHT="$BROWSER_URL?side=right"

# --- Functions ---
die() { echo "❌ Error: $*" >&2; exit 1; }

# --- Check dependencies ---
[[ -x "$APP_BIN" ]] || die "Binary not found or not executable: $APP_BIN"
[[ -x "$BROWSER_SCRIPT" ]] || die "Browser launcher script not found: $BROWSER_SCRIPT"

# --- Start backend ---
echo "🚀 Starting backend: $APP_BIN"
nohup "$APP_BIN" >"$APP_LOG" 2>&1 &
APP_PID=$!
echo "✅ Backend started (PID: $APP_PID, log: $APP_LOG)"

# --- Wait briefly for the server to be ready ---
echo "⏳ Waiting for localhost:8080..."
for i in {1..20}; do
  if curl -fs "$BROWSER_URL/healthz" >/dev/null 2>&1; then
    echo "✅ Server is up!"
    break
  fi
  sleep 0.5
done

echo "🖥️  Opening browser on screen #1 on chrome → $BROWSER_URL_LEFT"
"$BROWSER_SCRIPT" 1 "chrome" "$BROWSER_URL_LEFT"

echo "🖥️  Opening browser on screen #2 on chrome → $BROWSER_URL_RIGHT"
"$BROWSER_SCRIPT" 2 "chrome" "$BROWSER_URL_RIGHT"

echo "✨ All done. Backend PID: $APP_PID"