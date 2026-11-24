import crypto from "node:crypto";

export const DEFAULT_MAX_IMAGE_BYTES = Number(process.env.TWISTED23_MAX_IMAGE_BYTES || 575 * 1024);
export const DEFAULT_NONCONFORMING_MAX_BYTES = Number(
  process.env.TWISTED23_NONCONFORMING_MAX_BYTES || 385 * 1024
);
export const DEFAULT_IP_DAILY_QUOTA = Number(process.env.TWISTED23_IP_DAILY_QUOTA || 60);
export const CONFORMING_QUOTA_COST = 1;
export const NONCONFORMING_QUOTA_COST = Number(process.env.TWISTED23_NONCONFORMING_QUOTA_COST || 2);

export const WISH_TRIAD_ALIASES = Object.freeze({
  pi1browser: "p1b",
  pibrowser: "p1b",
  full5screen: "f5n",
  fullscreen: "f5n",
});

const TIME_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz|^";
const TIME_BASE = 38;
const TRIAD_BASE = TIME_BASE * TIME_BASE * TIME_BASE; // 54872
const A8A_COUNT = 26 * 8 * 26; // 5408
const TIME_EPOCH = 1584540571;
const AGY_OFFSET_VAL = 10 * TIME_BASE * TIME_BASE + 16 * TIME_BASE + 34; // decode("agy") = 15082
const A8A_DIGITS = "12345789";
const BLOCKED_PARTS = ["69", "666", "anal", "anus", "arse", "bitch", "btch", "cock", "c0ck", "cunt", "damn", "dick", "d1ck", "dyke", "fag", "fck", "fuk", "fuck", "hell", "jizz", "kike", "klan", "nazi", "nig", "n1g", "porn", "p0rn", "puss", "rape", "shit", "sh1t", "slut", "spic", "twat", "wank", "whor", "xxx"];

export function getMaxImageBytes() {
  const val = Number(process.env.TWISTED23_MAX_IMAGE_BYTES || DEFAULT_MAX_IMAGE_BYTES);
  return Number.isFinite(val) && val > 0 ? val : 575 * 1024;
}

export function getNonConformingMaxImageBytes() {
  const maxAll = getMaxImageBytes();
  const val = Number(process.env.TWISTED23_NONCONFORMING_MAX_BYTES || DEFAULT_NONCONFORMING_MAX_BYTES);
  const cap = Number.isFinite(val) && val > 0 ? val : 385 * 1024;
  return Math.min(maxAll, cap);
}

export function getDailyIpQuota() {
  const val = Number(process.env.TWISTED23_IP_DAILY_QUOTA || DEFAULT_IP_DAILY_QUOTA);
  return Number.isFinite(val) && val > 0 ? val : 60;
}

function encodeCompactTime(value) {
  let n = Math.max(0, Math.trunc(value));
  if (n === 0) return "0";
  let out = "";
  while (n > 0) {
    out = TIME_ALPHABET[n % TIME_BASE] + out;
    n = Math.floor(n / TIME_BASE);
  }
  return out;
}

function decodeCompactTime(str) {
  let total = 0;
  for (const ch of String(str || "")) {
    const normalized = ch === "_" ? "0" : ch === "-" ? "^" : ch;
    const idx = TIME_ALPHABET.indexOf(normalized);
    if (idx < 0) return null;
    total = total * TIME_BASE + idx;
  }
  return total;
}

