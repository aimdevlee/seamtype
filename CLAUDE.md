# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Seamtype is a macOS InputMethodKit input method: the user types on QWERTY and Seamtype decides per
word whether it is English, Korean (2-set) or Japanese romaji (kanji through macOS's own engine, AzooKey where it can't be loaded). README.md
(Korean, the main one) and README.en.md (English) cover the keys, settings files, accuracy numbers
and data licenses; read one before changing behavior users see, and keep both in step. The website,
https://nyttastudio.com/seamtype/ (Korean only), lives in `seamtype/` of the nyttastudio/nyttastudio.com
repo (Cloudflare Pages); keep its copy in step too.

## Commands

```sh
swift build                                  # debug build of everything
swift test                                   # all tests (Swift Testing, ~7 s)
swift test --filter MixedWordTests           # one suite; --filter 'MixedWordTests/splitsEnglishPlusParticle' for one test
scripts/install.sh                           # release build + --selftest, install to ~/Library/Input Methods, enable, restart menu agent
                                             # (asks reinstall/clean/uninstall when already installed and a tty exists;
                                             #  --reinstall | --clean | --uninstall [--delete-data] to choose)
scripts/release.sh                           # universal build → build/release/Seamtype{,-<version>}.{zip,pkg}
                                             # (SEAMTYPE_APP_SIGN / SEAMTYPE_PKG_SIGN / SEAMTYPE_NOTARY_PROFILE: Developer ID, notarization)
swift run seamtype-cli -v "dkssud hello"     # English/Korean decision with scores
printf 'keys\tprevious\n' | swift run seamtype-cli --decide --japanese   # previous: english|korean|japanese|empty
printf 'きょうは\n' | swift run seamtype-cli --convert                    # AzooKey candidates (SEAMTYPE_ENGINE=apple: macOS's)
tools/prepare.sh [--models]                  # held-out accuracy (downloads into tools/data, gitignored)
scripts/typing-test/run.sh                   # real key events into the settings window's typing pane through the installed app
/usr/bin/log show --last 10m --predicate 'subsystem == "com.aimdevlee.inputmethod.Seamtype"' --info --debug
```

- `scripts/typing-test/run.sh` takes over the keyboard and focus for about a minute. Don't run it
  while the user is using the machine.
- Use `/usr/bin/log`, not `log`: zsh's builtin `log` shadows it and prints nothing.
- A change only reaches real typing after `scripts/install.sh`. A copy started with `open` or from
  `build/` never gets IMK connections; macOS has to launch the installed bundle itself.

## Architecture

**Targets.** `SeamtypeCore` holds all the typing logic and is what the tests cover. `Seamtype`
is a thin IMK layer over it. `seamtype-cli` is for tuning and evaluation.

**Decision chain** (built in `Runtime.makeEngine`): `LearningEngine` (lexicon.json: a correction
made twice wins) → `SplittingEngine` (`MixedWord.swift`) → `HeuristicEngine`.
- `SplittingEngine` handles English + Korean particle (`github에`), a single letter + particle
  (`xdp` → `x에`, not 도/나 after a lowercase letter), English + whole Korean word (`hello월드`,
  using `Data/korean_vocabulary.txt`, which is only for this) and English + Japanese particle
  (`githubで`). Its decisions have confidence 0.98 (`SplittingEngine.confidence`), above Strict
  (0.97), so they split in a strict app too.
- `HeuristicEngine` scores the keys per keystroke as English, Korean and Japanese, then nudges
  toward the previous word's language.
- `render(_:as: .mixed)` uses the engine's split when the engine makes one, else the plain
  particle split (what an Esc-forced mixed reading shows).

**`InputSession`** is one state machine per text client, behind the `TextClient` protocol (the
tests use `FakeTextField`). It owns the preview and hysteresis, commits, Esc reading cycling, the
"flip the word just committed" window, kana-kanji conversion and live conversion.
- Some splits happen here, not in the engine, because the part after the split keeps composing
  (the Japanese half needs conversion): Korean → English or Japanese (`오늘은` + `google에서`,
  `이력` + `rireki`) and Japanese → Korean (`rireki` + `를`, `kyouha` + `도시락`). The front part
  is committed mid-word (Japanese as kana, or the live candidate) and the rest keeps composing.
- Korean → other fires only when the whole token reads as broken Hangul, and for Japanese also
  not as Japanese on its own; Japanese → Korean only when the romaji has stray letters. Without
  those guards, ordinary Japanese phrases split (`chanwokoroshita` → `초무をころした`).
- In a Strict app, a token of 3 keys or fewer kept English by the threshold wins over a Korean
  preview shown along the way (`gst` stays `gst`); longer words keep the preview's hysteresis.
