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
