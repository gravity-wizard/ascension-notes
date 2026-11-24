"""9-Character Acode9 (`Acodes1a`) Architecture & Rolling Pool Generator.

Format: `[BigA][leadLetter][clock2][center][tail4]` (9 characters)
  [0]    : 'A' (BigA, pointing upward)
  [1]    : leadLetter paired to clock[0] ('1'..'9'->'a'..'i', '0'->'z', 'a'..'z'->same)
  [2..3] : first 2 characters of Base-38 Jesus Clock (e.g., '2p', '3x')
  [4]    : center mountain '^' (convertible to '-' via to_dash() / to_caret())
  [5..8] : 4-character Base-38 suffix (in good1a/second1a strict mode:
           [5] and [8] in [a-z], [6..7] in [0-9a-z])
"""

from __future__ import annotations

from dataclasses import dataclass
import random
import re
from typing import AbstractSet, Iterable, Sequence

from .base38 import (
    B38,
    B38_BASE,
    T0UX,
    TimestampLike,
    clock2_from_timestamp,
    coerce_unix_timestamp,
    encode_base38,
    jesus_clock,
)

BIG_A: str = "A"
CENTER_CARET: str = "^"
CENTER_DASH: str = "-"

ASCII_LOWER: str = "abcdefghijklmnopqrstuvwxyz"
ASCII_ALNUM: str = "0123456789abcdefghijklmnopqrstuvwxyz"
B38_SET: frozenset[str] = frozenset(B38)
LOWER_SET: frozenset[str] = frozenset(ASCII_LOWER)
ALNUM_SET: frozenset[str] = frozenset(ASCII_ALNUM)

STRICT_MODES: frozenset[str] = frozenset({"good1a", "second1a"})
ALL_MODES: frozenset[str] = frozenset({"standard", "b38", "good1a", "second1a"})

# YouTube-style ID safety filter substrings (checked case-insensitively across
# tail4, alphanumeric core, and up to 11-char candidate IDs).
DEFAULT_BLOCKED_SUBSTRINGS: tuple[str, ...] = (
    "666",
    "anal",
    "anus",
    "arse",
    "bitch",
    "btch",
    "cock",
    "c0ck",
    "cunt",
    "damn",
    "dick",
    "d1ck",
    "dyke",
    "fag",
    "fck",
    "fuk",
    "fuck",
    "hell",
    "jizz",
    "kike",
    "klan",
    "nazi",
    "nig",
    "n1g",
    "porn",
    "p0rn",
    "puss",
    "rape",
    "shit",
    "sh1t",
    "slut",
    "spic",
    "twat",
    "wank",
    "whor",
    "xxx",
)

_LEET_MAP = str.maketrans(
    {
        "0": "o",
        "1": "i",
        "3": "e",
        "4": "a",
        "5": "s",
        "7": "t",
        "8": "b",
    }
)


def lead_letter_for_clock_char(clock_char: str) -> str:
    """Pair a Base-38 clock[0] character with its lowercase leadLetter.

    Mapping:
      '1'..'9' -> 'a'..'i' (e.g., '2'->'b', '3'->'c', '8'->'h')
      '0'      -> 'z'
      'a'..'z' -> same lowercase letter
      '|' / '_' -> 'x'
      '^' / '-' -> 'y'
    """
    if not isinstance(clock_char, str) or len(clock_char) != 1:
        raise ValueError(f"Expected single character, got {clock_char!r}")
    if clock_char == "_":
        clock_char = "|"
    elif clock_char == "-":
        clock_char = "^"
    if clock_char not in B38_SET:
        raise ValueError(f"Clock character {clock_char!r} is not in B38 alphabet")

    if "1" <= clock_char <= "9":
        return chr(ord("a") + int(clock_char) - 1)
    if clock_char == "0":
        return "z"
    if "a" <= clock_char <= "z":
        return clock_char
    if clock_char == "|":
        return "x"
    if clock_char == "^":
        return "y"
    raise ValueError(f"Unhandled B38 character {clock_char!r}")  # pragma: no cover


