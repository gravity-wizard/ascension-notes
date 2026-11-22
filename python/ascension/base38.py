"""Base-38 encoding, URL-safe (-/_) mapping, and safe Jesus Clock (Time0)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Iterable, Union

B38_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz|^"
B38 = B38_ALPHABET
B38_BASE = len(B38_ALPHABET)  # 38
B38_INDEX = {ch: idx for idx, ch in enumerate(B38_ALPHABET)}

# March 8 Miracle / March 18 SLC quake Jesus Clock Time0 (2020-03-18T14:09:31Z)
T0UX = 1584540571
T0_ISO = "2020-03-18T14:09:31+00:00"

# Default blocked substrings for clock/ID skipping (includes triple-6 and leetspeak variants)
DEFAULT_CLOCK_BLOCKED: tuple[str, ...] = (
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

_LEET_NORMALIZE = str.maketrans({"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b"})

TimestampLike = Union[int, float, datetime, None]


@dataclass(frozen=True)
class SafeClockReading:
    clock: str
    raw_clock: str
    is_paused: bool
    effective_unix: int
    raw_unix: int


def to_url_safe_base38(value: str) -> str:
    """Convert canonical Base-38 caret (^) and pipe (|) into URL/filename-safe '-' and '_'."""
    return value.replace("^", "-").replace("|", "_")


def from_url_safe_base38(value: str) -> str:
    """Convert URL-safe '-' and '_' back into canonical Base-38 '^' and '|'."""
    return value.replace("-", "^").replace("_", "|")


def encode_base38(value: int) -> str:
    """Encode a non-negative integer into the 38-character twst23 Base-38 alphabet."""
    if value < 0:
        raise ValueError(f"Base-38 encoding requires a non-negative integer, got {value}.")
    if value == 0:
        return "0"
    n = value
    chars: list[str] = []
    while n > 0:
        n, rem = divmod(n, B38_BASE)
        chars.append(B38_ALPHABET[rem])
    return "".join(reversed(chars))


def decode_base38(encoded: str) -> int:
    """Decode a twst23 Base-38 string (accepting canonical ^/| or URL-safe -/_) into an integer."""
    if not encoded:
        raise ValueError("Base-38 string must not be empty.")
    canonical = from_url_safe_base38(encoded)
    total = 0
    for ch in canonical:
        if ch not in B38_INDEX:
            raise ValueError(f"Invalid Base-38 character {ch!r} in {encoded!r}.")
        total = total * B38_BASE + B38_INDEX[ch]
    return total


def coerce_unix_timestamp(timestamp: TimestampLike = None) -> int:
    """Convert int/float/datetime/None into integer UTC Unix seconds."""
    if timestamp is None:
        return int(datetime.now(timezone.utc).timestamp())
    if isinstance(timestamp, datetime):
        dt = timestamp if timestamp.tzinfo is not None else timestamp.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    return int(timestamp)


def jesus_clock(timestamp: TimestampLike = None, *, min_width: int = 1, url_safe: bool = False) -> str:
    """Return the raw Base-38 elapsed-seconds clock relative to T0UX."""
    unix_ts = coerce_unix_timestamp(timestamp)
    elapsed = max(0, unix_ts - T0UX)
    encoded = encode_base38(elapsed)
    if min_width > 1 and len(encoded) < min_width:
        encoded = encoded.rjust(min_width, "0")
    return to_url_safe_base38(encoded) if url_safe else encoded


def find_clock_block_reason(
    clock_str: str,
    blocked_substrings: Iterable[str] | None = None,
) -> tuple[str, int] | None:
    """Return (matched_bad_token, end_index_in_clock) if clock_str contains triple-6 or a bad word."""
    canonical = from_url_safe_base38(clock_str).lower()
    if "666" in canonical:
        idx = canonical.index("666")
        return ("666", idx + 3)

    core = canonical.replace("|", "").replace("^", "")
    leet = core.translate(_LEET_NORMALIZE)
    blocked = tuple(
        s.lower() for s in (DEFAULT_CLOCK_BLOCKED if blocked_substrings is None else blocked_substrings) if s
    )
    for bad in blocked:
        if bad == "666":
            continue
        if bad in core:
            idx = core.index(bad)
            return (bad, min(len(canonical), idx + len(bad)))
        if bad in leet:
            idx = leet.index(bad)
            return (bad, min(len(canonical), idx + len(bad)))
    return None


def is_clean_clock(clock_str: str, blocked_substrings: Iterable[str] | None = None) -> bool:
    """Return True iff clock_str contains neither triple-6 nor blocked substrings."""
    return find_clock_block_reason(clock_str, blocked_substrings=blocked_substrings) is None


def safe_jesus_clock(
    timestamp: TimestampLike = None,
    *,
    min_width: int = 1,
    url_safe: bool = False,
    blocked_substrings: Iterable[str] | None = None,
) -> SafeClockReading:
    """Compute Base-38 Jesus Clock, pausing/holding cleanly over bad words and triple-6 windows."""
    raw_unix = coerce_unix_timestamp(timestamp)
    raw_elapsed = max(0, raw_unix - T0UX)
    raw_clock = encode_base38(raw_elapsed)
    if min_width > 1 and len(raw_clock) < min_width:
        raw_clock = raw_clock.rjust(min_width, "0")

    elapsed = raw_elapsed
    is_paused = False
    while elapsed > 0:
        candidate = encode_base38(elapsed)
        if min_width > 1 and len(candidate) < min_width:
            candidate = candidate.rjust(min_width, "0")
        hit = find_clock_block_reason(candidate, blocked_substrings=blocked_substrings)
        if hit is None:
            shown = to_url_safe_base38(candidate) if url_safe else candidate
            raw_shown = to_url_safe_base38(raw_clock) if url_safe else raw_clock
            return SafeClockReading(
                clock=shown,
                raw_clock=raw_shown,
                is_paused=is_paused,
                effective_unix=T0UX + elapsed,
                raw_unix=raw_unix,
            )
        is_paused = True
        _, end_idx = hit
        trailing_digits = max(0, len(candidate) - end_idx)
        jump = B38_BASE ** trailing_digits
        # Jump directly to the tick right before the offending prefix when trailing digits exist
        step = (elapsed % jump) + 1 if trailing_digits > 0 else 1
        elapsed = max(0, elapsed - max(1, step))

    zero = "0".rjust(min_width, "0") if min_width > 1 else "0"
    raw_shown = to_url_safe_base38(raw_clock) if url_safe else raw_clock
    return SafeClockReading(
        clock=zero,
        raw_clock=raw_shown,
        is_paused=is_paused,
        effective_unix=T0UX,
        raw_unix=raw_unix,
    )


def decode_jesus_clock(clock_str: str) -> int:
    """Decode a Base-38 Jesus Clock string back into integer UTC Unix seconds."""
    return T0UX + decode_base38(clock_str)


def jesus_clock_to_datetime(clock_str: str) -> datetime:
    """Convert a Base-38 Jesus Clock string back into a UTC datetime."""
    return datetime.fromtimestamp(decode_jesus_clock(clock_str), tz=timezone.utc)


def clock2_from_timestamp(timestamp: TimestampLike = None, *, url_safe: bool = False) -> str:
    """Return the first 2 Base-38 characters of the safe Jesus Clock."""
    reading = safe_jesus_clock(timestamp, min_width=2, url_safe=url_safe)
    return reading.clock[:2]


@dataclass(frozen=True)
class ExactClockExpression:
    expression: str
    raw_clock: str
    used_arithmetic_workaround: bool
    preserved_msd_prefix: str
    context_word_used: str | None
    unix_seconds: int


_FALLBACK_EXACT_WORDS: tuple[str, ...] = (
    "sun", "sky", "joy", "art", "oak", "dew", "zen", "ace", "ray", "gem",
    "arc", "way", "key", "orb", "day", "era", "leaf", "peak", "pine", "wave",
    "moon", "glow", "hope", "love", "wind", "rain", "song", "book", "seed", "star",
    "calm", "home", "tree", "bird", "gold", "pure", "true", "wise", "good", "life",
    "angel", "bloom", "cloud", "dream", "earth", "faith", "grace", "heart", "light", "peace",
    "beacon", "nature", "wonder",
)


def is_lower_alnum_base38(value: str) -> bool:
    """Return True iff value is non-empty and consists solely of lowercase ASCII [0-9a-z]."""
    return bool(value) and all(("0" <= ch <= "9") or ("a" <= ch <= "z") for ch in value)


def is_clean_lower_alnum_clock(
    value: str,
    blocked_substrings: Iterable[str] | None = None,
) -> bool:
    """Return True iff value uses [0-9a-z] only and has no '666' or blocked substrings."""
    return is_lower_alnum_base38(value) and is_clean_clock(value, blocked_substrings=blocked_substrings)


def clean_exact_clock_expression(
    timestamp: TimestampLike = None,
    *,
    context_words: Iterable[str] = (),
    max_length: int = 17,
    always_use_difference_formula: bool = False,
    blocked_substrings: Iterable[str] | None = None,
) -> ExactClockExpression:
    """Format an exact timestamp as clean lowercase Base-38 (<= max_length chars).

    When the raw Base-38 value contains '666', a blocked word, or '^'/'|', keeps the leading
    MSDs intact and emits a pretty 9-digit + minus-sign formula ('2p7abc-xyz').
    """
    clamped_unix = max(T0UX, coerce_unix_timestamp(timestamp))
    elapsed = clamped_unix - T0UX
    raw_clock = encode_base38(elapsed)

    if (
        not always_use_difference_formula
        and len(raw_clock) <= max_length
        and is_clean_lower_alnum_clock(raw_clock, blocked_substrings=blocked_substrings)
    ):
        return ExactClockExpression(
            expression=raw_clock,
            raw_clock=raw_clock,
            used_arithmetic_workaround=False,
            preserved_msd_prefix=raw_clock,
            context_word_used=None,
            unix_seconds=clamped_unix,
        )

    import re

    three_ctx: list[str] = []
    other_ctx: list[str] = []
    seen: set[str] = set()
    for raw_word in context_words:
        for part in re.findall(r"[a-z]{2,6}", raw_word.lower()):
            if part in seen or not is_clean_lower_alnum_clock(part, blocked_substrings=blocked_substrings):
                continue
            seen.add(part)
            if len(part) == 3:
                three_ctx.append(part)
            else:
                other_ctx.append(part)

    three_fb: list[str] = []
    other_fb: list[str] = []
    for fallback in _FALLBACK_EXACT_WORDS:
        if fallback in seen or not is_clean_lower_alnum_clock(fallback, blocked_substrings=blocked_substrings):
            continue
        seen.add(fallback)
        if len(fallback) == 3:
            three_fb.append(fallback)
        else:
            other_fb.append(fallback)

    preferred_3_pool = three_ctx + three_fb
    full_word_pool = preferred_3_pool + other_ctx + other_fb

    max_msd = max(0, min(3, len(raw_clock) - 2))
    msd_candidates: list[str] = []
    for length in range(max_msd, 0, -1):
        prefix = raw_clock[:length]
        if is_clean_lower_alnum_clock(prefix, blocked_substrings=blocked_substrings):
            msd_candidates.append(prefix)
    msd_candidates.append("")

    target_anchor_digits = len(raw_clock)

    # First pass across MSD tiers (3 -> 2 -> 1 -> ""): strictly prefer 9 Base-38 digits + '-' (<anchor>-<3-char>)
    min_3_digit = B38_BASE * B38_BASE
    for msd_prefix in msd_candidates:
        # 1. Prefer strict 9-digit + '-' form: <target_anchor_digits>-<3-char word> (e.g. 2p7n2s-gym)
        for word in preferred_3_pool:
            rhs_val = decode_base38(word)
            if rhs_val <= 0:
                continue
            plus_anchor = encode_base38(elapsed + rhs_val)
            if (
                len(plus_anchor) == target_anchor_digits
                and plus_anchor.startswith(msd_prefix)
                and is_clean_lower_alnum_clock(plus_anchor, blocked_substrings=blocked_substrings)
            ):
                expr = f"{plus_anchor}-{word}"
                if len(expr) <= max_length:
                    return ExactClockExpression(
                        expression=expr,
                        raw_clock=raw_clock,
                        used_arithmetic_workaround=True,
                        preserved_msd_prefix=msd_prefix,
                        context_word_used=word,
                        unix_seconds=clamped_unix,
                    )

        # 2. Prefer strict 9-digit + '-' numeric 3-digit offset: 100_38 .. zzz_38 (e.g. 2p7abc-101)
        for step in range(min_3_digit, min_3_digit + 1201):
            delta = encode_base38(step)
            if len(delta) != 3 or not is_clean_lower_alnum_clock(delta, blocked_substrings=blocked_substrings):
                continue
            plus_anchor = encode_base38(elapsed + step)
            if (
                len(plus_anchor) == target_anchor_digits
                and plus_anchor.startswith(msd_prefix)
                and is_clean_lower_alnum_clock(plus_anchor, blocked_substrings=blocked_substrings)
            ):
                expr = f"{plus_anchor}-{delta}"
                if len(expr) <= max_length:
                    return ExactClockExpression(
                        expression=expr,
                        raw_clock=raw_clock,
                        used_arithmetic_workaround=True,
                        preserved_msd_prefix=msd_prefix,
                        context_word_used=None,
                        unix_seconds=clamped_unix,
                    )

    # Secondary fallback across MSD tiers if strict 6-3 subtraction is not possible
    for msd_prefix in msd_candidates:
        # 3. Other word lengths subtraction fallback
        for word in full_word_pool:
            if len(word) == 3:
                continue
            rhs_val = decode_base38(word)
            if rhs_val <= 0:
                continue
            plus_anchor = encode_base38(elapsed + rhs_val)
            if plus_anchor.startswith(msd_prefix) and is_clean_lower_alnum_clock(
                plus_anchor, blocked_substrings=blocked_substrings
            ):
                expr = f"{plus_anchor}-{word}"
                if len(expr) <= max_length:
                    return ExactClockExpression(
                        expression=expr,
                        raw_clock=raw_clock,
                        used_arithmetic_workaround=True,
                        preserved_msd_prefix=msd_prefix,
                        context_word_used=word,
                        unix_seconds=clamped_unix,
                    )

        # 4. Tiny offset subtraction (1..400) or addition fallback preserving MSDs
        for step in range(1, 401):
            delta = encode_base38(step)
            if not is_clean_lower_alnum_clock(delta, blocked_substrings=blocked_substrings):
                continue
            plus_anchor = encode_base38(elapsed + step)
            if plus_anchor.startswith(msd_prefix) and is_clean_lower_alnum_clock(
                plus_anchor, blocked_substrings=blocked_substrings
            ):
                expr = f"{plus_anchor}-{delta}"
                if len(expr) <= max_length:
                    return ExactClockExpression(
                        expression=expr,
                        raw_clock=raw_clock,
                        used_arithmetic_workaround=True,
                        preserved_msd_prefix=msd_prefix,
                        context_word_used=None,
                        unix_seconds=clamped_unix,
                    )

        for word in full_word_pool:
            rhs_val = decode_base38(word)
            if rhs_val <= 0 or elapsed < rhs_val:
                continue
            minus_anchor = encode_base38(elapsed - rhs_val)
            if minus_anchor.startswith(msd_prefix) and is_clean_lower_alnum_clock(
                minus_anchor, blocked_substrings=blocked_substrings
            ):
                expr = f"{minus_anchor}+{word}"
                if len(expr) <= max_length:
                    return ExactClockExpression(
                        expression=expr,
                        raw_clock=raw_clock,
                        used_arithmetic_workaround=True,
                        preserved_msd_prefix=msd_prefix,
                        context_word_used=word,
                        unix_seconds=clamped_unix,
                    )

    safe = safe_jesus_clock(clamped_unix, min_width=1, url_safe=False, blocked_substrings=blocked_substrings)
    delta = elapsed - (safe.effective_unix - T0UX)
    if delta > 0:
        delta_str = encode_base38(delta)
        if is_lower_alnum_base38(safe.clock) and is_lower_alnum_base38(delta_str):
            return ExactClockExpression(
                expression=f"{safe.clock}+{delta_str}",
                raw_clock=raw_clock,
                used_arithmetic_workaround=True,
                preserved_msd_prefix="",
                context_word_used=None,
                unix_seconds=clamped_unix,
            )

    return ExactClockExpression(
        expression=safe.clock,
        raw_clock=raw_clock,
        used_arithmetic_workaround=safe.is_paused,
        preserved_msd_prefix="",
        context_word_used=None,
        unix_seconds=safe.effective_unix,
    )


def decode_clock_expression(expr: str) -> int:
    """Evaluate a plain Base-38 clock or arithmetic expression ('anchor-word' / 'anchor+word') to Unix seconds."""
    trimmed = expr.strip()
    if not trimmed:
        raise ValueError("Base-38 clock expression must not be empty.")
    if "+" in trimmed:
        lhs, rhs = trimmed.split("+", 1)
        return T0UX + decode_base38(lhs) + decode_base38(rhs)
    if "-" in trimmed:
        lhs, rhs = trimmed.split("-", 1)
        if is_lower_alnum_base38(lhs) and is_lower_alnum_base38(rhs):
            lhs_val = decode_base38(lhs)
            rhs_val = decode_base38(rhs)
            if lhs_val >= rhs_val:
                return T0UX + (lhs_val - rhs_val)
    return decode_jesus_clock(trimmed)


def jesus_clock_expression_to_datetime(expr: str) -> datetime:
    """Convert a Base-38 clock or arithmetic expression back into a UTC datetime."""
    return datetime.fromtimestamp(decode_clock_expression(expr), tz=timezone.utc)
