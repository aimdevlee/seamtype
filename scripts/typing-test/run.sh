#!/bin/zsh
# Types test cases with real key events into the typing pane of Seamtype's settings window,
# through the installed Seamtype, and compares the text. The pane switches to Seamtype itself when
# another input source is in use. Needs Accessibility permission for the terminal. The settings
# window takes the focus for about a minute.
#
# Each suite runs with its own settings.json: cases.tsv with Japanese on, live.tsv with live
# conversion too, fullwidth.tsv with full-width numbers and spaces. Esc and ⇧Esc are the switch
# keys throughout (apps.json), as the cases switch with Esc. The user's settings, apps and
# learning files (the cases' Esc corrections would be learned like any other; so would its kanji
# choices) are backed up first and restored afterwards. Seamtype keeps running: it reads changed
# files when told, as from the settings window.
#
#   scripts/typing-test/run.sh
set -euo pipefail
here="${0:A:h}"
support="$HOME/Library/Application Support/Seamtype"
files=(settings.json apps.json lexicon.json apple-learning.json)
app=""
for candidate in "$HOME/Library/Input Methods/Seamtype.app" "/Library/Input Methods/Seamtype.app"; do
  [[ -d "$candidate" ]] && { app=$candidate; break; }
done
[[ -n "$app" ]] || { echo "Seamtype isn't installed"; exit 1; }
dirs=(azooKey)  # AzooKey's kanji learning
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swiftc -O -o "$work/typer" "$here/typer.swift"
swiftc -O -o "$work/notify" "$here/notify.swift"
mkdir -p "$support"
for f in $files; do
  [[ -f "$support/$f" ]] && cp "$support/$f" "$work/$f"
done
for d in $dirs; do
  [[ -d "$support/$d" ]] && cp -R "$support/$d" "$work/$d"
done
restore() {
  # Drop what the run learned in memory first, so nothing saves it over the restored copies,
  # then put them back and have Seamtype read them.
  "$work/notify" kanjiReset
  sleep 1
  for f in $files; do
    if [[ -f "$work/$f" ]]; then cp "$work/$f" "$support/$f"; else rm -f "$support/${f:?}"; fi
  done
  for d in $dirs; do
    rm -rf "$support/${d:?}"
    if [[ -d "$work/$d" ]]; then cp -R "$work/$d" "$support/$d"; fi
  done
  "$work/notify" kanjiReset
}
trap 'restore; rm -rf "$work"' EXIT

suite() {
  echo "== $1"
  print -r -- "$2" > "$support/settings.json"
  "$work/notify"
  sleep 1
  # A failing suite must not end the script here: zsh skips the EXIT trap (the restore) when
  # errexit fires inside a function.
  "$work/typer" "$here/$1" "$app" || failed=1
}
failed=0
print -r -- '{ "*": { "switchKeys": ["escape", "shiftEscape"] } }' > "$support/apps.json"
suite cases.tsv '{ "japanese": true }'
suite live.tsv '{ "japanese": true, "liveConversion": true }'
suite fullwidth.tsv '{ "japanese": true, "fullWidthDigits": true, "fullWidthSpace": true }'
exit $failed