def to_dash(code: str) -> str:
    """Convert canonical '^' and '|' to URL/filename-safe '-' and '_'."""
    if not isinstance(code, str) or len(code) != 9:
        raise ValueError(f"Acode9 must be 9 characters, got {code!r}")
    if code[4] not in (CENTER_CARET, CENTER_DASH):
        raise ValueError(f"Invalid center character at index 4 in {code!r}")
    left = code[:4].replace("|", "_")
    right = code[5:].replace("^", "-").replace("|", "_")
    return f"{left}{CENTER_DASH}{right}"


def to_caret(code: str) -> str:
    """Convert URL-safe '-' and '_' back to canonical Base-38 '^' and '|'."""
    if not isinstance(code, str) or len(code) != 9:
        raise ValueError(f"Acode9 must be 9 characters, got {code!r}")
    if code[4] not in (CENTER_CARET, CENTER_DASH):
        raise ValueError(f"Invalid center character at index 4 in {code!r}")
    left = code[:4].replace("_", "|")
    right = code[5:].replace("-", "^").replace("_", "|")
    return f"{left}{CENTER_CARET}{right}"


def is_good1a_tail(tail4: str) -> bool:
    """Return True if tail4 satisfies strict good1a / second1a rules.

    Strict rule: [0] and [3] in [a-z], [1..2] in [0-9a-z].
    """
    return (
        len(tail4) == 4
        and tail4[0] in LOWER_SET
        and tail4[1] in ALNUM_SET
        and tail4[2] in ALNUM_SET
        and tail4[3] in LOWER_SET
    )


def is_clean_id(
    candidate: str,
    *,
    blocked_substrings: Iterable[str] | None = None,
    existing_pool: AbstractSet[str] | None = None,
    block_all_same_tail: bool = True,
    block_repeated_pairs: bool = False,
    ambiguous_chars: str = "",
) -> tuple[bool, list[str]]:
    """YouTube-style 11-char ID filter for Acode9 and candidate IDs.

    Checks:
      1. Collision against `existing_pool` (both canonical '^' and dash '-' forms).
      2. Offensive / profanity substrings (including leetspeak normalized check).
      3. Degenerate repeated patterns (e.g., 'aaaa' or optional repeated pairs).
      4. Optional ambiguous visual characters (if `ambiguous_chars` configured).
    """
    reasons: list[str] = []
    if not candidate or len(candidate) > 11:
        if not candidate:
            reasons.append("empty_candidate")
        else:
            reasons.append("exceeds_11_char_filter_window")

    if existing_pool:
        variants = {candidate}
        if len(candidate) == 9 and candidate[4] in (CENTER_CARET, CENTER_DASH):
            variants.add(to_caret(candidate))
            variants.add(to_dash(candidate))
        if any(v in existing_pool for v in variants):
            reasons.append("pool_collision")

    # Extract tail4 and alphanumeric core for substring scanning
    if len(candidate) == 9 and candidate[4] in (CENTER_CARET, CENTER_DASH):
        tail4 = candidate[5:]
        core = candidate[1:4] + tail4
    else:
        tail4 = candidate[-4:] if len(candidate) >= 4 else candidate
        core = re.sub(r"[\^\-_|]", "", candidate)

    blocked = tuple(
        s.lower()
        for s in (DEFAULT_BLOCKED_SUBSTRINGS if blocked_substrings is None else blocked_substrings)
        if s
    )

    tail_lower = tail4.lower()
    core_lower = core.lower()
    if "666" in tail_lower or "666" in core_lower:
        reasons.append("blocked_substring:666")
    tail_leet = tail_lower.translate(_LEET_MAP)
    core_leet = core_lower.translate(_LEET_MAP)

    for bad in blocked:
        if bad == "666":
            continue
        if bad in tail_lower or bad in core_lower or bad in tail_leet or bad in core_leet:
            reasons.append(f"blocked_substring:{bad}")
            break

    if len(tail4) == 4:
        if block_all_same_tail and len(set(tail4)) == 1:
            reasons.append("all_same_tail_pattern")
        if block_repeated_pairs and tail4[:2] == tail4[2:]:
            reasons.append("repeated_pair_tail_pattern")

    if ambiguous_chars:
        amb_set = set(ambiguous_chars)
        target = tail4 if len(candidate) == 9 else candidate
        if any(ch in amb_set for ch in target):
            reasons.append("ambiguous_character")

    return (len(reasons) == 0, reasons)


