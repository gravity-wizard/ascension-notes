export const B38_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz|^";
export const B38_BASE = 38;
export const T0UX = 1584540571; // 2020-03-18T14:09:31Z

const CHAR_INDEX = new Map(
  Array.from(B38_ALPHABET).map((ch, idx) => [ch, idx])
);

export const DEFAULT_CLOCK_BLOCKED = [
  "666",
  "anal", "anus", "arse", "bitch", "btch", "cock", "c0ck", "cunt",
  "damn", "dick", "d1ck", "dyke", "fag", "fck", "fuk", "fuck",
  "hell", "jizz", "kike", "klan", "nazi", "nig", "n1g", "porn",
  "p0rn", "puss", "rape", "shit", "sh1t", "slut", "spic", "twat",
  "wank", "whor", "xxx",
];

const FALLBACK_EXACT_WORDS = [
  "sun", "sky", "joy", "art", "oak", "dew", "zen", "ace", "ray", "gem",
  "arc", "way", "key", "orb", "day", "era", "leaf", "peak", "pine", "wave",
  "moon", "glow", "hope", "love", "wind", "rain", "song", "book", "seed", "star",
  "calm", "home", "tree", "bird", "gold", "pure", "true", "wise", "good", "life",
  "angel", "bloom", "cloud", "dream", "earth", "faith", "grace", "heart", "light", "peace",
  "beacon", "nature", "wonder",
];

const LEET_MAP = {
  "0": "o",
  "1": "i",
  "3": "e",
  "4": "a",
  "5": "s",
  "7": "t",
  "8": "b",
};

export function toUrlSafeBase38(value) {
  return String(value).replace(/\^/g, "-").replace(/\|/g, "_");
}

export function fromUrlSafeBase38(value) {
  return String(value).replace(/-/g, "^").replace(/_/g, "|");
}

export function encodeBase38(value) {
  let n = Math.trunc(Number(value));
  if (!Number.isSafeInteger(n) || n < 0) {
    throw new RangeError(`Base-38 encoding requires a non-negative integer, got ${value}`);
  }
  if (n === 0) return "0";
  let out = "";
  while (n > 0) {
    out = B38_ALPHABET[n % B38_BASE] + out;
    n = Math.floor(n / B38_BASE);
  }
  return out;
}

export function decodeBase38(raw) {
  const s = String(raw ?? "").trim();
  if (!s) throw new Error("Base-38 string must not be empty.");
  let acc = 0;
  for (const ch of s) {
    const idx = CHAR_INDEX.get(ch);
    if (idx === undefined) {
      throw new Error(`Invalid Base-38 character '${ch}'.`);
    }
    acc = acc * B38_BASE + idx;
  }
  return acc;
}

export function isLowerAlnumBase38(value) {
  return typeof value === "string" && /^[0-9a-z]+$/.test(value);
}

export function isCleanClock(value, blockedSubstrings = DEFAULT_CLOCK_BLOCKED) {
  const lower = String(value ?? "").toLowerCase();
  if (!lower) return false;
  let leet = "";
  for (const ch of lower) {
    leet += LEET_MAP[ch] ?? ch;
  }
  for (const rawBlocked of blockedSubstrings) {
    const blocked = String(rawBlocked).toLowerCase();
    if (!blocked) continue;
    if (lower.includes(blocked) || leet.includes(blocked)) {
      return false;
    }
  }
  return true;
}

export function isCleanLowerAlnumClock(value, blockedSubstrings = DEFAULT_CLOCK_BLOCKED) {
  return isLowerAlnumBase38(value) && isCleanClock(value, blockedSubstrings);
}

export function sanitizeFavorite3LetterOffset(raw, blockedSubstrings = DEFAULT_CLOCK_BLOCKED) {
  if (!raw || typeof raw !== "string") return null;
  const letters = raw.toLowerCase().replace(/[^a-z]/g, "").slice(0, 3);
  if (letters.length !== 3 || !isCleanLowerAlnumClock(letters, blockedSubstrings)) {
    return null;
  }
  return letters;
}

