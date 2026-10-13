<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/logo-dark.svg">
    <img src="docs/media/logo-light.svg" width="150" alt="Seamtype: A, 아, あ">
  </picture>
</p>

<h1 align="center">Seamtype</h1>

<p align="center"><b>흐름대로 써진다 · 流れるままに · Type as it flows</b></p>

<p align="center"><a href="https://nyttastudio.com/seamtype/">Website (Korean)</a> · <a href="README.md">한국어</a> · English</p>

Type everything on the English (QWERTY) layout and stop pressing the language-switch key.
Seamtype is a macOS input method that decides **per word** whether you meant English,
Korean (2-set / 두벌식) or — if you turn it on — Japanese (romaji), and commits the right one.

```
Stay hungry, stay foolishsms wkqtmdml akfdlek.   →  Stay hungry, stay foolish는 잡스의 말이다.
wagahaihanekodearu␣sms thtpzldml thtjfdlek.      →  吾輩は猫である는 소세키의 소설이다.
Hello, worldhasaishonopuroguramudesu␣.           →  Hello, worldは最初のプログラムです。
```

<p align="center">
  <img src="docs/media/demo.gif" width="720" alt="Choosing Seamtype once from the input menu, then typing on QWERTY into Safari without switching the input source again: Stay hungry, stay foolish는 잡스의 말이다. / 吾輩は猫である는 소세키의 소설이다. / Hello, worldは最初のプログラムです。">
</p>

## Why