@dataclass(frozen=True, slots=True)
class Acode9Parts:
    """Parsed structural components of a 9-character Acode9 identifier."""

    raw: str
    canonical: str
    url_safe: str
    big_a: str
    lead_letter: str
    clock2: str
    center: str
    tail4: str
    mode: str

    @property
    def is_good1a(self) -> bool:
        return self.mode == "good1a"

    def to_dash(self) -> str:
        return self.url_safe

    def to_caret(self) -> str:
        return self.canonical


@dataclass(frozen=True, slots=True)
class ValidationResult:
    """Result of validating an Acode9 identifier."""

    valid: bool
    reasons: tuple[str, ...]
    parts: Acode9Parts | None
    is_good1a: bool


def parse_acode9(code: str, *, allow_dash: bool = True) -> Acode9Parts:
    """Parse a 9-character Acode9 string into its structural parts.

    Raises ValueError if syntax or leadLetter-to-clock2 pairing is invalid.
    """
    if not isinstance(code, str):
        raise ValueError(f"Acode9 must be a str, got {type(code).__name__}")
    if len(code) != 9:
        raise ValueError(f"Acode9 must be exactly 9 characters, got {len(code)} ({code!r})")

    big_a = code[0]
    center = code[4]

    if big_a != BIG_A:
        raise ValueError(f"Acode9[0] must be 'A', got {big_a!r}")

    allowed_centers = (CENTER_CARET, CENTER_DASH) if allow_dash else (CENTER_CARET,)
    if center not in allowed_centers:
        raise ValueError(f"Acode9[4] center must be one of {allowed_centers}, got {center!r}")

    normalized = to_caret(code) if allow_dash else code
    lead_letter = normalized[1]
    clock2 = normalized[2:4]
    tail4 = normalized[5:9]

    for idx, ch in enumerate(clock2):
        if ch not in B38_SET:
            raise ValueError(f"Invalid B38 character {ch!r} in clock2 at index {2 + idx}")

    expected_lead = lead_letter_for_clock_char(clock2[0])
    if lead_letter != expected_lead:
        raise ValueError(
            f"Acode9[1] leadLetter {lead_letter!r} does not match clock[0]={clock2[0]!r} "
            f"(expected {expected_lead!r})"
        )

    for idx, ch in enumerate(tail4):
        if ch not in B38_SET:
            raise ValueError(f"Invalid B38 character {ch!r} in tail4 at index {5 + idx}")

    mode = "good1a" if is_good1a_tail(tail4) else "b38"
    canonical = f"{big_a}{lead_letter}{clock2}{CENTER_CARET}{tail4}"
    url_safe = to_dash(canonical)

    return Acode9Parts(
        raw=code,
        canonical=canonical,
        url_safe=url_safe,
        big_a=big_a,
        lead_letter=lead_letter,
        clock2=clock2,
        center=center,
        tail4=tail4,
        mode=mode,
    )


