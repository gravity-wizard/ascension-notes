"""AXIF (Ascension eXchangeable Identifier Format) & MUNSC Normalization Engine.

Supports notes whose raw text embeds MUNSCs (Multiple Unique Non-Special Characters,
such as `NormA`, `Norm4`, `Norma4`) while rendering clean human-readable output
(`Norma`) and preserving an EXIF-like AXIF metadata index of:
  (token, normalized_form, offset, acode9, munsc_rule)
alongside exact raw <-> normalized span mappings.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import json
import re
from typing import Any, Iterable, Sequence

from .acode9 import validate_acode9
from .base38 import TimestampLike, jesus_clock

AXIF_VERSION: str = "AXIF/1.0"

DEFAULT_PROTECTED_TOKENS: frozenset[str] = frozenset(
    {
        "Acode9",
        "Acodes1a",
        "Base38",
        "First1a",
        "good1a",
        "second1a",
        "Hydrogen4",
        "AXIF",
        "MUNSC",
        "MUNSCs",
        "SwiftUI",
        "macOS",
        "iOS",
        "Xcode",
        "Time0",
        "T0UX",
    }
)

DEFAULT_CANONICAL_FORMS: frozenset[str] = frozenset({"Norma"})

_LEET_CHAR_MAP: dict[str, str] = {
    "0": "o",
    "1": "i",
    "3": "e",
    "4": "a",
    "5": "s",
    "7": "t",
}

# Recognizes either a 9-char Acode9 identifier (protected) or an alphanumeric word token
_TOKEN_SCAN_RE = re.compile(
    r"A[a-z][0-9a-z|\^]{2}[\^\-][0-9a-z|\^]{4}|[A-Za-z0-9]+"
)
_TRAILING_CAP_RE = re.compile(r"^[A-Z][a-z]{2,}[A-Z]$")
_INTERNAL_LEET_RE = re.compile(r"^[A-Za-z]+[013457][A-Za-z]+$")
_TRAILING_LEET_CONSONANT_RE = re.compile(
    r"^[A-Z][a-z]+[bcdfghjklmnpqrstvwxyz][013457]$"
)
_TRAILING_DIGIT_RE = re.compile(r"^[A-Za-z]{2,}[0-9]$")


@dataclass(frozen=True, slots=True)
class MUNSCRule:
    """Declarative normalization rule for a MUNSC token or pattern."""

    name: str
    pattern: str
    replacement: str
    is_regex: bool = False
    description: str = ""

    def apply(self, token: str) -> str | None:
        if self.is_regex:
            new_val, count = re.subn(self.pattern, self.replacement, token)
            if count > 0 and new_val != token:
                return new_val
            return None
        if token == self.pattern and self.replacement != token:
            return self.replacement
        return None

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "pattern": self.pattern,
            "replacement": self.replacement,
            "is_regex": self.is_regex,
            "description": self.description,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> MUNSCRule:
        return cls(
            name=str(data["name"]),
            pattern=str(data["pattern"]),
            replacement=str(data["replacement"]),
            is_regex=bool(data.get("is_regex", False)),
            description=str(data.get("description", "")),
        )


DEFAULT_MUNSC_RULES: tuple[MUNSCRule, ...] = (
    MUNSCRule(
        name="munsc_trailing_cap_norma",
        pattern="NormA",
        replacement="Norma",
        description="Normalize trailing uppercase MUNSC 'NormA' -> 'Norma'",
    ),
    MUNSCRule(
        name="munsc_leet_4_to_a",
        pattern="Norm4",
        replacement="Norma",
        description="Normalize leet-digit MUNSC 'Norm4' -> 'Norma'",
    ),
    MUNSCRule(
        name="munsc_trailing_disambiguator",
        pattern="Norma4",
        replacement="Norma",
        description="Normalize trailing disambiguator MUNSC 'Norma4' -> 'Norma'",
    ),
)


@dataclass(frozen=True, slots=True)
class AXIFEntry:
    """EXIF-like metadata index entry for a single MUNSC token occurrence."""

    token: str
    normalized_form: str
    offset: int
    acode9: str
    munsc_rule: str
    length: int = 0
    normalized_offset: int = 0
    normalized_length: int = 0

    def __post_init__(self) -> None:
        if self.length == 0:
            object.__setattr__(self, "length", len(self.token))
        if self.normalized_length == 0:
            object.__setattr__(self, "normalized_length", len(self.normalized_form))

    @property
    def raw_end(self) -> int:
        return self.offset + self.length

    @property
    def normalized_end(self) -> int:
        return self.normalized_offset + self.normalized_length

    def to_tuple(self) -> tuple[str, str, int, str, str]:
        """Return the canonical 5-tuple (token, normalized_form, offset, acode9, munsc_rule)."""
        return (
            self.token,
            self.normalized_form,
            self.offset,
            self.acode9,
            self.munsc_rule,
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "token": self.token,
            "normalized_form": self.normalized_form,
            "offset": self.offset,
            "length": self.length,
            "normalized_offset": self.normalized_offset,
            "normalized_length": self.normalized_length,
            "acode9": self.acode9,
            "munsc_rule": self.munsc_rule,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> AXIFEntry:
        return cls(
            token=str(data["token"]),
            normalized_form=str(data["normalized_form"]),
            offset=int(data["offset"]),
            acode9=str(data["acode9"]),
            munsc_rule=str(data["munsc_rule"]),
            length=int(data.get("length", len(str(data["token"])))),
            normalized_offset=int(data.get("normalized_offset", data["offset"])),
            normalized_length=int(
                data.get("normalized_length", len(str(data["normalized_form"])))
            ),
        )


@dataclass(frozen=True, slots=True)
class TextSegment:
    """Maps a contiguous raw span to its corresponding normalized span."""

    raw_start: int
    raw_end: int
    norm_start: int
    norm_end: int
    axif_entry: AXIFEntry | None = None


@dataclass(slots=True)
class AXIFMetadata:
    """EXIF-style AXIF sidecar / header metadata for an AscensionNote."""

    acode9: str
    jesus_clock: str
    raw_sha256: str
    normalized_sha256: str
    entries: list[AXIFEntry] = field(default_factory=list)
    version: str = AXIF_VERSION
    rules: list[MUNSCRule] = field(default_factory=list)

    @property
    def munsc_count(self) -> int:
        return len(self.entries)

    def entries_for_token(
        self, token: str, *, case_sensitive: bool = True
    ) -> list[AXIFEntry]:
        if case_sensitive:
            return [e for e in self.entries if e.token == token]
        target = token.lower()
        return [e for e in self.entries if e.token.lower() == target]

    def entries_for_normalized(
        self, normalized_form: str, *, case_sensitive: bool = True
    ) -> list[AXIFEntry]:
        if case_sensitive:
            return [e for e in self.entries if e.normalized_form == normalized_form]
        target = normalized_form.lower()
        return [e for e in self.entries if e.normalized_form.lower() == target]

    def to_dict(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "acode9": self.acode9,
            "jesus_clock": self.jesus_clock,
            "raw_sha256": self.raw_sha256,
            "normalized_sha256": self.normalized_sha256,
            "munsc_count": self.munsc_count,
            "entries": [entry.to_dict() for entry in self.entries],
            "rules": [rule.to_dict() for rule in self.rules],
        }

    def to_json(self, *, indent: int | None = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent, ensure_ascii=False)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> AXIFMetadata:
        return cls(
            version=str(data.get("version", AXIF_VERSION)),
            acode9=str(data["acode9"]),
            jesus_clock=str(data["jesus_clock"]),
            raw_sha256=str(data["raw_sha256"]),
            normalized_sha256=str(data["normalized_sha256"]),
            entries=[AXIFEntry.from_dict(e) for e in data.get("entries", [])],
            rules=[MUNSCRule.from_dict(r) for r in data.get("rules", [])],
        )

    @classmethod
    def from_json(cls, payload: str) -> AXIFMetadata:
        return cls.from_dict(json.loads(payload))


def normalize_munsc_token(
    token: str,
    *,
    rules: Sequence[MUNSCRule] = (),
    canonical_forms: Iterable[str] = DEFAULT_CANONICAL_FORMS,
    protected_tokens: Iterable[str] = DEFAULT_PROTECTED_TOKENS,
    auto_detect: bool = True,
) -> tuple[str, str] | None:
    """Return `(normalized_form, rule_name)` if `token` is a MUNSC, else None."""
    if not token:
        return None

    protected = set(protected_tokens)
    if token in protected:
        return None

    if len(token) == 9 and validate_acode9(token, filter_profanity=False).valid:
        return None

    # 1. Custom user-supplied rules first
    for rule in rules:
        replaced = rule.apply(token)
        if replaced is not None:
            return replaced, rule.name

    # 2. Built-in default MUNSC rules
    for rule in DEFAULT_MUNSC_RULES:
        replaced = rule.apply(token)
        if replaced is not None:
            return replaced, rule.name

    if not auto_detect:
        return None

    # 3. Heuristic MUNSC detection
    # 3a. Trailing uppercase letter after lowercase run (e.g. 'TestA' -> 'Testa')
    if _TRAILING_CAP_RE.match(token):
        return token[:-1] + token[-1].lower(), "munsc_trailing_cap"

    # 3b. Internal leet digit flanked by letters (e.g. 'Sar4h' -> 'Sarah')
    if _INTERNAL_LEET_RE.match(token):
        normalized = "".join(_LEET_CHAR_MAP.get(ch, ch) for ch in token)
        if normalized != token:
            return normalized, "munsc_internal_leet"

    # 3c. Trailing leet digit after consonant (e.g. 'Pet3' -> 'Pete')
    if _TRAILING_LEET_CONSONANT_RE.match(token):
        last_char = _LEET_CHAR_MAP.get(token[-1], token[-1])
        return token[:-1] + last_char, "munsc_trailing_leet"

    # 3d. Trailing numeric disambiguator matching a known canonical form (e.g. 'Norma4' -> 'Norma')
    canon_set = set(canonical_forms)
    if _TRAILING_DIGIT_RE.match(token) and token[:-1] in canon_set:
        return token[:-1], "munsc_trailing_disambiguator"

    return None


def compile_axif(
    raw_text: str,
    owner_acode9: str,
    *,
    rules: Sequence[MUNSCRule] = (),
    canonical_forms: Iterable[str] = DEFAULT_CANONICAL_FORMS,
    protected_tokens: Iterable[str] = DEFAULT_PROTECTED_TOKENS,
    auto_detect: bool = True,
    timestamp: TimestampLike = None,
) -> tuple[str, AXIFMetadata, list[TextSegment]]:
    """Normalize `raw_text`, emit `AXIFMetadata`, and build exact raw<->normalized segments."""
    validation = validate_acode9(owner_acode9, allow_dash=True, filter_profanity=False)
    if not validation.valid:
        raise ValueError(f"Invalid owner Acode9 {owner_acode9!r}: {validation.reasons}")

    norm_parts: list[str] = []
    entries: list[AXIFEntry] = []
    segments: list[TextSegment] = []

    raw_cursor = 0
    norm_cursor = 0

    for match in _TOKEN_SCAN_RE.finditer(raw_text):
        start, end = match.span()
        token = match.group(0)

        if start > raw_cursor:
            plain = raw_text[raw_cursor:start]
            norm_parts.append(plain)
            segments.append(
                TextSegment(
                    raw_start=raw_cursor,
                    raw_end=start,
                    norm_start=norm_cursor,
                    norm_end=norm_cursor + len(plain),
                    axif_entry=None,
                )
            )
            norm_cursor += len(plain)

        result = normalize_munsc_token(
            token,
            rules=rules,
            canonical_forms=canonical_forms,
            protected_tokens=protected_tokens,
            auto_detect=auto_detect,
        )
        if result is not None:
            normalized_form, rule_name = result
            entry = AXIFEntry(
                token=token,
                normalized_form=normalized_form,
                offset=start,
                length=len(token),
                normalized_offset=norm_cursor,
                normalized_length=len(normalized_form),
                acode9=owner_acode9,
                munsc_rule=rule_name,
            )
            entries.append(entry)
            norm_parts.append(normalized_form)
            segments.append(
                TextSegment(
                    raw_start=start,
                    raw_end=end,
                    norm_start=norm_cursor,
                    norm_end=norm_cursor + len(normalized_form),
                    axif_entry=entry,
                )
            )
            norm_cursor += len(normalized_form)
        else:
            norm_parts.append(token)
            segments.append(
                TextSegment(
                    raw_start=start,
                    raw_end=end,
                    norm_start=norm_cursor,
                    norm_end=norm_cursor + len(token),
                    axif_entry=None,
                )
            )
            norm_cursor += len(token)

        raw_cursor = end

    if raw_cursor < len(raw_text):
        tail = raw_text[raw_cursor:]
        norm_parts.append(tail)
        segments.append(
            TextSegment(
                raw_start=raw_cursor,
                raw_end=len(raw_text),
                norm_start=norm_cursor,
                norm_end=norm_cursor + len(tail),
                axif_entry=None,
            )
        )

    normalized_text = "".join(norm_parts)
    raw_sha = hashlib.sha256(raw_text.encode("utf-8")).hexdigest()
    norm_sha = hashlib.sha256(normalized_text.encode("utf-8")).hexdigest()

    metadata = AXIFMetadata(
        acode9=owner_acode9,
        jesus_clock=jesus_clock(timestamp, min_width=2),
        raw_sha256=raw_sha,
        normalized_sha256=norm_sha,
        entries=entries,
        rules=list(rules),
    )

    return normalized_text, metadata, segments
