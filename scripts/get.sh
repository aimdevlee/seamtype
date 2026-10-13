#!/bin/sh
# Installs the latest Seamtype release into ~/Library/Input Methods and registers it:
#
#   curl -fsSL https://raw.githubusercontent.com/aimdevlee/seamtype/main/scripts/get.sh | sh
#
# If Seamtype is already installed it asks what to do; to choose without the question:
#   … | sh -s -- --reinstall              replace it, keep settings and learned words
#   … | sh -s -- --clean                  remove it with settings and learned words, then install
#   … | sh -s -- --uninstall [--delete-data]
# Without a terminal to ask in, it reinstalls, unless the installer package's copy is in /Library:
# then it stops, since that copy can only be removed with a password.
#
# Releases aren't signed with a Developer ID. A download made with curl isn't quarantined, so
# Gatekeeper doesn't stop it; the quarantine flag is cleared anyway in case it's there.
# SEAMTYPE_ZIP=/path/to/Seamtype.zip installs a local zip instead (for trying a build).
set -eu

url="https://github.com/aimdevlee/seamtype/releases/latest/download/Seamtype.zip"
dest="$HOME/Library/Input Methods"
app="$dest/Seamtype.app"
system="/Library/Input Methods/Seamtype.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

action="" deletedata=""
for arg in "$@"; do
  case $arg in
    --reinstall) action=reinstall ;;
    --clean) action=clean ;;
    --uninstall) action=uninstall ;;
    --delete-data) deletedata=--delete-data ;;
    *) echo "usage: get.sh [--reinstall | --clean | --uninstall [--delete-data]]" >&2; exit 2 ;;
  esac
done

if [ -z "$action" ] && { [ -d "$app" ] || [ -d "$system" ]; }; then
  action=reinstall
  if (exec </dev/tty) 2>/dev/null; then
    echo "Seamtype is already installed:"
    [ -d "$app" ] && echo "  $app"
    [ -d "$system" ] && echo "  $system (the installer package)"
    cat <<'MSG'
  1) Reinstall: replace it, keep settings and learned words
  2) Clean reinstall: remove it with its settings and learned words, then install
  3) Uninstall (keep settings and learned words)
  4) Uninstall and delete settings and learned words
  5) Cancel
MSG
    printf 'Choose [1]: '
    read -r answer </dev/tty || answer=""
    case ${answer:-1} in
      1) ;;
      2) action=clean ;;
      3) action=uninstall ;;
      4) action=uninstall deletedata=--delete-data ;;
      *) echo "Nothing changed."; exit 0 ;;
    esac
  fi
fi

# The pkg's copy in /Library has to go before this one goes into ~/Library: two copies are the
# same input method twice, and macOS may launch either. Removing it needs an administrator, asked
# for now; without a terminal, or without the password, nothing is installed.
if [ "$action" = reinstall ] && [ -d "$system" ]; then
  if ! (exec </dev/tty) 2>/dev/null; then
    echo "Seamtype from the installer package is in /Library/Input Methods; nothing was installed." >&2
    echo "Update it with the package, or run this in a terminal to replace it." >&2
    exit 1
  fi
  echo "Replacing $system (the installer package's copy) needs your password."
  sudo -v </dev/tty || { echo "Nothing was installed." >&2; exit 1; }
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
xattr -dr com.apple.quarantine "$work/Seamtype.app" 2>/dev/null || true

# Uninstalling goes through the app (what About → Uninstall… does): both copies, the pkg's
# receipt (macOS asks for the password), the input source and the processes.
if [ "$action" = uninstall ] || [ "$action" = clean ]; then
  [ "$action" = clean ] && deletedata=--delete-data
  "$work/Seamtype.app/Contents/MacOS/Seamtype" --uninstall $deletedata
  "$lsregister" -u "$work/Seamtype.app" 2>/dev/null || true
  [ "$action" = uninstall ] && exit 0
fi

mkdir -p "$dest"
# Swapped by renaming within the folder, so there is never a moment without a Seamtype.app there
# for macOS to launch (the old one keeps running meanwhile).
rm -rf "$dest/.Seamtype.app.new" "$dest/.Seamtype.app.old"
ditto "$work/Seamtype.app" "$dest/.Seamtype.app.new"
[ -d "$app" ] && mv "$app" "$dest/.Seamtype.app.old"
mv "$dest/.Seamtype.app.new" "$app"
# Stopped only after the new copy is in place: macOS launches an input method from whatever is on
# disk when an app asks, so stopping it earlier only starts the old code again under a new pid.
# SIGTERM, then SIGKILL whatever is left, and wait until it is gone (as vChewing's installer does):
# a Seamtype still running would keep the old code, and registering may start one.
pkill -x Seamtype 2>/dev/null || true
i=0; while pgrep -x Seamtype >/dev/null && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done
pkill -9 -x Seamtype 2>/dev/null || true
i=0; while pgrep -x Seamtype >/dev/null && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done
"$app/Contents/MacOS/Seamtype" --register
rm -rf "$dest/.Seamtype.app.old"
# Two copies make two input methods, and macOS may launch the wrong one: a reinstall the user
# chose takes the pkg's copy out (with its receipt). Only after this copy is registered: removed
# first, it takes the input source (and the user's choice to use it) along.
if [ "$action" = reinstall ] && [ -d "$system" ] && (exec </dev/tty) 2>/dev/null; then
  sudo rm -rf "$system" </dev/tty && sudo pkgutil --forget com.aimdevlee.inputmethod.Seamtype.pkg >/dev/null 2>&1 || true
fi
killall TextInputMenuAgent 2>/dev/null || true
# The switch indicator by the caret keeps the icon it read first (they ignore SIGTERM).
killall -KILL CursorUIViewService TextInputSwitcher 2>/dev/null || true

[ -d "$system" ] &&
  echo "Note: another copy is in /Library/Input Methods; remove one of them."
cat <<'MSG'

Seamtype is installed. Add it in System Settings → Keyboard → Input Sources → Edit… → + →
Korean → Seamtype (log out and back in once if it isn't listed), then pick it from the input menu.
MSG