def validate_acode9(
    code: str,
    *,
    strict: bool = False,
    mode: str | None = None,
    allow_dash: bool = True,
    filter_profanity: bool = True,
    blocked_substrings: Iterable[str] | None = None,
    existing_pool: AbstractSet[str] | None = None,
    block_all_same_tail: bool = True,
    block_repeated_pairs: bool = False,
    ambiguous_chars: str = "",
) -> ValidationResult:
    """Validate an Acode9 identifier against structural, mode, and filter rules."""
    if mode is not None and mode not in ALL_MODES:
        raise ValueError(f"Unknown mode {mode!r}; expected one of {sorted(ALL_MODES)}")

    enforce_strict = strict or (mode in STRICT_MODES)

    try:
        parts = parse_acode9(code, allow_dash=allow_dash)
    except ValueError as exc:
        return ValidationResult(
            valid=False,
            reasons=(str(exc),),
            parts=None,
            is_good1a=False,
        )

    reasons: list[str] = []
    if enforce_strict and not parts.is_good1a:
        reasons.append(
            f"tail4 {parts.tail4!r} does not satisfy good1a/second1a strict rules "
            "([5] and [8] in [a-z], [6..7] in [0-9a-z])"
        )

    if filter_profanity or existing_pool or block_repeated_pairs or ambiguous_chars:
        clean, filter_reasons = is_clean_id(
            parts.canonical,
            blocked_substrings=blocked_substrings if filter_profanity else (),
            existing_pool=existing_pool,
            block_all_same_tail=block_all_same_tail,
            block_repeated_pairs=block_repeated_pairs,
            ambiguous_chars=ambiguous_chars,
        )
        if not clean:
            reasons.extend(filter_reasons)

    return ValidationResult(
        valid=len(reasons) == 0,
        reasons=tuple(reasons),
        parts=parts,
        is_good1a=parts.is_good1a,
    )


def _sample_tail4(mode: str, rng: random.Random) -> str:
    if mode in STRICT_MODES:
        return (
            rng.choice(ASCII_LOWER)
            + rng.choice(ASCII_ALNUM)
            + rng.choice(ASCII_ALNUM)
            + rng.choice(ASCII_LOWER)
        )
    return "".join(rng.choice(B38) for _ in range(4))


def generate_acode9(
    timestamp: TimestampLike = None,
    *,
    mode: str = "good1a",
    url_safe: bool = False,
    tail4: str | None = None,
    existing_pool: AbstractSet[str] | None = None,
    blocked_substrings: Iterable[str] | None = None,
    block_all_same_tail: bool = True,
    block_repeated_pairs: bool = False,
    ambiguous_chars: str = "",
    rng: random.Random | None = None,
    max_attempts: int = 1000,
) -> str:
    """Generate a validated 9-character Acode9 for the given timestamp."""
    if mode not in ALL_MODES:
        raise ValueError(f"Unknown mode {mode!r}; expected one of {sorted(ALL_MODES)}")

    clock2 = clock2_from_timestamp(timestamp)
    lead = lead_letter_for_clock_char(clock2[0])
    center = CENTER_DASH if url_safe else CENTER_CARET
    generator = rng or random.SystemRandom()

    if tail4 is not None:
        candidate = f"{BIG_A}{lead}{clock2}{center}{tail4}"
        res = validate_acode9(
            candidate,
            strict=(mode in STRICT_MODES),
            allow_dash=True,
            filter_profanity=True,
            blocked_substrings=blocked_substrings,
            existing_pool=existing_pool,
            block_all_same_tail=block_all_same_tail,
            block_repeated_pairs=block_repeated_pairs,
            ambiguous_chars=ambiguous_chars,
        )
        if not res.valid:
            raise ValueError(f"Provided tail4 {tail4!r} failed validation: {res.reasons}")
        return candidate

    for _ in range(max_attempts):
        sampled = _sample_tail4(mode, generator)
        candidate = f"{BIG_A}{lead}{clock2}{center}{sampled}"
        res = validate_acode9(
            candidate,
            strict=(mode in STRICT_MODES),
            allow_dash=True,
            filter_profanity=True,
            blocked_substrings=blocked_substrings,
            existing_pool=existing_pool,
            block_all_same_tail=block_all_same_tail,
            block_repeated_pairs=block_repeated_pairs,
            ambiguous_chars=ambiguous_chars,
        )
        if res.valid:
            return candidate

    raise RuntimeError(f"Failed to generate clean Acode9 after {max_attempts} attempts")


