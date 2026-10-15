# Seamtype

A macOS input method that decides, per word typed on QWERTY, whether the keys are English,
Korean (2-set) or Japanese romaji. These are the words the code and docs use for that.

## Language

**Korean shift key**:
A key whose shifted form is a different jamo on the 2-set layout: Q W E R T (ㅃ ㅉ ㄸ ㄲ ㅆ) and
O P (ㅒ ㅖ). A capital on any other key has no Korean meaning.
_Avoid_: double-consonant key, QWERTOP

**Lingering Shift** (늦게 뗀 Shift):
Shift still held after a Korean shift key, so the next key arrives as a capital with no shifted
jamo (어떤 typed fast is `djEJs`). Read as Korean typed fast, not as English.
_Avoid_: stray Shift, Shift leak

**English-only capital**:
A capital that a lingering Shift does not explain (`Hello`, `API`, `dHello`). It makes the word
English before any scoring.