export function jesusClock(unixSeconds = Math.floor(Date.now() / 1000)) {
  const clamped = Math.max(T0UX, Math.trunc(unixSeconds));
  return encodeBase38(clamped - T0UX);
}

export function decodeJesusClock(clockStr) {
  return T0UX + decodeBase38(clockStr);
}

export function decodeClockExpression(expr) {
  const trimmed = String(expr ?? "").trim();
  if (!trimmed) throw new Error("Clock expression must not be empty.");
  if (trimmed.includes("+")) {
    const [lhs, rhs] = trimmed.split("+", 2);
    return T0UX + decodeBase38(lhs) + decodeBase38(rhs);
  }
  if (trimmed.includes("-")) {
    const [lhs, rhs] = trimmed.split("-", 2);
    return T0UX + decodeBase38(lhs) - decodeBase38(rhs);
  }
  return T0UX + decodeBase38(trimmed);
}

export function cleanExactClockExpression({
  unixSeconds = Math.floor(Date.now() / 1000),
  contextWords = [],
  maxLength = 17,
  alwaysUseDifferenceFormula = false,
  favoriteOffset = null,
  blockedSubstrings = DEFAULT_CLOCK_BLOCKED,
} = {}) {
  const clampedUnix = Math.max(T0UX, Math.trunc(unixSeconds));
  const elapsed = clampedUnix - T0UX;
  const rawClock = encodeBase38(elapsed);

  if (
    !alwaysUseDifferenceFormula &&
    rawClock.length <= maxLength &&
    isCleanLowerAlnumClock(rawClock, blockedSubstrings)
  ) {
    return {
      expression: rawClock,
      rawClock,
      usedArithmeticWorkaround: false,
      preservedMSDPrefix: rawClock,
      contextWordUsed: null,
      unixSeconds: clampedUnix,
    };
  }

  const threeCtx = [];
  const otherCtx = [];
  const seen = new Set();

  const fav = sanitizeFavorite3LetterOffset(favoriteOffset, blockedSubstrings);
  if (fav) {
    seen.add(fav);
    threeCtx.push(fav);
  }

  for (const rawWord of contextWords) {
    const parts = String(rawWord ?? "").toLowerCase().match(/[a-z]{2,6}/g) || [];
    for (const part of parts) {
      if (seen.has(part) || !isCleanLowerAlnumClock(part, blockedSubstrings)) continue;
      seen.add(part);
      if (part.length === 3) threeCtx.push(part);
      else otherCtx.push(part);
    }
  }

  const threeFb = [];
  const otherFb = [];
  for (const fb of FALLBACK_EXACT_WORDS) {
    if (seen.has(fb) || !isCleanLowerAlnumClock(fb, blockedSubstrings)) continue;
    seen.add(fb);
    if (fb.length === 3) threeFb.push(fb);
    else otherFb.push(fb);
  }

  const preferred3Pool = [...threeCtx, ...threeFb];
  const fullWordPool = [...preferred3Pool, ...otherCtx, ...otherFb];

  const maxMsd = Math.max(0, Math.min(3, rawClock.length - 2));
  const msdCandidates = [];
  for (let len = maxMsd; len >= 1; len--) {
    const prefix = rawClock.slice(0, len);
    if (isCleanLowerAlnumClock(prefix, blockedSubstrings)) {
      msdCandidates.push(prefix);
    }
  }
  msdCandidates.push("");

  const targetAnchorDigits = rawClock.length;
  const min3Digit = B38_BASE * B38_BASE;

  // Pass 1 & 2 across MSD tiers: strict 6-3 (9 Base-38 digits + '-')
  for (const msdPrefix of msdCandidates) {
    for (const word of preferred3Pool) {
      const rhsVal = decodeBase38(word);
      if (rhsVal <= 0) continue;
      const plusAnchor = encodeBase38(elapsed + rhsVal);
      if (
        plusAnchor.length === targetAnchorDigits &&
        plusAnchor.startsWith(msdPrefix) &&
        isCleanLowerAlnumClock(plusAnchor, blockedSubstrings)
      ) {
        const expr = `${plusAnchor}-${word}`;
        if (expr.length <= maxLength) {
          return {
            expression: expr,
            rawClock,
            usedArithmeticWorkaround: true,
            preservedMSDPrefix: msdPrefix,
            contextWordUsed: word,
            unixSeconds: clampedUnix,
          };
        }
      }
    }

    for (let step = min3Digit; step <= min3Digit + 1200; step++) {
      const delta = encodeBase38(step);
      if (delta.length !== 3 || !isCleanLowerAlnumClock(delta, blockedSubstrings)) continue;
      const plusAnchor = encodeBase38(elapsed + step);
      if (
        plusAnchor.length === targetAnchorDigits &&
        plusAnchor.startsWith(msdPrefix) &&
        isCleanLowerAlnumClock(plusAnchor, blockedSubstrings)
      ) {
        const expr = `${plusAnchor}-${delta}`;
        if (expr.length <= maxLength) {
          return {
            expression: expr,
            rawClock,
            usedArithmeticWorkaround: true,
            preservedMSDPrefix: msdPrefix,
            contextWordUsed: null,
            unixSeconds: clampedUnix,
          };
        }
      }
    }
  }

  // Pass 3 & 4: non-3-char words and addition fallback
  for (const msdPrefix of msdCandidates) {
    for (const word of fullWordPool) {
      if (word.length === 3) continue;
      const rhsVal = decodeBase38(word);
      if (rhsVal <= 0) continue;
      const plusAnchor = encodeBase38(elapsed + rhsVal);
      if (plusAnchor.startsWith(msdPrefix) && isCleanLowerAlnumClock(plusAnchor, blockedSubstrings)) {
        const expr = `${plusAnchor}-${word}`;
        if (expr.length <= maxLength) {
          return {
            expression: expr,
            rawClock,
            usedArithmeticWorkaround: true,
            preservedMSDPrefix: msdPrefix,
            contextWordUsed: word,
            unixSeconds: clampedUnix,
          };
        }
      }
    }

    for (let step = 1; step <= 400; step++) {
      const delta = encodeBase38(step);
      if (!isCleanLowerAlnumClock(delta, blockedSubstrings)) continue;
      const plusAnchor = encodeBase38(elapsed + step);
      if (plusAnchor.startsWith(msdPrefix) && isCleanLowerAlnumClock(plusAnchor, blockedSubstrings)) {
        const expr = `${plusAnchor}-${delta}`;
        if (expr.length <= maxLength) {
          return {
            expression: expr,
            rawClock,
            usedArithmeticWorkaround: true,
            preservedMSDPrefix: msdPrefix,
            contextWordUsed: null,
            unixSeconds: clampedUnix,
          };
        }
      }
    }

    for (const word of fullWordPool) {
      const rhsVal = decodeBase38(word);
      if (rhsVal <= 0 || elapsed < rhsVal) continue;
      const minusAnchor = encodeBase38(elapsed - rhsVal);
      if (minusAnchor.startsWith(msdPrefix) && isCleanLowerAlnumClock(minusAnchor, blockedSubstrings)) {
        const expr = `${minusAnchor}+${word}`;
        if (expr.length <= maxLength) {
          return {
            expression: expr,
            rawClock,
            usedArithmeticWorkaround: true,
            preservedMSDPrefix: msdPrefix,
            contextWordUsed: word,
            unixSeconds: clampedUnix,
          };
        }
      }
    }
  }

  return {
    expression: rawClock,
    rawClock,
    usedArithmeticWorkaround: false,
    preservedMSDPrefix: "",
    contextWordUsed: null,
    unixSeconds: clampedUnix,
  };
}