@dataclass(frozen=True, slots=True)
class PoolEntry:
    """A single generated entry in a 1-second cadence rolling Acode9 pool."""

    acode9: str
    timestamp: int
    jesus_clock: str
    mode: str

    def to_dict(self) -> dict[str, str | int]:
        return {
            "acode9": self.acode9,
            "timestamp": self.timestamp,
            "jesus_clock": self.jesus_clock,
            "mode": self.mode,
        }


def generate_rolling_pool(
    count: int = 60,
    *,
    start_timestamp: TimestampLike = None,
    cadence_seconds: int = 1,
    mode: str = "good1a",
    url_safe: bool = False,
    existing_pool: Iterable[str] | None = None,
    blocked_substrings: Iterable[str] | None = None,
    block_all_same_tail: bool = True,
    block_repeated_pairs: bool = False,
    ambiguous_chars: str = "",
    rng: random.Random | None = None,
) -> list[PoolEntry]:
    """Generate a collision-free rolling pool of Acode9 IDs at 1-second cadence."""
    if count < 0:
        raise ValueError("count must be non-negative")
    if cadence_seconds <= 0:
        raise ValueError("cadence_seconds must be positive")
    if mode not in ALL_MODES:
        raise ValueError(f"Unknown mode {mode!r}; expected one of {sorted(ALL_MODES)}")

    base_ts = coerce_unix_timestamp(start_timestamp)
    seen: set[str] = set(existing_pool) if existing_pool else set()
    # Ensure both caret and dash forms of pre-existing entries block collisions
    for item in list(seen):
        if len(item) == 9 and item[4] in (CENTER_CARET, CENTER_DASH):
            seen.add(to_caret(item))
            seen.add(to_dash(item))

    generator = rng or random.Random()
    pool: list[PoolEntry] = []

    for i in range(count):
        ts = base_ts + i * cadence_seconds
        code = generate_acode9(
            ts,
            mode=mode,
            url_safe=url_safe,
            existing_pool=seen,
            blocked_substrings=blocked_substrings,
            block_all_same_tail=block_all_same_tail,
            block_repeated_pairs=block_repeated_pairs,
            ambiguous_chars=ambiguous_chars,
            rng=generator,
        )
        seen.add(to_caret(code))
        seen.add(to_dash(code))
        pool.append(
            PoolEntry(
                acode9=code,
                timestamp=ts,
                jesus_clock=jesus_clock(ts, min_width=2),
                mode=mode,
            )
        )

    return pool


# --- 3-Peaks Time Encoding & Wish-Window Conforming / Non-Conforming Tags ---

TRIAD_BASE: int = B38_BASE**3  # 54,872
A8A_DIGITS: str = "12345789"
A8A_COUNT: int = 26 * len(A8A_DIGITS) * 26  # 5,408
WISH_TRIAD_ALIASES: dict[str, str] = {
    "pi1browser": "p1b",
    "pibrowser": "p1b",
    "full5screen": "f5n",
    "fullscreen": "f5n",
}
CONFORMING_MAX_BYTES: int = 575 * 1024
NONCONFORMING_MAX_BYTES: int = 385 * 1024
CONFORMING_QUOTA_COST: int = 1
NONCONFORMING_QUOTA_COST: int = 2

