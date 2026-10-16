# Seamtype

A macOS input method that decides, per word typed on QWERTY, whether the keys are English,
Korean (2-set) or Japanese romaji. These are the words the code and docs use for that.

## Language

**Korean shift key**:
A key whose shifted form is a different jamo on the 2-set layout: Q W E R T (ㅃ ㅉ ㄸ ㄲ ㅆ) and
O P (ㅒ ㅖ). A capital on any other key has no Korean meaning.
_Avoid_: double-consonant key, QWERTOP

**Lingering Shift** (늦게 뗀 Shift):
Shift still held for the one key right after a Korean shift key, so that key arrives as a capital
with no shifted jamo: a vowel after a double consonant (어떤 typed fast is `djEJs`), the next
consonant after a final ㅆ/ㄲ (있어 as `dlTDj`), or a consonant after ㅒ/ㅖ typed on a consonant
(예를 as `dPFmf`). It happens between lowercase keys: a word typed in capitals throughout (`TM`) is
an acronym, and ㅒ/ㅖ with no consonant before it (`PDF파일` as `PDFvkdlf`, `OAuth`) is English, not
a lingering Shift.
_Avoid_: stray Shift, Shift leak

**English-only capital**:
A capital that a lingering Shift does not explain (`Hello`, `API`, `dHello`). It makes the word
English before any scoring.
