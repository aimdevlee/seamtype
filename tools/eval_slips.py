"""Korean words typed with one slip of the keys, through a real session (araso-cli --type): how
many go in right, as English, with loose jamo or as another word (`SlipGuesser`, #85; ARASO_FIX_SLIPS=1 for `fixSlips`). And what
must not change: the same sentences without slips, this repo's Korean prose, and common English
words alone and after a Korean word. Run it with main's build and with a branch's to compare.

Slips, one in a word of 4 keys or more in each sentence, by turns: two keys swapped, one dropped,
one typed twice, a neighbour added, Shift missed (했 → 햇). Sentences are Tatoeba's Korean ones of
Hangul words only (kor_sentences.tsv, from prepare.sh); Korean prose is README.md, CONTRIBUTING.md,
docs/*.md and .github/release-notes.md, which the word lists weren't built from.

usage: python3 eval_slips.py <araso-cli> <kor_sentences.tsv> <en_50k.txt> [wrong fixes to list]
"""
import glob
import random
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

from make_eval import keys_for

ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
KINDS = ["swap", "drop", "double", "neighbour", "shift"]


def neighbours(key: str) -> list[str]:
    for row in ROWS:
        i = row.find(key.lower())
        if i >= 0:
            return [row[j] for j in (i - 1, i + 1) if 0 <= j < len(row)]
    return []


def slip(keys: str, kind: str, rng: random.Random) -> str | None:
    """`keys` with one slip of `kind`, or None when the keys have no place for it."""
    k = list(keys)
    if kind == "swap":
        places = [i for i in range(len(k) - 1) if k[i] != k[i + 1]]
        if not places:
            return None
        i = rng.choice(places)
        k[i], k[i + 1] = k[i + 1], k[i]
    elif kind == "drop":
        del k[rng.randrange(len(k))]
    elif kind == "double":
        i = rng.randrange(len(k))
        k.insert(i, k[i])
    elif kind == "neighbour":
        i = rng.randrange(len(k))
        near = neighbours(k[i])
        if not near:
            return None
        k.insert(i + rng.choice([0, 1]), rng.choice(near))
    else:  # Shift missed on a shifted key (ㅆ → ㅅ)
        places = [i for i in range(len(k)) if k[i] in "QWERTOP"]
        if not places:
            return None
        i = rng.choice(places)
        k[i] = k[i].lower()
    return "".join(k)


def type_lines(cli: str, lines: list[str]) -> list[list[str]]:
    res = subprocess.run([cli, "--type"], input="".join(line + "\n" for line in lines), capture_output=True, text=True)
    return [line.split("\t", 1)[1].rstrip(" ").split(" ") if "\t" in line else [] for line in res.stdout.splitlines()]


def outcome(out: str, truth: str) -> str:
    if out == truth:
        return "right"
    if re.fullmatch(r"[A-Za-z]+", out):
        return "English"
    if re.search(r"[ㄱ-ㅣ]", out):
        return "loose jamo"
    return "another word"


def with_slips(cli: str, rows: list[list[str]], seed: int, label: str, listed: int) -> None:
    rng = random.Random(seed)
    lines, marks = [], []
    for n, row in enumerate(rows):
        places = [i for i, w in enumerate(row) if re.fullmatch(r"[가-힣]+", w) and len(keys_for(w)) >= 4]
        if not places:
            continue
        i = rng.choice(places)
        kind = KINDS[n % len(KINDS)]
        typo = slip(keys_for(row[i]), kind, rng)
        if not typo or typo == keys_for(row[i]):
            continue
        keys = [keys_for(w) if re.fullmatch(r"[가-힣]+", w) else w for w in row]
        keys[i] = typo
        lines.append(" ".join(keys))
        marks.append((row, i, kind, typo))
    counts, right_by_kind, total_by_kind, others, wrong = Counter(), Counter(), Counter(), 0, []
    for (row, i, kind, typo), out in zip(marks, type_lines(cli, lines)):
        if len(out) != len(row):
            continue
        what = outcome(out[i], row[i])
        counts[what] += 1
        total_by_kind[kind] += 1
        right_by_kind[kind] += what == "right"
        others += sum(1 for j, w in enumerate(row) if j != i and out[j] != w)
        if what == "another word":
            wrong.append(f"{row[i]}: {typo} → {out[i]}")
    total = sum(counts.values())
    print(f"\n{label}, one slip in each: {total} words")
    print("  went in " + ", ".join(f"{k} {counts[k]} ({counts[k] / total:.1%})" for k in ("right", "English", "loose jamo", "another word")))
    print("  right by slip: " + ", ".join(f"{k} {right_by_kind[k]}/{total_by_kind[k]}" for k in KINDS if total_by_kind[k]))
    print(f"  other words of those lines that went in wrong: {others}")
    for w in wrong[:listed]:
        print(f"    {w}")


def as_written(cli: str, rows: list[list[str]], label: str) -> None:
    lines = [" ".join(keys_for(w) if re.fullmatch(r"[가-힣]+", w) else w for w in row) for row in rows]
    out = type_lines(cli, lines)
    wrong = sum(1 for row, o in zip(rows, out) for w, x in zip(row, o) if w != x)
    print(f"{label} as written: {len(rows)} lines, {sum(map(len, rows))} words, {wrong} went in wrong")


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    cli, sentences_path, english_path = sys.argv[1:4]
    listed = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    sentences = []
    for line in open(sentences_path, encoding="utf-8"):
        words = line.rstrip("\n").split("\t")[-1].strip().rstrip(".?!").split(" ")
        if words and all(re.fullmatch(r"[가-힣]+", w) for w in words):
            sentences.append(words)
    repo = Path(__file__).resolve().parent.parent
    files = [repo / "README.md", repo / "CONTRIBUTING.md", repo / ".github/release-notes.md"]
    files += sorted(Path(p) for p in glob.glob(str(repo / "docs/*.md")))
    prose = []
    for path in files:
        for line in path.read_text(encoding="utf-8").splitlines():
            tokens = re.findall(r"[가-힣]+|[A-Za-z]+", line)
            if sum(1 for t in tokens if re.fullmatch(r"[가-힣]+", t)) >= 3:
                prose.append(tokens)

    as_written(cli, sentences, "Tatoeba sentences")
    as_written(cli, prose, "Prose")
    english = [w for w in (line.split()[0] for line in open(english_path, encoding="utf-8")) if re.fullmatch(r"[a-z]{2,}", w)][:5000]
    for label, before in (("alone", ""), ("after 그건", "rmrjs ")):
        out = type_lines(cli, [before + w for w in english])
        print(f"English words {label}: {len(english)}, went in as something else: {sum(1 for w, o in zip(english, out) if not o or o[-1] != w)}")
    with_slips(cli, sentences, 1, "Tatoeba sentences", listed)
    with_slips(cli, prose, 2, "Prose", listed)


if __name__ == "__main__":
    main()
