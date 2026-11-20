"""Normalized Dual-Layer Notes Engine & Xcode-Style Case-Sensitive Search.

Allows viewing clean normalized text (`Norma`) while running Xcode-style
case-sensitive (`Aa`), whole-word (`W`), and regex (`.*`) search against
both the raw `MUNSC` layer (`NormA`, `Norm4`, `Norma4`) and the normalized
layer via the `AXIF` span index.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import re
from typing import Any, Iterable, Sequence

from .acode9 import generate_acode9, validate_acode9
from .axif import (
    AXIFEntry,
    AXIFMetadata,
    DEFAULT_CANONICAL_FORMS,
    DEFAULT_PROTECTED_TOKENS,
    MUNSCRule,
    TextSegment,
    compile_axif,
)
from .base38 import TimestampLike


@dataclass(frozen=True, slots=True)
class SearchMatch:
    """A single dual-layer search hit linking raw MUNSC, normalized text, and AXIF."""

    query: str
    matched_text: str
    layer: str
    raw_offset: int
    raw_end: int
    normalized_offset: int
    normalized_end: int
    line_number: int
    column: int
    snippet: str
    raw_snippet: str
    axif_entry: AXIFEntry | None
    acode9: str
    note_title: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "query": self.query,
            "matched_text": self.matched_text,
            "layer": self.layer,
            "raw_offset": self.raw_offset,
            "raw_end": self.raw_end,
            "normalized_offset": self.normalized_offset,
            "normalized_end": self.normalized_end,
            "line_number": self.line_number,
            "column": self.column,
            "snippet": self.snippet,
            "raw_snippet": self.raw_snippet,
            "axif_entry": self.axif_entry.to_dict() if self.axif_entry else None,
            "acode9": self.acode9,
            "note_title": self.note_title,
        }


def _line_col_at(text: str, offset: int) -> tuple[int, int]:
    clamped = max(0, min(offset, len(text)))
    prefix = text[:clamped]
    line = prefix.count("\n") + 1
    last_nl = prefix.rfind("\n")
    col = clamped + 1 if last_nl == -1 else clamped - last_nl
    return line, col


def _snippet_around(text: str, start: int, end: int, radius: int = 24) -> str:
    left = max(0, start - radius)
    right = min(len(text), end + radius)
    prefix = "..." if left > 0 else ""
    suffix = "..." if right < len(text) else ""
    return f"{prefix}{text[left:right]}{suffix}"


def _compile_pattern(
    query: str, *, case_sensitive: bool, whole_word: bool, regex: bool
) -> re.Pattern[str]:
    flags = 0 if case_sensitive else re.IGNORECASE
    body = query if regex else re.escape(query)
    if whole_word:
        body = rf"(?<!\w)(?:{body})(?!\w)"
    return re.compile(body, flags)


class AscensionNote:
    """A note storing raw MUNSC text, normalized text, owner Acode9, and AXIF index."""

    def __init__(
        self,
        *,
        title: str,
        raw_text: str,
        normalized_text: str,
        owner_acode9: str,
        axif: AXIFMetadata,
        segments: list[TextSegment],
        rules: Sequence[MUNSCRule] = (),
        canonical_forms: Iterable[str] = DEFAULT_CANONICAL_FORMS,
        protected_tokens: Iterable[str] = DEFAULT_PROTECTED_TOKENS,
        auto_detect: bool = True,
    ) -> None:
        self.title = title
        self.raw_text = raw_text
        self.normalized_text = normalized_text
        self.owner_acode9 = owner_acode9
        self.axif = axif
        self._segments = segments
        self.rules = list(rules)
        self.canonical_forms = set(canonical_forms)
        self.protected_tokens = set(protected_tokens)
        self.auto_detect = auto_detect

    @classmethod
    def create(
        cls,
        raw_text: str,
        *,
        owner_acode9: str | None = None,
        title: str = "Untitled",
        rules: Sequence[MUNSCRule] = (),
        canonical_forms: Iterable[str] = DEFAULT_CANONICAL_FORMS,
        protected_tokens: Iterable[str] = DEFAULT_PROTECTED_TOKENS,
        auto_detect: bool = True,
        timestamp: TimestampLike = None,
    ) -> AscensionNote:
        acode = owner_acode9 or generate_acode9(timestamp, mode="good1a")
        validation = validate_acode9(acode, allow_dash=True, filter_profanity=False)
        if not validation.valid:
            raise ValueError(f"Invalid owner Acode9 {acode!r}: {validation.reasons}")

        canon_set = set(canonical_forms)
        prot_set = set(protected_tokens)
        normalized_text, metadata, segments = compile_axif(
            raw_text,
            acode,
            rules=rules,
            canonical_forms=canon_set,
            protected_tokens=prot_set,
            auto_detect=auto_detect,
            timestamp=timestamp,
        )
        return cls(
            title=title,
            raw_text=raw_text,
            normalized_text=normalized_text,
            owner_acode9=acode,
            axif=metadata,
            segments=segments,
            rules=rules,
            canonical_forms=canon_set,
            protected_tokens=prot_set,
            auto_detect=auto_detect,
        )

    def update_raw_text(
        self, new_raw_text: str, *, timestamp: TimestampLike = None
    ) -> None:
        """Replace raw text and recompile normalized output + AXIF index."""
        normalized_text, metadata, segments = compile_axif(
            new_raw_text,
            self.owner_acode9,
            rules=self.rules,
            canonical_forms=self.canonical_forms,
            protected_tokens=self.protected_tokens,
            auto_detect=self.auto_detect,
            timestamp=timestamp,
        )
        self.raw_text = new_raw_text
        self.normalized_text = normalized_text
        self.axif = metadata
        self._segments = segments

    def render(self, view: str = "normalized") -> str:
        """Render either 'normalized' (clean human-readable) or 'raw' (MUNSC) text."""
        if view == "normalized":
            return self.normalized_text
        if view == "raw":
            return self.raw_text
        raise ValueError(f"Unknown view {view!r}; expected 'normalized' or 'raw'")

    def _map_raw_span_to_norm(
        self, raw_start: int, raw_end: int
    ) -> tuple[int, int, AXIFEntry | None]:
        norm_starts: list[int] = []
        norm_ends: list[int] = []
        matched_entry: AXIFEntry | None = None

        for seg in self._segments:
            if seg.raw_end <= raw_start or seg.raw_start >= raw_end:
                continue
            if seg.axif_entry is not None:
                matched_entry = seg.axif_entry
                norm_starts.append(seg.norm_start)
                norm_ends.append(seg.norm_end)
            else:
                delta_start = max(0, raw_start - seg.raw_start)
                delta_end = min(seg.raw_end, raw_end) - seg.raw_start
                norm_starts.append(seg.norm_start + delta_start)
                norm_ends.append(seg.norm_start + delta_end)

        if not norm_starts:
            return raw_start, raw_end, None
        return min(norm_starts), max(norm_ends), matched_entry

    def _map_norm_span_to_raw(
        self, norm_start: int, norm_end: int
    ) -> tuple[int, int, AXIFEntry | None]:
        raw_starts: list[int] = []
        raw_ends: list[int] = []
        matched_entry: AXIFEntry | None = None

        for seg in self._segments:
            if seg.norm_end <= norm_start or seg.norm_start >= norm_end:
                continue
            if seg.axif_entry is not None:
                matched_entry = seg.axif_entry
                raw_starts.append(seg.raw_start)
                raw_ends.append(seg.raw_end)
            else:
                delta_start = max(0, norm_start - seg.norm_start)
                delta_end = min(seg.norm_end, norm_end) - seg.norm_start
                raw_starts.append(seg.raw_start + delta_start)
                raw_ends.append(seg.raw_start + delta_end)

        if not raw_starts:
            return norm_start, norm_end, None
        return min(raw_starts), max(raw_ends), matched_entry

    def search(
        self,
        query: str,
        *,
        case_sensitive: bool = True,
        whole_word: bool = False,
        regex: bool = False,
        view_layer: str = "dual",
    ) -> list[SearchMatch]:
        """Xcode-style search across dual-layer (AXIF + normalized + raw) note text.

        `view_layer`:
          - 'dual' (default): searches raw MUNSC layer and normalized layer,
            mapping hits across both layers and deduplicating by normalized span.
          - 'raw': searches raw MUNSC text only.
          - 'normalized': searches normalized text only.
        """
        if not query:
            return []
        if view_layer not in ("dual", "raw", "normalized"):
            raise ValueError(
                f"Unknown view_layer {view_layer!r}; expected 'dual', 'raw', or 'normalized'"
            )

        pattern = _compile_pattern(
            query,
            case_sensitive=case_sensitive,
            whole_word=whole_word,
            regex=regex,
        )

        results: list[SearchMatch] = []
        seen_norm_spans: set[tuple[int, int]] = set()

        if view_layer in ("dual", "raw"):
            for m in pattern.finditer(self.raw_text):
                raw_start, raw_end = m.span()
                norm_start, norm_end, entry = self._map_raw_span_to_norm(
                    raw_start, raw_end
                )
                seen_norm_spans.add((norm_start, norm_end))
                line, col = _line_col_at(self.normalized_text, norm_start)
                results.append(
                    SearchMatch(
                        query=query,
                        matched_text=m.group(0),
                        layer="raw" if view_layer == "raw" else "dual:raw",
                        raw_offset=raw_start,
                        raw_end=raw_end,
                        normalized_offset=norm_start,
                        normalized_end=norm_end,
                        line_number=line,
                        column=col,
                        snippet=_snippet_around(
                            self.normalized_text, norm_start, norm_end
                        ),
                        raw_snippet=_snippet_around(self.raw_text, raw_start, raw_end),
                        axif_entry=entry,
                        acode9=self.owner_acode9,
                        note_title=self.title,
                    )
                )

        if view_layer in ("dual", "normalized"):
            for m in pattern.finditer(self.normalized_text):
                norm_start, norm_end = m.span()
                if view_layer == "dual" and (norm_start, norm_end) in seen_norm_spans:
                    continue
                raw_start, raw_end, entry = self._map_norm_span_to_raw(
                    norm_start, norm_end
                )
                line, col = _line_col_at(self.normalized_text, norm_start)
                results.append(
                    SearchMatch(
                        query=query,
                        matched_text=m.group(0),
                        layer=(
                            "normalized"
                            if view_layer == "normalized"
                            else "dual:normalized"
                        ),
                        raw_offset=raw_start,
                        raw_end=raw_end,
                        normalized_offset=norm_start,
                        normalized_end=norm_end,
                        line_number=line,
                        column=col,
                        snippet=_snippet_around(
                            self.normalized_text, norm_start, norm_end
                        ),
                        raw_snippet=_snippet_around(self.raw_text, raw_start, raw_end),
                        axif_entry=entry,
                        acode9=self.owner_acode9,
                        note_title=self.title,
                    )
                )

        results.sort(key=lambda r: (r.normalized_offset, r.raw_offset))
        return results

    def to_dict(self) -> dict[str, Any]:
        return {
            "title": self.title,
            "owner_acode9": self.owner_acode9,
            "raw_text": self.raw_text,
            "normalized_text": self.normalized_text,
            "axif": self.axif.to_dict(),
            "canonical_forms": sorted(self.canonical_forms),
            "protected_tokens": sorted(self.protected_tokens),
            "auto_detect": self.auto_detect,
        }

    def to_json(self, *, indent: int | None = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent, ensure_ascii=False)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> AscensionNote:
        axif_data = data["axif"]
        rules = [MUNSCRule.from_dict(r) for r in axif_data.get("rules", [])]
        return cls.create(
            raw_text=str(data["raw_text"]),
            owner_acode9=str(data["owner_acode9"]),
            title=str(data.get("title", "Untitled")),
            rules=rules,
            canonical_forms=data.get("canonical_forms", DEFAULT_CANONICAL_FORMS),
            protected_tokens=data.get("protected_tokens", DEFAULT_PROTECTED_TOKENS),
            auto_detect=bool(data.get("auto_detect", True)),
        )


class AscensionNotesStore:
    """In-memory collection of AscensionNotes indexed by owner Acode9."""

    def __init__(self, notes: Iterable[AscensionNote] = ()) -> None:
        self._notes: dict[str, AscensionNote] = {}
        for note in notes:
            self.add_note(note)

    def add_note(self, note: AscensionNote) -> None:
        self._notes[note.owner_acode9] = note

    def get_note(self, acode9: str) -> AscensionNote | None:
        return self._notes.get(acode9)

    def list_notes(self) -> list[AscensionNote]:
        return list(self._notes.values())

    def search_all(
        self,
        query: str,
        *,
        case_sensitive: bool = True,
        whole_word: bool = False,
        regex: bool = False,
        view_layer: str = "dual",
    ) -> list[SearchMatch]:
        matches: list[SearchMatch] = []
        for note in self._notes.values():
            matches.extend(
                note.search(
                    query,
                    case_sensitive=case_sensitive,
                    whole_word=whole_word,
                    regex=regex,
                    view_layer=view_layer,
                )
            )
        return matches

    def export_bundle(self, *, indent: int | None = 2) -> str:
        return json.dumps(
            {"notes": [n.to_dict() for n in self._notes.values()]},
            indent=indent,
            ensure_ascii=False,
        )

    @classmethod
    def import_bundle(cls, payload: str) -> AscensionNotesStore:
        data = json.loads(payload)
        return cls(AscensionNote.from_dict(item) for item in data.get("notes", []))
