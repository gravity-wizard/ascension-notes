"""Normalized Dual-Layer Notes Engine & Xcode-Style Case-Sensitive Search.

Allows viewing clean normalized text (`Norma`) while running Xcode-style
case-sensitive (`Aa`), whole-word (`W`), and regex (`.*`) search against
both the raw `MUNSC` layer (`NormA`, `Norm4`, `Norma4`) and the normalized
layer via the `AXIF` span index.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass
import json
from pathlib import Path
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


@dataclass(frozen=True, slots=True)
class NoteAttachment:
    """Lossless PNG attachment metadata compatible with Swift StoredNote.attachments."""

    id: str
    filename: str
    relative_path: str
    pixel_width: int
    pixel_height: int
    created_at: str = ""

    @property
    def short_id(self) -> str:
        return self.id[:4].lower()

    @property
    def marker_text(self) -> str:
        safe_name = self.filename.replace("]", ")").replace("\n", " ")
        return f"▸[Image: {safe_name} #{self.short_id}]"

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "filename": self.filename,
            "relative_path": self.relative_path,
            "pixel_width": self.pixel_width,
            "pixel_height": self.pixel_height,
            "created_at": self.created_at,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> NoteAttachment:
        return cls(
            id=str(data["id"]),
            filename=str(data["filename"]),
            relative_path=str(data.get("relative_path", data.get("relativePath", ""))),
            pixel_width=int(data.get("pixel_width", data.get("pixelWidth", 1))),
            pixel_height=int(data.get("pixel_height", data.get("pixelHeight", 1))),
            created_at=str(data.get("created_at", data.get("createdAt", ""))),
        )


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
        attachments: Sequence[NoteAttachment] = (),
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
        self.attachments: list[NoteAttachment] = list(attachments)

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
        attachments: Sequence[NoteAttachment] = (),
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
            attachments=attachments,
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
            "attachments": [att.to_dict() for att in self.attachments],
        }

    def to_json(self, *, indent: int | None = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent, ensure_ascii=False)

    def export_clean_with_axif_footer(self, *, use_base64: bool = True) -> str:
        compact_json = self.axif.to_json(indent=None)
        if use_base64:
            payload = base64.b64encode(compact_json.encode("utf-8")).decode("ascii")
        else:
            payload = compact_json
        return f"{self.normalized_text}\n\n[AXIF: {self.owner_acode9} | {payload}]"

    def export_slogbog_bbcode(self) -> str:
        axif_json = self.axif.to_json(indent=2)
        return (
            f'[quote="Acode9: {self.owner_acode9} | Clock: {self.axif.jesus_clock}"]\n'
            f"{self.normalized_text}\n"
            "[/quote]\n"
            f"[b]Acode9:[/b] [code]{self.owner_acode9}[/code] | "
            f"[b]Jesus Clock:[/b] [code]{self.axif.jesus_clock}[/code] | "
            f"[b]MUNSCs:[/b] {self.axif.munsc_count}\n"
            "[spoiler=AXIF][code]\n"
            f"{axif_json}\n"
            "[/code][/spoiler]"
        )

    def export_markdown(
        self,
        *,
        include_frontmatter: bool = True,
        include_axif_footer: bool = True,
        use_raw_text: bool = False,
    ) -> str:
        body = self.raw_text if use_raw_text else self.normalized_text
        parts: list[str] = []

        if include_frontmatter:
            safe_title = (self.title or "Ascension Note").strip().replace('"', '\\"')
            parts.append(
                f"---\n"
                f'title: "{safe_title}"\n'
                f'acode9: "{self.owner_acode9}"\n'
                f'jesus_clock: "{self.axif.jesus_clock}"\n'
                f"munsc_count: {self.axif.munsc_count}\n"
                f'axif_version: "{self.axif.version}"\n'
                f"---"
            )

        for att in self.attachments:
            marker = att.marker_text
            md_image = f"![{att.filename}]({att.relative_path})"
            body = body.replace(marker, md_image)

        parts.append(body)

        if include_axif_footer:
            compact_json = self.axif.to_json(indent=None)
            payload = base64.b64encode(compact_json.encode("utf-8")).decode("ascii")
            parts.append(
                f"<!-- AXIF: {self.owner_acode9} | Clock: {self.axif.jesus_clock} | Payload: {payload} -->"
            )

        return "\n\n".join(parts)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> AscensionNote:
        axif_data = data["axif"]
        rules = [MUNSCRule.from_dict(r) for r in axif_data.get("rules", [])]
        attachments = [
            NoteAttachment.from_dict(att) for att in data.get("attachments", [])
        ]
        return cls.create(
            raw_text=str(data["raw_text"]),
            owner_acode9=str(data["owner_acode9"]),
            title=str(data.get("title", "Untitled")),
            rules=rules,
            canonical_forms=data.get("canonical_forms", DEFAULT_CANONICAL_FORMS),
            protected_tokens=data.get("protected_tokens", DEFAULT_PROTECTED_TOKENS),
            auto_detect=bool(data.get("auto_detect", True)),
            attachments=attachments,
        )


def _resolve_rules_path(folder_or_file: str | Path) -> Path:
    path = Path(folder_or_file)
    if path.suffix.lower() == ".json":
        return path
    return path / "munsc_rules.json"


def load_custom_rules(folder_or_file: str | Path) -> list[MUNSCRule]:
    """Load user-defined MUNSC rules from `munsc_rules.json` in a folder (or explicit file)."""
    target = _resolve_rules_path(folder_or_file)
    if not target.exists():
        return []
    raw_data = json.loads(target.read_text(encoding="utf-8"))
    if isinstance(raw_data, dict):
        raw_items = raw_data.get("rules", [])
    elif isinstance(raw_data, list):
        raw_items = raw_data
    else:
        raise ValueError(f"Invalid munsc_rules.json payload in {target}")
    return [MUNSCRule.from_dict(item) for item in raw_items]


def save_custom_rules(
    rules: Sequence[MUNSCRule], folder_or_file: str | Path
) -> Path:
    """Persist user-defined MUNSC rules to `munsc_rules.json` inside a sync/storage folder."""
    target = _resolve_rules_path(folder_or_file)
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = [rule.to_dict() for rule in rules]
    target.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return target


class AscensionNotesStore:
    """In-memory collection of AscensionNotes indexed by owner Acode9."""

    def __init__(
        self,
        notes: Iterable[AscensionNote] = (),
        custom_rules: Sequence[MUNSCRule] = (),
        sync_folder: str | Path | None = None,
    ) -> None:
        self._notes: dict[str, AscensionNote] = {}
        self.custom_rules: list[MUNSCRule] = list(custom_rules)
        self.sync_folder: Path | None = Path(sync_folder) if sync_folder is not None else None
        if self.sync_folder is not None and not self.custom_rules:
            self.custom_rules = load_custom_rules(self.sync_folder)
        for note in notes:
            self.add_note(note)

    def add_note(self, note: AscensionNote) -> None:
        self._notes[note.owner_acode9] = note

    def get_note(self, acode9: str) -> AscensionNote | None:
        return self._notes.get(acode9)

    def list_notes(self) -> list[AscensionNote]:
        return list(self._notes.values())

    def add_custom_rule(
        self,
        token: str,
        normalized: str,
        *,
        description: str = "",
        is_regex: bool = False,
    ) -> MUNSCRule:
        clean_token = token.strip()
        clean_norm = normalized.strip()
        if not clean_token or not clean_norm or clean_token == clean_norm:
            raise ValueError("Custom MUNSC rule requires non-empty distinct token and normalized form.")

        for idx, existing in enumerate(self.custom_rules):
            if existing.pattern == clean_token and existing.is_regex == is_regex:
                updated = MUNSCRule(
                    name=existing.name,
                    pattern=clean_token,
                    replacement=clean_norm,
                    is_regex=is_regex,
                    description=description.strip()
                    or f"Custom MUNSC '{clean_token}' -> '{clean_norm}'",
                )
                self.custom_rules[idx] = updated
                if self.sync_folder is not None:
                    self.save_custom_rules(self.sync_folder)
                return updated

        slug = "".join(ch if ch.isalnum() else "_" for ch in clean_token)
        candidate = f"custom_{slug}"
        existing_names = {r.name for r in self.custom_rules}
        suffix = 2
        while candidate in existing_names:
            candidate = f"custom_{slug}_{suffix}"
            suffix += 1

        rule = MUNSCRule(
            name=candidate,
            pattern=clean_token,
            replacement=clean_norm,
            is_regex=is_regex,
            description=description.strip()
            or f"Custom MUNSC '{clean_token}' -> '{clean_norm}'",
        )
        self.custom_rules.append(rule)
        if self.sync_folder is not None:
            self.save_custom_rules(self.sync_folder)
        return rule

    def add_skip_vowels_rule(self, token: str, normalized: str) -> MUNSCRule:
        """Add and verify a Skip Vowels MUNSC rule with description 'Skip vowels verified'."""
        return self.add_custom_rule(
            token,
            normalized,
            description="Skip vowels verified",
            is_regex=False,
        )

    def delete_custom_rule(self, name: str) -> bool:
        before = len(self.custom_rules)
        self.custom_rules = [r for r in self.custom_rules if r.name != name]
        removed = len(self.custom_rules) < before
        if removed and self.sync_folder is not None:
            self.save_custom_rules(self.sync_folder)
        return removed

    def save_custom_rules(self, folder_or_file: str | Path | None = None) -> Path:
        target = folder_or_file if folder_or_file is not None else self.sync_folder
        if target is None:
            raise ValueError("No sync_folder or target path provided for saving custom rules.")
        return save_custom_rules(self.custom_rules, target)

    def load_custom_rules(self, folder_or_file: str | Path | None = None) -> list[MUNSCRule]:
        target = folder_or_file if folder_or_file is not None else self.sync_folder
        if target is None:
            raise ValueError("No sync_folder or target path provided for loading custom rules.")
        self.custom_rules = load_custom_rules(target)
        return list(self.custom_rules)

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
            {
                "notes": [n.to_dict() for n in self._notes.values()],
                "custom_rules": [r.to_dict() for r in self.custom_rules],
            },
            indent=indent,
            ensure_ascii=False,
        )

    @classmethod
    def import_bundle(cls, payload: str) -> AscensionNotesStore:
        data = json.loads(payload)
        rules = [MUNSCRule.from_dict(r) for r in data.get("custom_rules", [])]
        return cls(
            (AscensionNote.from_dict(item) for item in data.get("notes", [])),
            custom_rules=rules,
        )
