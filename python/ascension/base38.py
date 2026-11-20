"""Base-38 Alphabet & Jesus Clock (Time0) utilities.

Implements the `twst23` Base-38 alphabet and the `Time0` (`T0UX`) epoch
anchored at 2020-03-18T14:09:31Z (1584540571).
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Union

B38: str = "0123456789abcdefghijklmnopqrstuvwxyz|^"
B38_BASE: int = len(B38)
_B38_INDEX: dict[str, int] = {ch: idx for idx, ch in enumerate(B38)}

# 2020-03-18T14:09:31Z — March 8 Miracle / March 18 SLC quake Jesus Clock Time0
T0UX: int = 1584540571
T0_ISO: str = "2020-03-18T14:09:31Z"

TimestampLike = Union[int, float, datetime, None]


def encode_base38(value: int) -> str:
    """Encode a non-negative integer into the 38-character B38 alphabet."""
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError(f"Expected int, got {type(value).__name__}")
    if value < 0:
        raise ValueError(f"Base-38 encoding requires non-negative integer, got {value}")
    if value == 0:
        return B38[0]

    chars: list[str] = []
    n = value
    while n > 0:
        n, rem = divmod(n, B38_BASE)
        chars.append(B38[rem])
    return "".join(reversed(chars))


def decode_base38(encoded: str) -> int:
    """Decode a B38 string back into a non-negative integer."""
    if not isinstance(encoded, str) or not encoded:
        raise ValueError("Base-38 string must be a non-empty string")

    total = 0
    for ch in encoded:
        idx = _B38_INDEX.get(ch)
        if idx is None:
            raise ValueError(f"Invalid Base-38 character {ch!r} in {encoded!r}")
        total = total * B38_BASE + idx
    return total


def coerce_unix_timestamp(timestamp: TimestampLike = None) -> int:
    """Convert None, int, float, or datetime into integer Unix seconds."""
    if timestamp is None:
        return int(datetime.now(timezone.utc).timestamp())
    if isinstance(timestamp, datetime):
        dt = timestamp
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            dt = dt.astimezone(timezone.utc)
        return int(dt.timestamp())
    if isinstance(timestamp, bool):
        raise TypeError("Timestamp cannot be a bool")
    if isinstance(timestamp, (int, float)):
        return int(timestamp)
    raise TypeError(f"Unsupported timestamp type: {type(timestamp).__name__}")


def jesus_clock(timestamp: TimestampLike = None, *, min_width: int = 1) -> str:
    """Encode `elapsed = max(0, int(timestamp) - T0UX)` in Base-38."""
    ts = coerce_unix_timestamp(timestamp)
    elapsed = max(0, ts - T0UX)
    encoded = encode_base38(elapsed)
    if min_width > 1 and len(encoded) < min_width:
        return encoded.rjust(min_width, B38[0])
    return encoded


def decode_jesus_clock(clock_str: str) -> int:
    """Decode a Base-38 Jesus Clock string into a Unix timestamp (seconds)."""
    elapsed = decode_base38(clock_str)
    return T0UX + elapsed


def jesus_clock_to_datetime(clock_str: str) -> datetime:
    """Decode a Base-38 Jesus Clock string into a UTC datetime."""
    ts = decode_jesus_clock(clock_str)
    return datetime.fromtimestamp(ts, tz=timezone.utc)


def clock2_from_timestamp(timestamp: TimestampLike = None) -> str:
    """Return the 2-character Jesus Clock prefix used in Acode9 (`[2..3]`)."""
    return jesus_clock(timestamp, min_width=2)[:2]