- The keys that switch a word's reading are per app (`AppPolicy.switchKeys`; default right ⌥ tap
  and ⇧Esc). `InputController` turns a chosen tap, ⌥Space or ⇧Esc into `.cycle`, and only a chosen
  one; an unchosen Esc or ⇧Esc commits and goes to the app. Esc still goes back to the kana in the
  candidate window and with live conversion. `AppPolicies.migrateSwitchKey` moves 0.1.9's
  `switchKey` (settings.json) into `"*"`; an entry's old `escapeToApp` still applies until
  the entry names its own `switchKeys`.
- Return on an underlined word only confirms it (`returnConfirmsOnly`, on by default); off, the
  app gets the Return too, except after Japanese.
- Vim reports its modes through `scripts/vim/seamtype.{lua,vim}` (`Seamtype --vim <mode> --app
  $__CFBundleIdentifier`, a distributed notification). `Runtime` hands it to the active controller,
  which takes it only if vim runs in its app (a signal without `--app`, only where Esc isn't a
  switch key). Outside insert mode every key passes straight through, and while
  vim reports, Esc is vim's whatever the app's policy says; nothing guesses the mode from keys.
- A right ⌘ tap (flagsChanged, in `InputController`) pauses the session until the next tap,
  `activate`, or a settings change (a fresh session). The menu icon can't change, so `PauseHUD`
  shows the icon under the caret for a moment, struck through when paused (drawn by
  `make-icon.swift --slash`), for the menu's toggle too. It copies the system's input source
  indicator, measured on screen: size, gap, and the accent color's components taken as Display P3.
- After a word ends with Space or punctuation, only the word is inserted and `handle` returns
  false, so the app types the key itself, as the system Korean IME does. Inserting "word + space"
  left a stray character in Ghostty. Test harnesses must insert the passed-on key themselves.
- In an app set to `holdSpace` (per app only: the Apps pane offers no default for it, since in `"*"`
  it would turn off text replacements everywhere), Space doesn't commit: the word stays composed
  with `heldSpace` set and is shown with its space (`show`), rendered as the whole word's decision
  (`pinned`) so what's underlined is what will go in. It is still the word being typed: a switch
  key cycles it, Delete only clears `heldSpace`, and Space on it once switched to Japanese converts.
  The next letter, Return, Tab, punctuation, a shortcut or a focus change commits the word and its
  space in one `insertText`. Ghostty sends text committed on a letter key as text and encodes nothing for a key
  the IME consumed while composing, which is what makes this work there; it reports its mouse
  selection as the caret, so the post-commit flip window can't.

**`Runtime`** (`Sources/Seamtype`) is a process-wide singleton holding settings, engine and
converter, plus a `generation` counter. Controllers swap in a fresh session when the generation
changes, so a settings change applies without a restart.

**Settings window.** It is a separate process, `Seamtype --settings <tab>`, because the IME is
`LSBackgroundOnly`. It edits the JSON files in `~/Library/Application Support/Seamtype/` and posts
the distributed notification `com.aimdevlee.inputmethod.Seamtype.settingsChanged`; the IME reloads
on it. About's Uninstall… (`Uninstaller.swift`, shown only in a copy under an Input Methods folder)
deletes both installed copies and the pkg receipt, so testing it uninstalls the real input method:
run `scripts/install.sh` again afterwards.

**Per-app policy** (`AppPolicy.swift`): in `apps.json`, `"*"` is the user's default and an app
entry names only the keys that differ; a key ending in `.` matches as a prefix. There is no
built-in app list, so add an entry only when the user asks for one.

**Resources.** Data files are found by `Resources.swift`: `Contents/Resources` in the app, the
source tree in development. SPM resource bundles are avoided on purpose, because they'd sit outside
the signed `Contents`. `build-app.sh` copies each data file explicitly, so a new file under
`Sources/SeamtypeCore/Data` has to be added there too.

**Menu icon.** The system reads it from `Seamtype.tiff` (drawn by `scripts/make-icon.swift`),
and it's fixed: the bundle is signed (Developer ID for releases), so nothing inside it may change at
runtime.

## Conventions and pitfalls

- **Logging:** never log typed text. The input logger records the key kind and app only.
- **UI strings:** they go through `L("English key")`, with Korean in
  `Resources/ko.lproj/Localizable.strings`. The input source's name comes from
  `Resources/*.lproj/InfoPlist.strings`.
- **New split or heuristic rules:** check them for wrong splits, not just the target case.
  - Run every keys row of `tools/data/eval.tsv` (English, Korean, Japanese) through an
    `InputSession` with Japanese on, and count Hangul next to kana.
  - For English, also run `tools/data/en_50k.txt` through `seamtype-cli -v`.
  - The CLI only shows the engine's decision, so also test through a session: an earlier split
    looked right in the CLI but never reached real typing.
- **Install refreshes:** after a reinstall, the input menu keeps its old list until
  `TextInputMenuAgent` restarts, and the switch indicator by the caret keeps the icon it read
  first until `CursorUIViewService` and `TextInputSwitcher` do (they ignore SIGTERM, so the install
  paths SIGKILL them). A fresh process can still take 10–30 s to see the source as enabled, hence
  `enable-input-source.swift --check` with retries.
