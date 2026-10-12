#!/bin/zsh
# Builds, self-tests and installs the input method.
#   scripts/install.sh
set -euo pipefail
cd "${0:A:h}/.."

if [[ -d "/Library/Input Methods/Seamtype.app" ]]; then
  echo "Seamtype is already installed in /Library/Input Methods. Uninstall it before installing a development build." >&2
  exit 1
fi
scripts/build-app.sh
dest="$HOME/Library/Input Methods"
mkdir -p "$dest"
pkill -x Seamtype 2>/dev/null || true
rm -rf "$dest/Seamtype.app"
cp -R build/Seamtype.app "$dest/"
echo "installed $dest/Seamtype.app"

id=com.aimdevlee.inputmethod.Seamtype
enabled=false
if swift scripts/enable-input-source.swift "$dest/Seamtype.app" $id; then enabled=true; else
  for _ in {1..10}; do  # an input source the user already added comes back within ~30 s
    sleep 3
    swift scripts/enable-input-source.swift --check $id && { enabled=true; break; }
  done
fi
# The input menu keeps the list from before the reinstall (without Seamtype) until it restarts,
# and the switch indicator by the caret its icon (they ignore SIGTERM; launchd brings them back).
$enabled && killall TextInputMenuAgent 2>/dev/null || true
$enabled && killall -KILL CursorUIViewService TextInputSwitcher 2>/dev/null || true
$enabled && echo "input source $id is enabled" ||
  echo "input source $id isn't enabled: add it in System Settings → Keyboard → Input Sources"

cat <<'EOF'

Next: pick "Seamtype" from the input menu. If it isn't there, add it in
System Settings → Keyboard → Input Sources → Edit… → + → Korean, or log out and back in once.
For Japanese, turn on Japanese Input in Seamtype's input menu; it is off by default.
EOF