I live in Japan and mix Korean, English and Japanese every day. With three input sources, I was
forever pressing the switch key, or typing a word in the wrong language. Then
[Meltype](https://github.com/yksr-melt/Meltype), which mixes Japanese and English without switching,
inspired me to build one input method for all three.

## Install

Download [`Seamtype.pkg`](https://github.com/aimdevlee/seamtype/releases/latest/download/Seamtype.pkg),
open it and follow the steps. It runs on Apple silicon and Intel and is notarized by Apple. It
installs into `/Library/Input Methods` and registers the input source, so you only need to pick
Seamtype in the input menu in the menu bar.

**Japanese is off by default.** To mix in Japanese as in the examples above, turn on **Japanese
Input** in the input menu.

If Seamtype isn't in the input menu, add it in **System Settings → Keyboard → Input Sources →
Edit… → + → Korean → Seamtype**. If it isn't listed there either, log out and back in once.

When a new version is out, the input menu shows **Update to Seamtype …** and **About** in the
settings window lists what changed and installs it (**Check Now** checks by hand). It downloads the installer, checks its
signature and opens it, so you only enter your password. Checks happen once a day and when the
settings window opens; they ask GitHub only for the latest version number, and nothing you type
is sent. Turn them off with **Check for updates automatically** in About.

To update by hand, download the new `Seamtype.pkg` and install it the same way. It replaces the app and
keeps your settings and learned words, with no logout or restart. For a clean reinstall, tick
**Reset settings and learned words** under **Customize** in the installer.

Seamtype takes ~50 MB of memory (plus the ~35 MB Japanese dictionary when Japanese is on) and
~47 MB on disk, with nothing else running. Keystrokes never leave the input method.

### Uninstall

In the settings window, click **About → Uninstall Seamtype → Uninstall…**. It removes Seamtype
from both Input Methods folders (macOS asks for your password if you used the pkg) and switches to
another input source. Settings and learned words go only if you tick that in the confirmation.

If Seamtype still shows in the input source list in System Settings after uninstalling, log
out and back in once. If you reinstall and it isn't in the input menu, remove it from that list
with − and add it again with +.

<details>
<summary>Uninstall in Terminal</summary>

Does what the settings window does (`--delete-data` only to drop settings and learned words too):

```sh
"/Library/Input Methods/Seamtype.app/Contents/MacOS/Seamtype" --uninstall --delete-data
```

</details>

## Keys

While a word is being typed it is underlined and shows the language Seamtype expects.

| Key | English / Korean word | Japanese phrase |
| --- | --- | --- |
| letters | extend the word | extend the phrase (kana preview) |
| **Esc** | switch reading: English → English+particle → Korean → Japanese | same |
| **⇧Esc** | switch reading, in every app (where Esc is set to go to the app) | same |
| **Right ⌥** (tapped on its own) | same as ⇧Esc; apps ignore it, so it never closes a window or clears input the way an Esc can (a setting can make it ⌥Space or right ⇧) | same |
| Delete | English: the last letter. Korean: the syllable being typed jamo by jamo, earlier ones whole (한국 → 한구 → 한ㄱ → 한 → gone, as the system's 2-set does) | one kana at a time (かんこく → かんこ) |
| **Space** | commit, then a space | **convert to kanji** (candidate window) |
| `, . ? !` and other symbols | commit, then the key | join the phrase, full-width: 、。？！ （）＿ 「」(`[ ]`) ・(`/`) 〜(`~`) |
| `-` | commit, then `-` | ー |
| Return | commit only (press again for a newline or to send; a setting) | commit as shown, kana or live-converted kanji (no newline) |
| ⌃K / F7, ⌃J / F6 | (the app's shortcut) | katakana / hiragana (Space flips, Return commits) |
| Tab, arrows, ⌘/⌃/⌥ | commit, the app gets the key | same |
| **Right ⌘** (tapped on its own) | pause / resume Seamtype in this text field | same |

A symbol typed on its own after Japanese is full-width and stays underlined, as in a Japanese IME (`！`, `＿`, `「`): Return confirms it (no newline), Space offers its other forms (`!`, `‼︎`, `『`…), and a letter confirms it and starts a new word. Inside numbers (`3.5`, `10:30`) it stays half-width, and a bracket opened full-width closes full-width even after an English word (`日本語（English）`).

While converting (candidate window open):

| Key | Effect |
| --- | --- |
| Space / ↓, ↑ | next / previous candidate |
| ←, → | shorten / lengthen the first clause (`今日は｜いいてんき`) |
| 1–9 | commit that candidate |
| Return | commit the selected candidate |
| Esc / Delete | back to the kana |
| letters, punctuation | commit, then keep typing |

Conversion goes clause by clause: a candidate that covers only the start of the reading (`今日は`
for きょうはいいてんきですね) commits that part and keeps converting the rest.

### Undo after commit, and learning

Right after a word is committed with Space or punctuation, **Esc** switches it to its next reading,
and pressing it again keeps cycling (⇧Esc where Esc goes to the app). Deleting the space or
punctuation first keeps that chance; any other key ends it. This needs the caret still right after
the word and an app that lets Seamtype read the text there; otherwise Esc goes to the app. ⇧Esc with
nothing to change does nothing and never reaches the app.

Chromium-based apps such as Claude's desktop app or Slack also see an Esc the input method took, so
they may close their window or cancel the input while the word changes. There, tap **right ⌥** on its
own instead (or ⌥Space or right ⇧, chosen as the language switch key in settings): it changes the word exactly as Esc does, and apps don't react to it.

A correction changes only that word, so a stray Esc doesn't stick. Correct the same keys the same
way a second time and Seamtype remembers it; switching a word back to Seamtype's own guess forgets
it.

### Text replacements

A shortcut in System Settings → Keyboard → Text Replacements that reads as Korean or Japanese
(`주소`, `ㅈㅅ`, `よろ`) shows in that language whatever the guess, so the app replaces it on Space as
it does with the system's input. English shortcuts are decided as usual. A Japanese shortcut's
phrase is the first candidate on Space, and a shortcut entered more than once offers every phrase in turn. The app does the replacing, so apps without text
replacement (terminals, Chrome…) only get the Japanese candidate. Edits to the list apply the next
time a text field becomes active. Enter a Japanese shortcut as its hiragana reading (`よろ`, `ぐー`).

### Esc that belongs to the app

If Esc has to reach the app, as when closing a popup in an editor, set that app's Esc key (or the
default's) to "Send to app" in the per-app settings. The word goes in as shown and the app gets
Esc. Use ⇧Esc to switch readings there.

### Pause

Where every key is a command, like lazygit or htop in a terminal, tap **right ⌘** on its own. The
word in progress goes in, and in that text field keys go through as typed. Tap again, move to
another app or text field, or change a setting, to resume.

Each tap shows Seamtype's icon under the caret for a moment, like the input source indicator,
struck through when paused. The menu bar icon doesn't change, so to check later, look for the tick
in the input menu. Turn the key off under General in the settings window.

### vim

For neovim put [`scripts/vim/seamtype.lua`](scripts/vim/seamtype.lua) in `~/.config/nvim/plugin/`;
for Vim (8.2 or later, `+job`) put [`scripts/vim/seamtype.vim`](scripts/vim/seamtype.vim) in
`~/.vim/plugin/`. Vim then tells Seamtype on every mode change, so words are decided only in insert
mode, and in normal, visual and command-line mode keys go straight to vim: `s`, `dd`, `ciw` and
`:wq⏎` run key by key. Inside vim, Esc always goes to vim, so no per-app setting is needed. Once vim
quits, words are decided again at the shell.

<details>
<summary>How it works, and caveats</summary>

- The signal is `Seamtype --vim insert|normal|off --app <bundle id>`, sent on mode changes
  (entering and leaving insert mode, start, quit, focus), not on keys.
- The bundle identifier is `$__CFBundleIdentifier`, which macOS sets for every app, so nothing
  needs setting up per terminal (Ghostty, Terminal, iTerm2, VS Code…), and the signal reaches only
  that app's text field. A signal without `--app` is taken only where Esc goes to the app.
- Attached to tmux from a different terminal than the one that started its server, the bundle
  identifiers differ and the signal is ignored.
- If Vim doesn't see the terminal's focus changes, Seamtype can't tell when you move from its pane
  to a shell pane; press ⇧Esc there to start deciding words again.

</details>

## Settings

From the input menu (the menu bar, while Seamtype is selected) you can:
- pause Seamtype in this text field (like right ⌘)
- turn word conversion on or off for the app in front, set its conversion threshold
  (Normal/Strict) and whether Esc goes to the app, or drop its settings. The threshold and Esc are
  greyed while conversion is off
- turn Japanese Input and Live Conversion on or off
- undo the last learned word, and open Try Typing, the remembered words or the settings window

The settings window has General, Try Typing (how each word was decided, with scores), per-app
behavior, the learned words (forget one or all) and About. The kanji candidate order resets under
Japanese. Changes apply at once.

### Settings files

The menu and the settings window both write `~/Library/Application Support/Seamtype/settings.json`.
You can edit it by hand; missing keys keep the default.

```json
{ "japanese": true, "liveConversion": true }
```

| Key | Default | What it does |
| --- | --- | --- |
| `japanese` | **off** | Detect romaji Japanese and convert it. |
| `liveConversion` | off | While you type a Japanese phrase, show its top kanji candidate (`今日はいい天気でs`); Return commits it as shown. Like macOS Live Conversion. |
| `returnConfirmsOnly` | on | Return on an underlined word only confirms it. Off, the app gets that Return too (a Japanese phrase is still only confirmed). |
| `switchKey` | `"rightOption"` | The key that switches the reading of the word being typed or just typed, like ⇧Esc: `"rightOption"` (right ⌥ tapped alone), `"optionSpace"` (⌥Space), `"rightShift"` (right ⇧ tapped alone) or `"off"` (Esc and ⇧Esc only). |
| `rightCommandPause` | on | A right ⌘ tap pauses Seamtype in the text field (see [Pause](#pause)). |
| `fullWidthDigits` | off | Numbers after Japanese come out full-width (`１２３`, `０３－１２３４` in addresses and phone numbers), underlined, with Space offering `123` (half-width) or conversions like `三月`. |
| `fullWidthSpace` | off | Space after Japanese types a full-width space (`　`). ⇧Space types the other width (full-width while this is off). |
| `japaneseEngine` | `"apple"` | Kanji conversion: `"apple"` uses the engine of macOS's Japanese input, `"azooKey"` the AzooKey converter in the app. |

With live conversion, Space opens the candidate window at the next candidate, and Esc shows the
kana (Esc again switches language). Short readings only change into kanji (`と` stays `と`, `私`
converts). The top candidate is right for about 4 in 5 short phrases and 3 in 4 whole sentences
([held-out results](#held-out-results)), so glance before Return. Conversion takes 8–21 ms a
keystroke.

Per-app behavior lives in `apps.json` in the same folder. `"*"` is your default for every app; an
app (by bundle identifier, a key ending in `.` matches as a prefix) names only the keys that differ
from it. No app is listed unless you list it.

```json
{ "*":                     { "escapeToApp": true },
  "com.apple.Terminal":    { "conversionThreshold": 0.97 },
  "com.example.Game":      { "enabled": false } }
```

| Key | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | `false` passes every key through (plain English). |
| `conversionThreshold` | `0.5` | Convert away from the typed letters only when at least this sure. `0.97` (Strict) keeps short shell commands from turning into Hangul in a terminal; `0.5` converts more Korean when you write prose. |
| `escapeToApp` | `false` | Esc goes to the app, and ⇧Esc switches readings (for editors). |
| `fullWidth` | `true` | `false` keeps numbers and spaces half-width in this app whatever the full-width settings say (terminals, code editors). |

After editing these files by hand, restart the input method: `pkill -x Seamtype`.

## How it decides

Locally, in this order. A keystroke's preview takes at most ~3 ms and a word's final decision
~7 ms, even 70 letters into a phrase.

1. **Your corrections** (made twice, see [learning](#undo-after-commit-and-learning)) always win
   (`lexicon.json`).
2. **Mixed words** are split, in an app set to Strict too.
   - English + particle, when the front looks English (or is typed in capitals) and the end is a
     Korean particle or ending: `githubdp` → `github에`, `UIrkxdmsrjs` → `UI같은건`
   - A single English letter + particle, as in a variable name: `xdp` → `x에`, `Xfmf` → `X를`. Not
     `도`/`나` after a lowercase letter, which are common English endings (`heh`, `tsk`); a capital
     gives `X도`.
   - English + Korean word, when the front is a known English word (or a name typed with capitals)
     and the back is in the Korean word list. When the whole token spells nothing like English, any
     Hangul of common syllables splits too. `hellodnjfem` → `hello월드`, `githubtjqj` → `github서버`
   - Korean, then an English word: `dhsmfdmsgoogledptj` → `오늘은google에서`. The Korean goes in
     and the rest keeps composing.
   - With Japanese on:
     - a known English word + one case particle: `githubde` → `githubで`
     - Japanese after Korean: `dlfurrireki` → `이력りれき` (Space for `履歴`)
     - a Korean particle or word after Japanese: `rirekifmf` → `りれき를`,
       `kyouhaehtlfkrdms` → `きょうは도시락은`. The Japanese part is committed on the spot, so with
       live conversion it goes in as `履歴를`, `今日は도시락은`.
     - These split only when the Korean side breaks, so ordinary Japanese phrases stay whole.
3. **Rules:** shift on a letter with no shifted jamo (`Hello`, `API`) is English.
4. **Heuristic:** the keys are scored per keystroke in all three languages, plus a nudge toward the
   previous word's language.
   - English: character trigrams, and a floor for words in the SCOWL list, by how common they are
   - Korean: 2-set syllable frequencies, and a floor for words seen in Korean text
   - Japanese: romaji → kana trigrams, with English words inside the phrase split out
   - The nudge is weaker when the keys are a word of another language and not of the previous one,
     which is someone switching language.
   - A known English word needs a clear Japanese win before it turns into kana.

Kanji come from the conversion engine of macOS's Japanese input (libmecabra), with the top
candidate re-picked by a character trigram model of written Japanese. So variant kanji like `髙`
(`たか`, `たかはし` → `髙橋`), English spellings of names (`とぅいっち` → `Twitch`) and completions
of a partial reading (`ゆーちゅ` → `YouTube`, after the top candidate) come up as in the system's
input. Seamtype remembers what you pick for each reading and puts it first next time. The engine is
private to macOS, so where it can't be loaded the app's own
[AzooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter) dictionary converter stands in.

### Held-out results

2,011 English words, 1,987 Korean words and 2,000 Japanese phrases from held-out sentences,
never used to build the models (`tools/prepare.sh`):

| | Japanese off (en/ko) | Japanese on (en/ko/ja) |
| --- | --- | --- |
| Accuracy | 99.80% | 99.48% |

That set counts every word once and seldom puts it after the other language. But real text is
mostly its most frequent words, and switching language mid-sentence is the point, so the 10,000
most frequent English and Korean words are also scored after each kind of word
(`tools/eval_context.py`, Japanese on). Wrong among the top 1,000 / top 10,000:

| | after nothing | after the same language | after the other | after Japanese |
| --- | --- | --- | --- | --- |
| Korean words | 9 / 42 | 2 / 16 | 16 / 159 | 9 / 46 |
| English words | 2 / 47 | 0 / 21 | 8 / 71 | 2 / 86 |

Before the SCOWL and Korean word lists and the switch-aware nudge, that was 94 / 785 in all; now
it is 48 / 488. These lists were used while tuning those rules, so they're a guide, not a
held-out score. Many remaining misses are genuinely ambiguous keys: `so`/내, `go`/해, `did`/양.

Kanji conversion, top candidate exactly matching the original text (held-out Tatoeba):

| | macOS engine | + reranking | correct one in the list | AzooKey + reranking |
| --- | --- | --- | --- | --- |
| 2–3 word phrases | 74.5% | **81.0%** | 96.2% | 81.0% |
| whole sentences | 71.2% | **74.0%** | 91.5% | 67.2% |

Exact match counts kana/kanji style differences (ひとまとめ vs 一まとめ) as misses.

## Known limits

- Never tested end to end in every app. Secure fields (passwords) bypass input methods, and undo
  after commit needs apps that report their caret and text.
- Where Esc doesn't go to the app, Esc right after a word (e.g. to close a popup) changes that word
  first. It isn't learned unless repeated; list such apps with `"escapeToApp": true`.
- Japanese: only the first clause is resized with ←/→ (Return commits it and moves on to the
  rest). Rare words still need the candidate list.

## Develop

```sh
swift test                     # tests: composers, engines, sessions, settings, end to end
scripts/install.sh             # build, self-test and install into ~/Library/Input Methods (development; stops if the pkg's copy is there)
scripts/typing-test/run.sh     # real key events into the settings window's typing pane through the installed Seamtype
swift scripts/make-readme-logo.swift docs/media  # the README logo (animated SVG)
scripts/release.sh             # universal (arm64 + x86_64) zip and pkg for a release; with a Developer ID also signed and notarized (app and pkg)
tools/prepare.sh               # accuracy (downloads word lists, Tatoeba and SCOWL once)
tools/prepare.sh --models      # rebuild the data in Sources/SeamtypeCore/Data first (not korean_vocabulary.txt)
SEAMTYPE_TIMING=1 swift run -c release seamtype-cli --decide --japanese < keys.tsv  # + time per decision
swift run seamtype-cli -v "dkssud gksrmf hello"               # English/Korean, with scores
printf 'kyouhagoogledekensaku\t\n' | swift run seamtype-cli --decide --japanese
printf 'きょうはいいてんきですね\n' | swift run seamtype-cli --convert
```

| Path | What |
| --- | --- |
| `Sources/SeamtypeCore` | composers, engines, conversion, `InputSession` (all typing logic) |
| `Sources/Seamtype` | InputMethodKit server, a thin controller over `InputSession`, candidate window, settings window |
| `Sources/SeamtypeCore/Data` | kana and written-Japanese trigrams, Korean syllables and words, English words |
| `tools/` | corpus → romaji, model builders, evaluation set and accuracy (python3, no packages) |

## License and data

Seamtype is MIT licensed ([LICENSE](LICENSE)). The app carries the licenses of everything compiled
or copied into it in `Contents/Resources/ThirdPartyNotices.txt`, collected by
`scripts/build-app.sh`.

- Kanji conversion: the Japanese engine that ships with macOS, loaded at runtime (not bundled).
- AzooKey Kana-Kanji Converter (the stand-in): MIT; its dictionary: Apache-2.0.
- Tatoeba sentences (kana and written-Japanese models, Korean syllable and word counts;
  evaluation): CC-BY 2.0 FR, https://tatoeba.org.
- English words and how common they are: [SCOWL](http://wordlist.aspell.net) (permissive,
  notice in the app). macOS's `/usr/share/dict/words` trains the letter trigrams at runtime.
- English/Korean frequency lists:
  [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords), CC-BY-SA 4.0. Used
  for evaluation; the Korean list also ships as `korean_vocabulary.txt` (for splitting an English
  word from a Korean one), under the same license, with its notice in the app.