- **Releases** are signed with the Developer ID and notarized, the app and the pkg alike; run
  `release.sh` with `SEAMTYPE_APP_SIGN="Developer ID Application: Dongbin Lee (2UZ65T3U82)"`,
  `SEAMTYPE_PKG_SIGN="Developer ID Installer: Dongbin Lee (2UZ65T3U82)"` and
  `SEAMTYPE_NOTARY_PROFILE=seamtype`, or the assets come out ad hoc and unsigned. Upload
  `Seamtype.pkg` (the website's download button) and `Seamtype.zip` (`scripts/get.sh`) under those
  names for `releases/latest/download/`, plus the versioned copies.
  Pushing a `v<version>` tag that matches `Resources/Info.plist` runs `.github/workflows/release.yml`,
  which does the same with the certificates and notary credentials from the repo secrets and leaves
  a draft release with the four assets and `.github/release-notes.md` as its notes; fill them in
  and publish it by hand.
- **Release notes** are in Korean, and About shows their first section in the app
  (`Release.changes`, `Release.headline`), so write them to these rules:
  - `## 바뀐 것` first, as a list of `- **제목**: 설명`, then the fixed `## 설치·업데이트` text
    from the template. About shows each bold lead as a title and the rest under it.
  - 제목: a short noun phrase, about 10 characters, no period (`입력 중 지우기`, `텍스트 대치`).
  - 설명: About cuts it at two lines (about 70–80 Korean characters), so the first sentence says
    what changed; examples, exceptions and setting keys come after it.
  - What a user notices, not how it was built; a fix says what works now. 3–5 items, biggest first.
  `SEAMTYPE_ZIP=build/release/Seamtype.zip sh scripts/get.sh` tries the zip locally. The pkg installs
  into `/Library/Input Methods` and is not relocatable. Its payload lands in
  `/Library/Application Support/Seamtype/Install` and the postinstall rsyncs it into the existing
  bundle: a bundle PackageKit swaps for a new folder leaves imklaunchagent failing to launch it
  (`LaunchInputMethod() Error, status=-50`) until the user logs out. Then the postinstall runs
  `lsregister -f` and `Seamtype --register` as the logged-in user, until `Seamtype --registered`
  sees the source (users have no Swift toolchain, so registration can't use the scripts).
  `release.sh` signs the app with the hardened runtime even ad hoc, and `build-app.sh` runs the
  self-test under Rosetta too for a universal build.
- **Reinstalling** (the pattern of vChewing's installer): put the new bundle in place first, then
  stop Seamtype (SIGTERM, wait, SIGKILL, wait); stopping it earlier only lets macOS start the old
  code again. Then the new copy's `--register` (`Registration.swift`) unregisters other copies from
  LaunchServices and registers/enables the source only if macOS doesn't list/enable it yet.
  Don't kill `imklaunchagent` (every app that was typing loses all input methods until it
  restarts), and don't start Seamtype yourself (`open`): apps that held the old process report its
  endpoint invalid and the new one's endpoint is dropped with it, so keys go nowhere.
  `--uninstall [--delete-data]` runs `Uninstaller` for the scripts. The pkg's postinstall also
  removes the console user's `~/Library/Input Methods` copy; its Customize pane offers a clean
  reinstall (`scripts/Distribution.xml`, the payload-free `scripts/pkg-reset` package).
- **Updates** (`Updater.swift`, `Release.swift`): the IME checks GitHub's latest release once a day
  (and the settings window on open and on Check Now); the result is shared through the bundle's
  user defaults. Install downloads `Seamtype.pkg`, requires `pkgutil --check-signature` to show
  the Developer ID Installer of team 2UZ65T3U82 and notarization, then opens it in Installer. So
  a release must keep the `Seamtype.pkg` asset name and a `v<version>` tag. About lists the items of
  the notes' first `## ` section as what changed (see Release notes).
  To try an update before publishing (drafts aren't visible to it), point the check at a file in
  GitHub's format: `defaults write com.aimdevlee.inputmethod.Seamtype updateFeed file:///…/latest.json`
  (its `browser_download_url` may be a file URL to a signed pkg); `defaults delete … updateFeed` after.
- **One install method while developing:** `scripts/install.sh` (ad hoc, `~/Library`) or a signed
  pkg (`/Library`), not both. After trying a pkg, run its copy's `--uninstall` before going back to
  `install.sh`; without a terminal `install.sh` refuses to install while the pkg's copy is there
  (two copies are one input method twice). Never install an ad-hoc pkg (`release.sh` without
  `SEAMTYPE_APP_SIGN`): Gatekeeper rejects a copy the installer put down, so it is selectable but
  never starts. A move between the two folders, or an uninstall, drops the input source; re-add it
  in System Settings (− then +) or log out.
- **Stale registrations:** extra copies of the app registered with LaunchServices (`build/`,
  the old `AutoIME.app`) can make macOS launch the wrong one. `build-app.sh` unregisters its copy.
