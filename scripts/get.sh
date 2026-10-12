#!/bin/sh
# Installs the latest Seamtype release into ~/Library/Input Methods and registers it:
#
#   curl -fsSL https://raw.githubusercontent.com/aimdevlee/seamtype/main/scripts/get.sh | sh
#
# Release downloads are signed and notarized.
# SEAMTYPE_ZIP=/path/to/Seamtype.zip installs a local zip instead (for trying a build).
set -eu

url="https://github.com/aimdevlee/seamtype/releases/latest/download/Seamtype.zip"
dest="$HOME/Library/Input Methods"
app="$dest/Seamtype.app"
if [ -d "/Library/Input Methods/Seamtype.app" ]; then
  echo "Seamtype is already installed in /Library/Input Methods. Update it with Seamtype.pkg, or uninstall it before using this installer." >&2
  exit 1
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ -n "${SEAMTYPE_ZIP:-}" ]; then
  cp "$SEAMTYPE_ZIP" "$work/Seamtype.zip"
else
  echo "Downloading Seamtype…"
  curl -fsSL -o "$work/Seamtype.zip" "$url"
fi
ditto -x -k "$work/Seamtype.zip" "$work"
[ -d "$work/Seamtype.app" ] || { echo "The download has no Seamtype.app." >&2; exit 1; }

mkdir -p "$dest"
pkill -x Seamtype 2>/dev/null || true
rm -rf "$app"
mv "$work/Seamtype.app" "$app"
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
"$app/Contents/MacOS/Seamtype" --register
killall TextInputMenuAgent 2>/dev/null || true
# The switch indicator by the caret keeps the icon it read first (they ignore SIGTERM).
killall -KILL CursorUIViewService TextInputSwitcher 2>/dev/null || true

cat <<'MSG'

Seamtype is installed. Add it in System Settings → Keyboard → Input Sources → Edit… → + →
Korean → Seamtype (log out and back in once if it isn't listed), then pick it from the input menu.
For Japanese, turn on Japanese Input in Seamtype's input menu; it is off by default.
MSG
