#!/usr/bin/env bash
# setup-autostart-start.sh
# -----------------------------------------------------------
# Create a GNOME autostart .desktop entry to launch start-on-linux.sh
# Uses the current working directory (same folder as this setup) to find the start script.
#
# Usage:
#   ./setup-autostart-start.sh [args...]
#     -> All [args...] are forwarded to ./start-on-linux.sh at login.
#
# Example:
#   ./setup-autostart-start.sh 1 brave http://localhost:8080
#
# Notes:
# - This sets up autostart for the current user (after graphical login).
# - Make sure Wayland is disabled (GDM: WaylandEnable=false) so you run X11.
# -----------------------------------------------------------

set -euo pipefail

err(){ echo "[ERROR] $*" >&2; exit 1; }
info(){ echo "[INFO]  $*" >&2; }

# Where we are (this is the directory we want to run from at login)
WORKDIR="$(pwd)"
START_SCRIPT="${WORKDIR}/start-on-linux.sh"
AUTOSTART_DIR="${HOME}/.config/autostart"
DESKTOP_FILE="${AUTOSTART_DIR}/start-on-linux.desktop"
APP_NAME="Kiosk Starter"

# Ensure start-on-linux.sh exists
[[ -f "$START_SCRIPT" ]] || err "start-on-linux.sh not found in: ${WORKDIR}"

# Make sure it's executable
chmod +x "$START_SCRIPT"

# Build a safely-escaped argument string for the Exec line
# (printf %q produces shell-escaped tokens understood by /bin/sh)
EXEC_ARGS=""
if [[ $# -gt 0 ]]; then
  for a in "$@"; do
    EXEC_ARGS+=" $(printf '%q' "$a")"
  done
fi

# Create autostart directory
mkdir -p "$AUTOSTART_DIR"

# Write .desktop entry
# - Path= sets the working directory (GNOME honors it)
# - Exec uses env to enforce X11-friendly environment (avoid Wayland/keyring surprises)
# - We call ./start-on-linux.sh with all forwarded arguments
info "Writing autostart file: ${DESKTOP_FILE}"
cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=Run start-on-linux.sh at login (X11 kiosk starter)
Path=${WORKDIR}
Exec=/usr/bin/env bash -lc 'env -u WAYLAND_DISPLAY XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb OZONE_PLATFORM=x11 MOZ_ENABLE_WAYLAND=0 MOZ_DISABLE_WAYLAND=1 ./start-on-linux.sh${EXEC_ARGS}'
X-GNOME-Autostart-enabled=true
Terminal=false
EOF

info "Autostart installed."
echo "File: ${DESKTOP_FILE}"
echo "Will run: ${START_SCRIPT}${EXEC_ARGS}"
echo
echo "Next steps:"
echo "  - Ensure you're on X11 (Wayland disabled):  echo \$XDG_SESSION_TYPE  -> x11"
echo "  - Log out/in (or reboot) to test autostart."
echo "  - You can test now by running:"
echo "      (cd ${WORKDIR} && env -u WAYLAND_DISPLAY XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb OZONE_PLATFORM=x11 MOZ_ENABLE_WAYLAND=0 MOZ_DISABLE_WAYLAND=1 ./start-on-linux.sh${EXEC_ARGS})"