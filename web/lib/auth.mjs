import crypto from "node:crypto";
import {
  cleanExactClockExpression,
  decodeClockExpression,
  sanitizeFavorite3LetterOffset,
} from "./base38.mjs";

const EPHEMERAL_FALLBACK_SECRET = crypto.randomBytes(32).toString("hex");
let warnedMissingSecret = false;

export function getAuthSecret() {
  const configured = process.env.TWISTED23_AUTH_SECRET || process.env.AUTH_SECRET;
  if (configured && configured.length >= 16) return configured;
  if (!warnedMissingSecret && process.env.NODE_ENV === "production") {
    warnedMissingSecret = true;
    console.warn("[Twisted23] TWISTED23_AUTH_SECRET is not set; using ephemeral secret for this runtime.");
  }
  return configured || `twisted23-dev-${EPHEMERAL_FALLBACK_SECRET}`;
}

export function normalizePasswordInput(raw) {
  return String(raw ?? "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "");
}

export function passwordLookupIndex(password) {
  const normalized = normalizePasswordInput(password);
  return crypto
    .createHmac("sha256", getAuthSecret())
    .update(`pwd:${normalized}`)
    .digest("hex");
}

export function hashPassword(password) {
  const normalized = normalizePasswordInput(password);
  const salt = crypto.randomBytes(16).toString("hex");
  const derived = crypto.scryptSync(normalized, salt, 64).toString("hex");
  return `${salt}:${derived}`;
}

export function verifyPasswordHash(password, storedHash) {
  const normalized = normalizePasswordInput(password);
  if (!normalized || !storedHash || !storedHash.includes(":")) return false;
  const [salt, expectedHex] = storedHash.split(":", 2);
  const actualBuf = crypto.scryptSync(normalized, salt, 64);
  const expectedBuf = Buffer.from(expectedHex, "hex");
  if (actualBuf.length !== expectedBuf.length) return false;
  return crypto.timingSafeEqual(actualBuf, expectedBuf);
}

/**
 * Mint a unique strict 6-3 Base-38 access password for Tier 1 or Tier 2.
 * Uses the user's favorite 3-letter offset/initials when available (or tier fallback: 'sun'/'joy' for L1, 'nda' for L2).
 */
export function mintTierBase38Password({
  tier,
  favoriteOffset = null,
  existingIndexes = {},
  unixSeconds = Math.floor(Date.now() / 1000),
}) {
  const favClean = sanitizeFavorite3LetterOffset(favoriteOffset);
  const tierContext =
    tier === 2
      ? (favClean ? [favClean, "nda"] : ["nda", "joy", "sun"])
      : (favClean ? [favClean, "sun", "joy"] : ["sun", "joy", "zen"]);

  for (let bump = 0; bump < 60; bump++) {
    const res = cleanExactClockExpression({
      unixSeconds: unixSeconds + bump,
      contextWords: tierContext,
      maxLength: 17,
      alwaysUseDifferenceFormula: true,
      favoriteOffset: tier === 2 && !favClean ? "nda" : favClean,
    });
    const candidate = res.expression;
    const indexKey = passwordLookupIndex(candidate);
    if (!existingIndexes[indexKey]) {
      return {
        password: candidate,
        indexKey,
        hash: hashPassword(candidate),
        mintedUnix: res.unixSeconds,
        decodedUnix: decodeClockExpression(candidate),
        suffixUsed: res.contextWordUsed || candidate.split("-")[1] || "",
      };
    }
  }
  throw new Error("Could not mint a non-colliding Base-38 password.");
}

export const SESSION_COOKIE_NAME = "tw23_session";

export function signSessionToken(payload, ttlSeconds = 60 * 60 * 24 * 14) {
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
  const body = { ...payload, exp };
  const encoded = Buffer.from(JSON.stringify(body), "utf8").toString("base64url");
  const sig = crypto
    .createHmac("sha256", getAuthSecret())
    .update(encoded)
    .digest("base64url");
  return `${encoded}.${sig}`;
}

export function verifySessionToken(token) {
  if (!token || typeof token !== "string" || !token.includes(".")) return null;
  const [encoded, sig] = token.split(".", 2);
  const expectedSig = crypto
    .createHmac("sha256", getAuthSecret())
    .update(encoded)
    .digest("base64url");
  const a = Buffer.from(sig);
  const b = Buffer.from(expectedSig);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const parsed = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
    if (!parsed || typeof parsed !== "object") return null;
    if (parsed.exp && parsed.exp < Math.floor(Date.now() / 1000)) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function parseCookies(cookieHeader) {
  const out = {};
  if (!cookieHeader) return out;
  for (const part of String(cookieHeader).split(";")) {
    const eq = part.indexOf("=");
    if (eq <= 0) continue;
    const k = part.slice(0, eq).trim();
    const v = part.slice(eq + 1).trim();
    try {
      out[k] = decodeURIComponent(v);
    } catch {
      out[k] = v;
    }
  }
  return out;
}

export function serializeSessionCookie(token, { secure = false, maxAge = 60 * 60 * 24 * 14 } = {}) {
  const parts = [
    `${SESSION_COOKIE_NAME}=${encodeURIComponent(token)}`,
    "Path=/",
    "HttpOnly",
    "SameSite=Lax",
    `Max-Age=${maxAge}`,
  ];
  if (secure) parts.push("Secure");
  return parts.join("; ");
}

export function clearSessionCookie({ secure = false } = {}) {
  const parts = [
    `${SESSION_COOKIE_NAME}=`,
    "Path=/",
    "HttpOnly",
    "SameSite=Lax",
    "Max-Age=0",
  ];
  if (secure) parts.push("Secure");
  return parts.join("; ");
}