function isCleanAlnumTag(s) {
  if (!/^[0-9a-z]+$/.test(s)) return false;
  const leet = s.replace(/[0134578]/g, (c) => ({ 0: "o", 1: "i", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b" }[c]));
  return !BLOCKED_PARTS.some((b) => s.includes(b) || leet.includes(b));
}

const BLOCKED_RE = new RegExp(BLOCKED_PARTS.join("|"));
const DIGITS_BLOCKED_RE = /69|666/;

function charIdx(code) {
  if (code >= 48 && code <= 57) return code - 48;
  if (code >= 97 && code <= 122) return code - 87;
  return 36;
}

const BLOCKED_TRIGRAM = new Uint8Array(37 * 37 * 37);
for (const b of BLOCKED_PARTS) {
  if (b.length >= 3) {
    BLOCKED_TRIGRAM[(charIdx(b.charCodeAt(0)) * 37 + charIdx(b.charCodeAt(1))) * 37 + charIdx(b.charCodeAt(2))] = 1;
  }
}

function hasStrTrigram(s) {
  if (s.length < 3) return false;
  let c0 = charIdx(s.charCodeAt(0));
  let c1 = charIdx(s.charCodeAt(1));
  for (let i = 2; i < s.length; i++) {
    const c2 = charIdx(s.charCodeAt(i));
    if (BLOCKED_TRIGRAM[(c0 * 37 + c1) * 37 + c2]) return true;
    c0 = c1;
    c1 = c2;
  }
  return false;
}

function hasAnyBlocked(s) {
  if (s.includes("69")) return true;
  return hasStrTrigram(s) && BLOCKED_RE.test(s);
}

function hasTriadTrigram(m12, m2_1369, p1, p2, p3) {
  const a0 = p1 >>> 12, a1 = (p1 >>> 6) & 63, a2 = p1 & 63;
  const b0 = p2 >>> 12, b1 = (p2 >>> 6) & 63, b2 = p2 & 63;
  const c0 = p3 >>> 12, c1 = (p3 >>> 6) & 63;
  return (
    BLOCKED_TRIGRAM[m12 + a0] |
    BLOCKED_TRIGRAM[m2_1369 + a0 * 37 + a1] |
    BLOCKED_TRIGRAM[(a1 * 37 + a2) * 37 + b0] |
    BLOCKED_TRIGRAM[a2 * 1369 + b0 * 37 + b1] |
    BLOCKED_TRIGRAM[(b1 * 37 + b2) * 37 + c0] |
    BLOCKED_TRIGRAM[b2 * 1369 + c0 * 37 + c1]
  ) !== 0;
}

function hasLeetIOrLettersTrigram(msdI12, msdI2_1369, msdL12, msdL2_1369, idx1, idx2, idx3) {
  const ab = A8A_C2_1369[idx1] + A8A_C0_37[idx2];
  const bc = A8A_C2_1369[idx2] + A8A_C0_37[idx3];
  return (
    A8A_I_SELF[idx1] |
    A8A_I_SELF[idx2] |
    A8A_I_SELF[idx3] |
    BLOCKED_TRIGRAM[msdI12 + A8A_C0[idx1]] |
    BLOCKED_TRIGRAM[msdI2_1369 + A8A_I_C01[idx1]] |
    BLOCKED_TRIGRAM[A8A_I_END[idx1] + A8A_C0[idx2]] |
    BLOCKED_TRIGRAM[ab + A8A_I_C1[idx2]] |
    BLOCKED_TRIGRAM[A8A_I_END[idx2] + A8A_C0[idx3]] |
    BLOCKED_TRIGRAM[bc + A8A_I_C1[idx3]] |
    (msdL12 >= 0 ? BLOCKED_TRIGRAM[msdL12 + A8A_C0[idx1]] : 0) |
    (msdL2_1369 >= 0 ? BLOCKED_TRIGRAM[msdL2_1369 + A8A_L_C02[idx1]] : 0) |
    BLOCKED_TRIGRAM[A8A_L_END[idx1] + A8A_C0[idx2]] |
    BLOCKED_TRIGRAM[ab + A8A_C2[idx2]] |
    BLOCKED_TRIGRAM[A8A_L_END[idx2] + A8A_C0[idx3]] |
    BLOCKED_TRIGRAM[bc + A8A_C2[idx3]]
  ) !== 0;
}

export function isCleanAcodeSequence(rawCode) {
  const joined = String(rawCode || "")
    .toLowerCase()
    .replace(/[|\^-]/g, "")
    .replace(/_/g, "0");
  const lettersOnly = joined.replace(/[0-9]/g, "");
  const digitsOnly = joined.replace(/[a-z]/g, "");
  const leetI = joined.replace(/[01345789]/g, (c) => ({ 0: "o", 1: "i", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b", 9: "g" }[c]));
  const leetL = joined.replace(/[01345789]/g, (c) => ({ 0: "o", 1: "l", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b", 9: "g" }[c]));

  return !(
    hasAnyBlocked(joined) ||
    hasAnyBlocked(lettersOnly) ||
    DIGITS_BLOCKED_RE.test(digitsOnly) ||
    hasAnyBlocked(leetI) ||
    hasAnyBlocked(leetL)
  );
}

function formatMsdTriad(msdVal) {
  const raw = encodeCompactTime(msdVal).padStart(3, "0").slice(-3);
  return raw.replace(/0/g, "_").replace(/\|/g, "_").replace(/\^/g, "-");
}

function a8aFromIndex(idx) {
  const i = ((idx % A8A_COUNT) + A8A_COUNT) % A8A_COUNT;
  const c0 = String.fromCharCode(97 + Math.floor(i / 208));
  const rem = i % 208;
  const c1 = A8A_DIGITS[Math.floor(rem / 26)];
  const c2 = String.fromCharCode(97 + (rem % 26));
  return `${c0}${c1}${c2}`;
}

const A8A_TRIADS = new Array(A8A_COUNT);
const A8A_VALS = new Int32Array(A8A_COUNT);
const A8A_CLEAN = new Uint8Array(A8A_COUNT);
const A8A_HAS1 = new Uint8Array(A8A_COUNT);
const A8A_IS9 = new Uint8Array(A8A_COUNT);
const A8A_LETTERS = new Array(A8A_COUNT);
const A8A_LEET_I = new Array(A8A_COUNT);
const A8A_LEET_L = new Array(A8A_COUNT);
const A8A_J_PACK = new Int32Array(A8A_COUNT);
const A8A_LL_PACK = new Int32Array(A8A_COUNT);
const A8A_C0 = new Uint8Array(A8A_COUNT);
const A8A_C2 = new Uint8Array(A8A_COUNT);
const A8A_I_C1 = new Uint8Array(A8A_COUNT);
const A8A_C0_37 = new Int32Array(A8A_COUNT);
const A8A_C2_1369 = new Int32Array(A8A_COUNT);
const A8A_I_C01 = new Int32Array(A8A_COUNT);
const A8A_L_C02 = new Int32Array(A8A_COUNT);
const A8A_I_END = new Int32Array(A8A_COUNT);
const A8A_L_END = new Int32Array(A8A_COUNT);
const A8A_J_SELF = new Uint8Array(A8A_COUNT);
const A8A_I_SELF = new Uint8Array(A8A_COUNT);
const A8A_LL_SELF = new Uint8Array(A8A_COUNT);
const NEEDED_TO_CLEAN_A8A = new Int16Array(TRIAD_BASE).fill(-1);
const LEET_I_MAP = { 0: "o", 1: "i", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b", 9: "g" };
const LEET_L_MAP = { 0: "o", 1: "l", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b", 9: "g" };
function pack3(s) {
  return (charIdx(s.charCodeAt(0)) << 12) | (charIdx(s.charCodeAt(1)) << 6) | charIdx(s.charCodeAt(2));
}
for (let i = 0; i < A8A_COUNT; i++) {
  const t = a8aFromIndex(i);
  const li = t.replace(/[01345789]/g, (c) => LEET_I_MAP[c]);
  const ll = t.replace(/[01345789]/g, (c) => LEET_L_MAP[c]);
  const val = decodeCompactTime(t);
  const clean = isCleanAcodeSequence(t) ? 1 : 0;
  const c0 = charIdx(li.charCodeAt(0));
  const c1 = charIdx(li.charCodeAt(1));
  const c2 = charIdx(li.charCodeAt(2));
  A8A_TRIADS[i] = t;
  A8A_VALS[i] = val;
  A8A_CLEAN[i] = clean;
  if (clean) NEEDED_TO_CLEAN_A8A[val] = i;
  A8A_HAS1[i] = t[1] === "1" ? 1 : 0;
  A8A_IS9[i] = t[1] === "9" ? 1 : 0;
  A8A_LETTERS[i] = t[0] + t[2];
  A8A_LEET_I[i] = li;
  A8A_LEET_L[i] = ll;
  A8A_J_PACK[i] = pack3(t);
  A8A_LL_PACK[i] = pack3(ll);
  A8A_J_SELF[i] = BLOCKED_TRIGRAM[(charIdx(t.charCodeAt(0)) * 37 + charIdx(t.charCodeAt(1))) * 37 + charIdx(t.charCodeAt(2))];
  A8A_I_SELF[i] = BLOCKED_TRIGRAM[(c0 * 37 + c1) * 37 + c2];
  A8A_LL_SELF[i] = BLOCKED_TRIGRAM[(charIdx(ll.charCodeAt(0)) * 37 + charIdx(ll.charCodeAt(1))) * 37 + charIdx(ll.charCodeAt(2))];
  A8A_C0[i] = c0;
  A8A_C2[i] = c2;
  A8A_I_C1[i] = c1;
  A8A_C0_37[i] = c0 * 37;
  A8A_C2_1369[i] = c2 * 1369;
  A8A_I_C01[i] = c0 * 37 + c1;
  A8A_L_C02[i] = c0 * 37 + c2;
  A8A_I_END[i] = (c1 * 37 + c2) * 37;
  A8A_L_END[i] = (c0 * 37 + c2) * 37;
}

export function isA8aTriad(s) {
  return /^[a-z][1-57-9][a-z]$/.test(String(s || ""));
}

function findTriplePeakAttempt(
  msd, e1, e2, baseDiff, msdNorm, msdLetters, msdLeetI, msdLeetL,
  msdEndsWith6, msdHas1, msdWallEnd, msdMayJ, msdMayL, msdMayI, msdMayLL,
  msdJ12, msdJ2_1369, msdL12, msdL2_1369, msdI12, msdI2_1369, msdLL12, msdLL2_1369,
  isTakenFn
) {
  const msdDash = `${msd}-`;
  const e1Mul = Math.imul(e1, 2654435761);
  const e2Mul = Math.imul(e2, 3266489917);
  const baseDiffPos = baseDiff + 3 * TRIAD_BASE;
  for (let attempt = 1; attempt <= 5000; attempt++) {
    const h1 = (e1Mul ^ Math.imul(attempt, 2246822519)) >>> 0;
    const h2 = (e2Mul ^ Math.imul(attempt, 668265263)) >>> 0;
    const idx1 = h1 % A8A_COUNT;
    const idx2 = h2 % A8A_COUNT;

    const needed = (baseDiffPos - A8A_VALS[idx1] - A8A_VALS[idx2]) % TRIAD_BASE;

    const idx3 = NEEDED_TO_CLEAN_A8A[needed];
    if (idx3 < 0) continue;
    if (!A8A_CLEAN[idx1] || !A8A_CLEAN[idx2]) continue;

    if (msdEndsWith6 && A8A_IS9[idx1]) continue;
    const has1 = msdHas1 | A8A_HAS1[idx1] | A8A_HAS1[idx2] | A8A_HAS1[idx3];
    if ((has1 || !msdWallEnd || msdMayJ) &&
        (msdMayJ || A8A_J_SELF[idx1] || A8A_J_SELF[idx2] || A8A_J_SELF[idx3] || hasTriadTrigram(msdJ12, msdJ2_1369, A8A_J_PACK[idx1], A8A_J_PACK[idx2], A8A_J_PACK[idx3])) &&
        BLOCKED_RE.test(msdNorm + A8A_TRIADS[idx1] + A8A_TRIADS[idx2] + A8A_TRIADS[idx3])) continue;
    if (msdMayI || msdMayL || hasLeetIOrLettersTrigram(msdI12, msdI2_1369, msdL12, msdL2_1369, idx1, idx2, idx3)) {
      if (BLOCKED_RE.test(msdLeetI + A8A_LEET_I[idx1] + A8A_LEET_I[idx2] + A8A_LEET_I[idx3])) continue;
      if (BLOCKED_RE.test(msdLetters + A8A_LETTERS[idx1] + A8A_LETTERS[idx2] + A8A_LETTERS[idx3])) continue;
    }
    if (has1 &&
        (msdMayLL || A8A_LL_SELF[idx1] || A8A_LL_SELF[idx2] || A8A_LL_SELF[idx3] || hasTriadTrigram(msdLL12, msdLL2_1369, A8A_LL_PACK[idx1], A8A_LL_PACK[idx2], A8A_LL_PACK[idx3])) &&
        BLOCKED_RE.test(msdLeetL + A8A_LEET_L[idx1] + A8A_LEET_L[idx2] + A8A_LEET_L[idx3])) continue;

    const t1 = A8A_TRIADS[idx1];
    const t2 = A8A_TRIADS[idx2];
    const t3 = A8A_TRIADS[idx3];
    const slug = `${msdDash}${t1}-${t2}-${t3}`;
    if (!isTakenFn(slug)) {
      const canonical = `${msd}^${t1}^${t2}^${t3}`;
      if (!isTakenFn(canonical) && isCleanAcodeSequence(canonical)) {
        return { slug, canonical };
      }
    }
  }
  return null;
}

export function mintAcodeTimeSlug(unixSeconds = Math.floor(Date.now() / 1000), isTakenFn = () => false) {
  const baseSec = Math.max(TIME_EPOCH, Math.trunc(unixSeconds));
  let sec = baseSec;
  let msdSkips = 0;
  let lastMsdVal = -1;
  let msd = "";
  let msdNorm = "";
  let msdClean = false;

  for (let step = 0; step < 2000; ) {
    const elapsed = sec - TIME_EPOCH;
    const msdVal = Math.floor(elapsed / TRIAD_BASE);
    const lsdVal = elapsed % TRIAD_BASE;
    if (msdVal !== lastMsdVal) {
      lastMsdVal = msdVal;
      msd = formatMsdTriad(msdVal);
      msdNorm = msd.replace(/_/g, "0");
      msdClean = isCleanAcodeSequence(msdNorm);
    }

    if (!msdClean) {
      if (msdSkips >= 64) break;
      msdSkips++;
      sec = TIME_EPOCH + (msdVal + 1) * TRIAD_BASE;
      continue;
    }

    // 1. Single Peak: ___^a8a (URL-safe: ___-a8a) when LSD triad is naturally a8a and clean/free
    const ld0 = (lsdVal / 1444) | 0;
    if (ld0 >= 10 && ld0 <= 35) {
      const lrem = lsdVal - ld0 * 1444;
      const ld1 = (lrem / 38) | 0;
      if ((ld1 >= 1 && ld1 <= 5) || (ld1 >= 7 && ld1 <= 9)) {
        const ld2 = lrem - ld1 * 38;
        if (ld2 >= 10 && ld2 <= 35) {
          const directLsd = encodeCompactTime(lsdVal);
          const canonical = `${msd}^${directLsd}`;
          const slug = `${msd}-${directLsd}`;
          if (isCleanAcodeSequence(canonical) && !isTakenFn(slug) && !isTakenFn(canonical)) {
            return { slug, canonical, mode: "single", unixSeconds: sec };
          }
        }
      }
    }

    // 2. Triple Peak: ___^a8a^a8a^a8a (URL-safe: ___-a8a-a8a-a8a)
    // Exact math: (v(t1) + v(t2) + v(t3) + msdVal) % 54872 === lsdVal
    // 3 a8a triads with c1 in {1..5,7..9} + carry in {0,1,2} can only sum to c1 in [3..29].
    const diff = (lsdVal - msdVal + TRIAD_BASE) % TRIAD_BASE;
    const c1 = Math.floor((diff % 1444) / TIME_BASE);
    if (c1 >= 3 && c1 <= 29) {
      const e1 = elapsed ^ 0x9e3779b9;
      const e2 = elapsed ^ 0x85ebca6b;
      const baseDiff = lsdVal - msdVal;
      const msdLetters = msdNorm.replace(/[0-9]/g, "");
      const msdDigits = msdNorm.replace(/[a-z]/g, "");
      const msdEndsWith6 = msdDigits.endsWith("6");
      const msdHas1 = msdNorm.includes("1") ? 1 : 0;
      const msdWallEnd = /[234578]$/.test(msdNorm);
      const msdLeetI = msdNorm.replace(/[01345789]/g, (c) => LEET_I_MAP[c]);
      const msdLeetL = msdNorm.replace(/[01345789]/g, (c) => LEET_L_MAP[c]);

      const msdMayJ = hasStrTrigram(msdNorm);
      const msdMayL = hasStrTrigram(msdLetters);
      const msdMayI = hasStrTrigram(msdLeetI);
      const msdMayLL = hasStrTrigram(msdLeetL);
      const msdJ1 = charIdx(msdNorm.charCodeAt(1));
      const msdJ2 = charIdx(msdNorm.charCodeAt(2));
      const msdL1 = msdLetters.length >= 2 ? charIdx(msdLetters.charCodeAt(msdLetters.length - 2)) : -1;
      const msdL2 = msdLetters.length >= 1 ? charIdx(msdLetters.charCodeAt(msdLetters.length - 1)) : -1;
      const msdI1 = charIdx(msdLeetI.charCodeAt(1));
      const msdI2 = charIdx(msdLeetI.charCodeAt(2));
      const msdLL1 = charIdx(msdLeetL.charCodeAt(1));
      const msdLL2 = charIdx(msdLeetL.charCodeAt(2));

      const found = findTriplePeakAttempt(
        msd, e1, e2, baseDiff, msdNorm, msdLetters, msdLeetI, msdLeetL,
        msdEndsWith6, msdHas1, msdWallEnd, msdMayJ, msdMayL, msdMayI, msdMayLL,
        (msdJ1 * 37 + msdJ2) * 37, msdJ2 * 1369,
        msdL1 >= 0 ? (msdL1 * 37 + msdL2) * 37 : -1, msdL2 >= 0 ? msdL2 * 1369 : -1,
        (msdI1 * 37 + msdI2) * 37, msdI2 * 1369,
        (msdLL1 * 37 + msdLL2) * 37, msdLL2 * 1369,
        isTakenFn
      );
      if (found) {
        return { slug: found.slug, canonical: found.canonical, mode: "triple", unixSeconds: sec };
      }
    }

    step++;
    sec++;
  }

  throw new Error("Unable to mint unique acode time slug.");
}

function encodePeakTriadCanonical(val) {
  return encodeCompactTime(((val % TRIAD_BASE) + TRIAD_BASE) % TRIAD_BASE).padStart(3, "0").slice(-3);
}

function encodePeakTriadUrlSafe(val) {
  return encodePeakTriadCanonical(val).replace(/\|/g, "_").replace(/\^/g, "-");
}

function decodePeakTriad(triad) {
  const s = String(triad || "").toLowerCase();
  if (s.length !== 3) return null;
  let total = 0;
  for (let i = 0; i < 3; i++) {
    const ch = s[i] === "_" ? "|" : s[i] === "-" ? "^" : s[i];
    const idx = TIME_ALPHABET.indexOf(ch);
    if (idx < 0) return null;
    total = total * TIME_BASE + idx;
  }
  return total;
}

export function parseWishWindow(raw) {
  const maxBytes = getMaxImageBytes();
  const nonConformingMaxBytes = getNonConformingMaxImageBytes();
  const trimmed = String(raw || "").trim();
  if (!trimmed) {
    return {
      kind: "blank",
      conforming: true,
      triads: [],
      canonicalWish: "",
      quotaCost: CONFORMING_QUOTA_COST,
      maxBytes,
    };
  }

  const tokens = trimmed
    .toLowerCase()
    .split(/[\s^\/-]+/)
    .filter(Boolean);

  if (tokens.length >= 1 && tokens.length <= 2) {
    const mapped = tokens.map((tok) => WISH_TRIAD_ALIASES[tok] || tok);
    if (mapped.every((t) => isA8aTriad(t) && isCleanAcodeSequence(t))) {
      const canonicalWish = mapped.join("^");
      if (isCleanAcodeSequence(canonicalWish)) {
        return {
          kind: "conforming",
          conforming: true,
          triads: mapped,
          canonicalWish,
          quotaCost: CONFORMING_QUOTA_COST,
          maxBytes,
        };
      }
    }
  }

  return {
    kind: "nonconforming",
    conforming: false,
    triads: [],
    canonicalWish: "",
    quotaCost: NONCONFORMING_QUOTA_COST,
    maxBytes: nonConformingMaxBytes,
  };
}

export function mintConforming3PeaksSlug(
  wishTriads,
  unixSeconds = Math.floor(Date.now() / 1000),
  isTakenFn = () => false
) {
  if (!Array.isArray(wishTriads) || wishTriads.length < 1 || wishTriads.length > 2) {
    throw new Error("mintConforming3PeaksSlug expects 1 or 2 conforming a8a triads.");
  }
  const cleanWish = wishTriads.map((t) => (WISH_TRIAD_ALIASES[String(t).toLowerCase()] || String(t).toLowerCase()));
  if (!cleanWish.every((t) => isA8aTriad(t) && isCleanAcodeSequence(t)) || !isCleanAcodeSequence(cleanWish.join("^"))) {
    throw new Error(`Invalid conforming wish triads: ${wishTriads.join("^")}`);
  }

  const baseSec = Math.max(TIME_EPOCH, Math.trunc(unixSeconds));
  let sec = baseSec;
  let msdSkips = 0;
  let lastMsdVal = -1;
  let msd = "";
  let msdNorm = "";
  let msdClean = false;

  const t1 = cleanWish[0];
  const v1 = decodePeakTriad(t1);

  for (let step = 0; step < 2000; ) {
    const elapsed = sec - TIME_EPOCH;
    const msdVal = Math.floor(elapsed / TRIAD_BASE);
    const lsdVal = elapsed % TRIAD_BASE;
    if (msdVal !== lastMsdVal) {
      lastMsdVal = msdVal;
      msd = formatMsdTriad(msdVal);
      msdNorm = msd.replace(/_/g, "0");
      msdClean = isCleanAcodeSequence(msdNorm);
    }

    if (!msdClean) {
      if (msdSkips >= 64) break;
      msdSkips++;
      sec = TIME_EPOCH + (msdVal + 1) * TRIAD_BASE;
      continue;
    }

    if (cleanWish.length === 2) {
      const t2 = cleanWish[1];
      const v2 = decodePeakTriad(t2);
      const needed = (((lsdVal - msdVal - v1 - v2) % TRIAD_BASE) + TRIAD_BASE) % TRIAD_BASE;
      const a8aIdx = NEEDED_TO_CLEAN_A8A[needed];
      const s3Canonical = a8aIdx >= 0 ? A8A_TRIADS[a8aIdx] : encodePeakTriadCanonical(needed);
      const s3Slug = a8aIdx >= 0 ? A8A_TRIADS[a8aIdx] : encodePeakTriadUrlSafe(needed);
      const canonical = `${msd}^${t1}^${t2}^${s3Canonical}`;
      const slug = `${msd}-${t1}-${t2}-${s3Slug}`;
      if (
        isCleanAcodeSequence(canonical) &&
        isCleanAcodeSequence(slug) &&
        !isTakenFn(slug) &&
        !isTakenFn(canonical)
      ) {
        return {
          slug,
          canonical,
          mode: a8aIdx >= 0 ? "wish2-a8a" : "wish2-b38",
          unixSeconds: sec,
        };
      }
    } else {
      // 1-triad wish: try 2 pure a8a solver peaks first at exact second, then exact Base-38 Peak 3 for 0s drift
      const remAfterT1 = (((lsdVal - msdVal - v1) % TRIAD_BASE) + TRIAD_BASE) % TRIAD_BASE;
      const seed = Math.imul(elapsed ^ 0x9e3779b9, 2654435761) >>> 0;
      for (let attempt = 0; attempt < 600; attempt++) {
        const idx2 = ((seed + Math.imul(attempt + 1, 2246822519)) >>> 0) % A8A_COUNT;
        if (!A8A_CLEAN[idx2]) continue;
        const needed = (remAfterT1 - A8A_VALS[idx2] + TRIAD_BASE) % TRIAD_BASE;
        const idx3 = NEEDED_TO_CLEAN_A8A[needed];
        if (idx3 < 0) continue;
        const t2 = A8A_TRIADS[idx2];
        const t3 = A8A_TRIADS[idx3];
        const canonical = `${msd}^${t1}^${t2}^${t3}`;
        const slug = `${msd}-${t1}-${t2}-${t3}`;
        if (
          isCleanAcodeSequence(canonical) &&
          isCleanAcodeSequence(slug) &&
          !isTakenFn(slug) &&
          !isTakenFn(canonical)
        ) {
          return { slug, canonical, mode: "wish1-a8a", unixSeconds: sec };
        }
      }

      for (let attempt = 0; attempt < 200; attempt++) {
        const idx2 = ((seed + Math.imul(attempt + 1, 668265263)) >>> 0) % A8A_COUNT;
        if (!A8A_CLEAN[idx2]) continue;
        const t2 = A8A_TRIADS[idx2];
        const needed = (remAfterT1 - A8A_VALS[idx2] + TRIAD_BASE) % TRIAD_BASE;
        const s3Canonical = encodePeakTriadCanonical(needed);
        const s3Slug = encodePeakTriadUrlSafe(needed);
        const canonical = `${msd}^${t1}^${t2}^${s3Canonical}`;
        const slug = `${msd}-${t1}-${t2}-${s3Slug}`;
        if (
          isCleanAcodeSequence(canonical) &&
          isCleanAcodeSequence(slug) &&
          !isTakenFn(slug) &&
          !isTakenFn(canonical)
        ) {
          return { slug, canonical, mode: "wish1-b38", unixSeconds: sec };
        }
      }
    }

    step++;
    sec++;
  }

  throw new Error("Unable to mint unique conforming 3-peaks slug.");
}

export function decodeAcodeTimestamp(code) {
  const s = String(code || "").trim().toLowerCase();
  const isSep = (ch) => ch === "^" || ch === "-";

  // Single Peak: 7 chars (m0m1m2-p10p11p12)
  if (s.length === 7 && isSep(s[3])) {
    const msd = s.slice(0, 3);
    const p1 = s.slice(4, 7);
    if (!isA8aTriad(p1)) return null;
    const msdVal = decodeCompactTime(msd);
    const lsdVal = decodePeakTriad(p1);
    if (msdVal === null || lsdVal === null) return null;
    return TIME_EPOCH + msdVal * TRIAD_BASE + lsdVal;
  }

  // Triple Peak: 15 chars (m0m1m2-p10p11p12-p20p21p22-p30p31p32)
  // Supports pure-a8a peaks and conforming 2-wish Base-38 complement in Peak 3
  if (s.length === 15 && isSep(s[3]) && isSep(s[7]) && isSep(s[11])) {
    const msd = s.slice(0, 3);
    const p1 = s.slice(4, 7);
    const p2 = s.slice(8, 11);
    const p3 = s.slice(12, 15);
    if (!isA8aTriad(p1) || !isA8aTriad(p2)) return null;
    const msdVal = decodeCompactTime(msd);
    const v1 = decodePeakTriad(p1);
    const v2 = decodePeakTriad(p2);
    const v3 = decodePeakTriad(p3);
    if (msdVal === null || v1 === null || v2 === null || v3 === null) return null;
    const lsdVal = (v1 + v2 + v3 + msdVal) % TRIAD_BASE;
    return TIME_EPOCH + msdVal * TRIAD_BASE + lsdVal;
  }

  return null;
}

export function mintAgyTimeTag(unixSeconds = Math.floor(Date.now() / 1000), isTakenFn = () => false, customPrefix = "") {
  const baseSec = Math.max(TIME_EPOCH, Math.trunc(unixSeconds));
  if (customPrefix && !isCleanAcodeSequence(customPrefix)) {
    const acode = mintAcodeTimeSlug(baseSec, isTakenFn);
    return { tag: acode.slug, slug: acode.slug, unixSeconds: acode.unixSeconds };
  }
  for (let bump = 0; bump < 90; bump++) {
    const elapsed = (baseSec + bump) - TIME_EPOCH;
    const anchor = encodeCompactTime(elapsed + AGY_OFFSET_VAL);
    if (!isCleanAlnumTag(anchor) || !isCleanAcodeSequence(anchor)) continue;
    const tag = `${anchor}-agy`;
    const fullSlug = customPrefix ? `${customPrefix}-${tag}` : tag;
    if (!isCleanAcodeSequence(fullSlug)) continue;
    if (!isTakenFn(fullSlug)) {
      return { tag, slug: fullSlug, unixSeconds: baseSec + bump };
    }
  }
  const acode = mintAcodeTimeSlug(baseSec, isTakenFn);
  return { tag: acode.slug, slug: acode.slug, unixSeconds: acode.unixSeconds };
}

export function detectImageFormat(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 12) return null;
  if (buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47) {
    return { ext: "png", mime: "image/png" };
  }
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return { ext: "jpg", mime: "image/jpeg" };
  }
  if (
    buffer.subarray(0, 4).toString("ascii") === "RIFF" &&
    buffer.subarray(8, 12).toString("ascii") === "WEBP"
  ) {
    return { ext: "webp", mime: "image/webp" };
  }
  if (buffer.subarray(0, 3).toString("ascii") === "GIF") {
    return { ext: "gif", mime: "image/gif" };
  }
  return null;
}

export function sanitizeSlug(raw) {
  const cleaned = String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
  return cleaned;
}

export function pickUniqueSlug(customName, existingImages = {}, unixSeconds = Math.floor(Date.now() / 1000)) {
  const isTaken = (cand) => Boolean(existingImages[cand]);
  const wish = parseWishWindow(customName);
  if (wish.kind === "blank") {
    return mintAcodeTimeSlug(unixSeconds, isTaken).slug;
  }
  if (wish.kind === "conforming") {
    return mintConforming3PeaksSlug(wish.triads, unixSeconds, isTaken).slug;
  }
  const prefix = sanitizeSlug(customName);
  if (!prefix) {
    return mintAcodeTimeSlug(unixSeconds, isTaken).slug;
  }
  return mintAgyTimeTag(unixSeconds, isTaken, prefix).slug;
}

export function buildHostedImageSnippets({
  origin,
  basePath = "",
  storedFilename,
  slug,
  title,
  bytes,
}) {
  const root = `${(origin || "").replace(/\/$/, "")}${basePath.replace(/\/$/, "")}`;
  const directUrl = `${root}/i/${encodeURIComponent(storedFilename)}`;
  const viewerUrl = `${root}/?img=${encodeURIComponent(slug)}`;
  const alt = (title || slug).replace(/["<>]/g, "");

  return {
    directUrl,
    viewerUrl,
    html: `<img src="${directUrl}" alt="${alt}" />`,
    htmlLinked: `<a href="${viewerUrl}"><img src="${directUrl}" alt="${alt}" /></a>`,
    bbcode: `[img]${directUrl}[/img]`,
    bbcodeLinked: `[url=${viewerUrl}][img]${directUrl}[/img][/url]`,
    markdown: `![${alt}](${directUrl})`,
    markdownLinked: `[![${alt}](${directUrl})](${viewerUrl})`,
    bytes,
  };
}

export function buildImageRecord({
  buffer,
  customName = "",
  existingImages = {},
  clientIp = "unknown",
  origin = "",
  basePath = "",
  unixSeconds = Math.floor(Date.now() / 1000),
}) {
  const fmt = detectImageFormat(buffer);
  if (!fmt) {
    const err = new Error("Unsupported file type. Upload PNG, JPEG, WebP, or GIF.");
    err.statusCode = 400;
    throw err;
  }

  const wish = parseWishWindow(customName);
  const maxBytes = getMaxImageBytes();
  if (buffer.length > maxBytes) {
    const err = new Error(
      `Image exceeds ${(maxBytes / 1024).toFixed(0)} KB limit (${(buffer.length / 1024).toFixed(1)} KB received).`
    );
    err.statusCode = 413;
    throw err;
  }
  if (!wish.conforming && buffer.length > wish.maxBytes) {
    const err = new Error(
      `Non-conforming wish tags cap at ${(wish.maxBytes / 1024).toFixed(0)} KB (${(buffer.length / 1024).toFixed(1)} KB received). Enter conforming a8a tags like p1b^f5n or leave blank for ${(maxBytes / 1024).toFixed(0)} KB.`
    );
    err.statusCode = 413;
    throw err;
  }

  const isTaken = (cand) => Boolean(existingImages[cand]);
  let slug;
  let canonicalCode = null;
  if (wish.kind === "blank") {
    const minted = mintAcodeTimeSlug(unixSeconds, isTaken);
    slug = minted.slug;
    canonicalCode = minted.canonical;
  } else if (wish.kind === "conforming") {
    const minted = mintConforming3PeaksSlug(wish.triads, unixSeconds, isTaken);
    slug = minted.slug;
    canonicalCode = minted.canonical;
  } else {
    const prefix = sanitizeSlug(customName);
    if (!prefix) {
      const minted = mintAcodeTimeSlug(unixSeconds, isTaken);
      slug = minted.slug;
      canonicalCode = minted.canonical;
    } else {
      slug = mintAgyTimeTag(unixSeconds, isTaken, prefix).slug;
    }
  }
  const storedFilename = `${slug}.${fmt.ext}`;
  const title = String(customName || "").trim().slice(0, 64) || canonicalCode || slug;
  const etag = `"${crypto.createHash("sha256").update(buffer).digest("hex").slice(0, 16)}"`;

  const snippets = buildHostedImageSnippets({
    origin,
    basePath,
    storedFilename,
    slug,
    title,
    bytes: buffer.length,
  });

  return {
    slug,
    canonical: canonicalCode,
    wishMode: wish.kind,
    conforming: wish.conforming,
    quotaCost: wish.quotaCost,
    storedFilename,
    ext: fmt.ext,
    mime: fmt.mime,
    bytes: buffer.length,
    etag,
    title,
    uploaderIpHash: crypto.createHash("sha256").update(String(clientIp)).digest("hex").slice(0, 12),
    createdAtIso: new Date().toISOString(),
    snippets,
  };
}