_LEET_I_3PEAKS = str.maketrans({"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "9": "g"})
_LEET_L_3PEAKS = str.maketrans({"0": "o", "1": "l", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "9": "g"})


def is_a8a_triad(triad: str) -> bool:
    """Return True iff triad matches conforming [a-z][1-57-9][a-z] (skipping 0 and 6)."""
    return bool(re.fullmatch(r"[a-z][1-57-9][a-z]", triad or ""))


def is_clean_3peaks_sequence(raw_code: str) -> bool:
    """Return True iff 3-peaks code contains no 69/666 or blocked substrings across boundaries."""
    joined = re.sub(r"[|\^-]", "", (raw_code or "").lower()).replace("_", "0")
    letters_only = re.sub(r"[0-9]", "", joined)
    digits_only = re.sub(r"[a-z]", "", joined)
    leet_i = joined.translate(_LEET_I_3PEAKS)
    leet_l = joined.translate(_LEET_L_3PEAKS)
    if "69" in digits_only or "666" in digits_only:
        return False
    blocked = ("69",) + DEFAULT_BLOCKED_SUBSTRINGS
    for view in (joined, letters_only, leet_i, leet_l):
        for bad in blocked:
            if bad in view:
                return False
    return True


def _decode_msd_triad(msd: str) -> int | None:
    if len(msd) != 3:
        return None
    total = 0
    for ch in msd.lower():
        norm = "0" if ch == "_" else ("^" if ch == "-" else ch)
        idx = B38.find(norm)
        if idx < 0:
            return None
        total = total * B38_BASE + idx
    return total


def _decode_peak_triad(triad: str) -> int | None:
    if len(triad) != 3:
        return None
    total = 0
    for ch in triad.lower():
        norm = "|" if ch == "_" else ("^" if ch == "-" else ch)
        idx = B38.find(norm)
        if idx < 0:
            return None
        total = total * B38_BASE + idx
    return total


def _format_msd_triad(msd_val: int) -> str:
    raw = encode_base38(msd_val).rjust(3, "0")[-3:]
    return raw.replace("0", "_").replace("|", "_").replace("^", "-")


def _encode_peak_canonical(val: int) -> str:
    return encode_base38(val % TRIAD_BASE).rjust(3, "0")[-3:]


def _encode_peak_urlsafe(val: int) -> str:
    return _encode_peak_canonical(val).replace("|", "_").replace("^", "-")


def _a8a_from_index(idx: int) -> str:
    i = idx % A8A_COUNT
    c0 = chr(97 + (i // 208))
    rem = i % 208
    c1 = A8A_DIGITS[rem // 26]
    c2 = chr(97 + (rem % 26))
    return f"{c0}{c1}{c2}"


def parse_wish_window(
    raw: str,
    *,
    max_bytes: int = CONFORMING_MAX_BYTES,
    nonconforming_max_bytes: int = NONCONFORMING_MAX_BYTES,
) -> dict[str, object]:
    """Classify Wish-Window input into blank, conforming (1-2 a8a triads), or nonconforming."""
    trimmed = (raw or "").strip()
    if not trimmed:
        return {
            "kind": "blank",
            "conforming": True,
            "triads": [],
            "canonical_wish": "",
            "quota_cost": CONFORMING_QUOTA_COST,
            "max_bytes": max_bytes,
        }

    tokens = [t for t in re.split(r"[\s^/\-]+", trimmed.lower()) if t]
    if 1 <= len(tokens) <= 2:
        mapped = [WISH_TRIAD_ALIASES.get(t, t) for t in tokens]
        if all(is_a8a_triad(t) and is_clean_3peaks_sequence(t) for t in mapped):
            canonical_wish = "^".join(mapped)
            if is_clean_3peaks_sequence(canonical_wish):
                return {
                    "kind": "conforming",
                    "conforming": True,
                    "triads": mapped,
                    "canonical_wish": canonical_wish,
                    "quota_cost": CONFORMING_QUOTA_COST,
                    "max_bytes": max_bytes,
                }

    return {
        "kind": "nonconforming",
        "conforming": False,
        "triads": [],
        "canonical_wish": "",
        "quota_cost": NONCONFORMING_QUOTA_COST,
        "max_bytes": min(max_bytes, nonconforming_max_bytes),
    }


def mint_conforming_3peaks_slug(
    wish_triads: Sequence[str],
    timestamp: TimestampLike = None,
    *,
    existing_pool: AbstractSet[str] | None = None,
) -> dict[str, object]:
    """Mint a 15-char 3-peaks time code (<msd>-<t1>-<t2>-<s3>) incorporating 1 or 2 conforming triads."""
    if not (1 <= len(wish_triads) <= 2):
        raise ValueError("mint_conforming_3peaks_slug requires 1 or 2 conforming triads")
    clean_wish = [WISH_TRIAD_ALIASES.get(str(t).lower(), str(t).lower()) for t in wish_triads]
    if not all(is_a8a_triad(t) and is_clean_3peaks_sequence(t) for t in clean_wish) or not is_clean_3peaks_sequence(
        "^".join(clean_wish)
    ):
        raise ValueError(f"Non-conforming or blocked wish triads: {wish_triads!r}")

    taken = existing_pool or frozenset()
    sec = max(T0UX, coerce_unix_timestamp(timestamp))
    t1 = clean_wish[0]
    v1 = _decode_peak_triad(t1) or 0

    for _ in range(2000):
        elapsed = sec - T0UX
        msd_val, lsd_val = divmod(elapsed, TRIAD_BASE)
        msd = _format_msd_triad(msd_val)
        if not is_clean_3peaks_sequence(msd.replace("_", "0")):
            sec = T0UX + (msd_val + 1) * TRIAD_BASE
            continue

        if len(clean_wish) == 2:
            t2 = clean_wish[1]
            v2 = _decode_peak_triad(t2) or 0
            needed = (lsd_val - msd_val - v1 - v2) % TRIAD_BASE
            s3_canon = _encode_peak_canonical(needed)
            s3_slug = s3_canon if is_a8a_triad(s3_canon) else _encode_peak_urlsafe(needed)
            canonical = f"{msd}^{t1}^{t2}^{s3_canon}"
            slug = f"{msd}-{t1}-{t2}-{s3_slug}"
            if (
                is_clean_3peaks_sequence(canonical)
                and is_clean_3peaks_sequence(slug)
                and slug not in taken
                and canonical not in taken
            ):
                return {"slug": slug, "canonical": canonical, "unix_seconds": sec}
        else:
            rem = (lsd_val - msd_val - v1) % TRIAD_BASE
            for attempt in range(400):
                t2 = _a8a_from_index(elapsed + attempt * 37)
                if not is_clean_3peaks_sequence(t2):
                    continue
                v2 = _decode_peak_triad(t2) or 0
                needed = (rem - v2) % TRIAD_BASE
                s3_canon = _encode_peak_canonical(needed)
                s3_slug = s3_canon if is_a8a_triad(s3_canon) else _encode_peak_urlsafe(needed)
                canonical = f"{msd}^{t1}^{t2}^{s3_canon}"
                slug = f"{msd}-{t1}-{t2}-{s3_slug}"
                if (
                    is_clean_3peaks_sequence(canonical)
                    and is_clean_3peaks_sequence(slug)
                    and slug not in taken
                    and canonical not in taken
                ):
                    return {"slug": slug, "canonical": canonical, "unix_seconds": sec}

        sec += 1

    raise RuntimeError("Unable to mint unique conforming 3-peaks slug")


def decode_3peaks_timestamp(code: str) -> int | None:
    """Decode a 7-char Single Peak or 15-char Triple Peak code back to Unix seconds since epoch."""
    s = (code or "").strip().lower()
    if len(s) == 7 and s[3] in ("^", "-"):
        msd, p1 = s[:3], s[4:7]
        if not is_a8a_triad(p1):
            return None
        msd_val = _decode_msd_triad(msd)
        lsd_val = _decode_peak_triad(p1)
        if msd_val is None or lsd_val is None:
            return None
        return T0UX + msd_val * TRIAD_BASE + lsd_val

    if len(s) == 15 and s[3] in ("^", "-") and s[7] in ("^", "-") and s[11] in ("^", "-"):
        msd, p1, p2, p3 = s[:3], s[4:7], s[8:11], s[12:15]
        if not (is_a8a_triad(p1) and is_a8a_triad(p2)):
            return None
        msd_val = _decode_msd_triad(msd)
        v1 = _decode_peak_triad(p1)
        v2 = _decode_peak_triad(p2)
        v3 = _decode_peak_triad(p3)
        if msd_val is None or v1 is None or v2 is None or v3 is None:
            return None
        lsd_val = (v1 + v2 + v3 + msd_val) % TRIAD_BASE
        return T0UX + msd_val * TRIAD_BASE + lsd_val

    return None
