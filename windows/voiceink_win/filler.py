"""Filler-word removal, run between transcription and paste.

Word-list format, one entry per line (`#` starts a comment):
  um        always removed, as a whole word, with a trailing comma or period
  ~like     ambiguous: removed only when set off by commas or at a sentence edge
            ("we should, like, ship it" loses it, "I like it" keeps it)
"""

import re
from pathlib import Path

DEFAULT_WORDS_FILE = Path(__file__).with_name("filler_words.txt")

# Marks a removed filler that started a sentence, so the next word gets its capital.
_CAP = "\x00"


def load_words(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    return [w for w in (line.split("#", 1)[0].strip() for line in lines) if w]


def _phrase(word: str) -> str:
    return r"\s+".join(re.escape(part) for part in word.split())


def _cap_if_upper(match: re.Match) -> str:
    return _CAP if match.group("w")[0].isupper() else ""


def remove_fillers(text: str, words: list[str]) -> str:
    for word in words:
        ambiguous = word.startswith("~")
        w = rf"(?P<w>\b{_phrase(word.lstrip('~').strip())}\b)"
        text = re.sub(rf",\s*{w}\s*,", "", text, flags=re.I)
        if ambiguous:
            text = re.sub(rf",\s*{w}(?=\s*[.!?]|\s*$)", "", text, flags=re.I)
            text = re.sub(rf"(?:^|(?<=[.!?]\s)){w}\s*,\s*", _cap_if_upper, text, flags=re.I)
        else:
            text = re.sub(rf"{w}[,.]?", _cap_if_upper, text, flags=re.I)

    text = re.sub(rf"{_CAP}\s*(\w)", lambda m: m.group(1).upper(), text)
    text = text.replace(_CAP, "")
    text = re.sub(r"\s+([,.!?])", r"\1", text)
    text = re.sub(r",+\s*([,.!?])", r"\1", text)
    text = re.sub(r"^[\s,.]+|[\s,]+$", "", text)
    return re.sub(r"\s{2,}", " ", text)
