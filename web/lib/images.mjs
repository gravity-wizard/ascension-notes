import crypto from "node:crypto";

export const DEFAULT_MAX_IMAGE_BYTES = Number(process.env.TWISTED23_MAX_IMAGE_BYTES || 575 * 1024);
export const DEFAULT_IP_DAILY_QUOTA = Number(process.env.TWISTED23_IP_DAILY_QUOTA || 60);

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

export function isCleanAcodeSequence(rawCode) {
  const joined = String(rawCode || "")
    .toLowerCase()
    .replace(/[\^-]/g, "")
    .replace(/_/g, "0");
  const lettersOnly = joined.replace(/[0-9]/g, "");
  const digitsOnly = joined.replace(/[a-z]/g, "");
  const leetI = joined.replace(/[01345789]/g, (c) => ({ 0: "o", 1: "i", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b", 9: "g" }[c]));
  const leetL = joined.replace(/[01345789]/g, (c) => ({ 0: "o", 1: "l", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b", 9: "g" }[c]));

  return !BLOCKED_PARTS.some(
    (b) =>
      joined.includes(b) ||
      lettersOnly.includes(b) ||
      digitsOnly.includes(b) ||
      leetI.includes(b) ||
      leetL.includes(b)
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

export function isA8aTriad(s) {
  return /^[a-z][1-57-9][a-z]$/.test(String(s || ""));
}

export function mintAcodeTimeSlug(unixSeconds = Math.floor(Date.now() / 1000), isTakenFn = () => false) {
  const sec = Math.max(TIME_EPOCH, Math.trunc(unixSeconds));
  const elapsed = sec - TIME_EPOCH;
  const msdVal = Math.floor(elapsed / TRIAD_BASE);
  const lsdVal = elapsed % TRIAD_BASE;
  const msd = formatMsdTriad(msdVal);

  // 1. Single Peak: ___^a8a (URL-safe: ___-a8a) when LSD triad is naturally a8a and clean/free
  const directLsd = encodeCompactTime(lsdVal);
  if (directLsd.length === 3 && isA8aTriad(directLsd)) {
    const canonical = `${msd}^${directLsd}`;
    const slug = `${msd}-${directLsd}`;
    if (isCleanAcodeSequence(canonical) && !isTakenFn(slug) && !isTakenFn(canonical)) {
      return { slug, canonical, mode: "single", unixSeconds: sec };
    }
  }

  // 2. Triple Peak: ___^a8a^a8a^a8a (URL-safe: ___-a8a-a8a-a8a)
  // Exact math: (v(t1) + v(t2) + v(t3) + msdVal) % 54872 === lsdVal
  for (let attempt = 0; attempt < 5000; attempt++) {
    const h1 = (Math.imul(elapsed ^ 0x9e3779b9, 2654435761) ^ Math.imul(attempt + 1, 2246822519)) >>> 0;
    const h2 = (Math.imul(elapsed ^ 0x85ebca6b, 3266489917) ^ Math.imul(attempt + 1, 668265263)) >>> 0;
    const t1 = a8aFromIndex(h1 % A8A_COUNT);
    const t2 = a8aFromIndex(h2 % A8A_COUNT);
    if (!isCleanAcodeSequence(t1) || !isCleanAcodeSequence(t2)) continue;

    const v1 = decodeCompactTime(t1);
    const v2 = decodeCompactTime(t2);
    const needed = (((lsdVal - msdVal - v1 - v2) % TRIAD_BASE) + TRIAD_BASE) % TRIAD_BASE;
    const t3 = encodeCompactTime(needed);
    if (t3.length !== 3 || !isA8aTriad(t3)) continue;

    const canonical = `${msd}^${t1}^${t2}^${t3}`;
    const slug = `${msd}-${t1}-${t2}-${t3}`;
    if (!isCleanAcodeSequence(canonical)) continue;
    if (!isTakenFn(slug) && !isTakenFn(canonical)) {
      return { slug, canonical, mode: "triple", unixSeconds: sec };
    }
  }

  const fallback = `${msd}-a1a-a1a-a1a`;
  return { slug: fallback, canonical: fallback.replace(/-/g, "^"), mode: "triple", unixSeconds: sec };
}

export function decodeAcodeTimestamp(code) {
  const parts = String(code || "").trim().split(/[\^-]/);
  if (parts.length !== 2 && parts.length !== 4) return null;
  const [msd, ...peaks] = parts;
  if (msd.length !== 3 || !peaks.every((p) => isA8aTriad(p))) return null;
  const msdVal = decodeCompactTime(msd);
  if (msdVal === null) return null;

  let lsdVal;
  if (peaks.length === 1) {
    lsdVal = decodeCompactTime(peaks[0]);
  } else {
    const sum = peaks.reduce((acc, p) => acc + decodeCompactTime(p), 0);
    lsdVal = (sum + msdVal) % TRIAD_BASE;
  }
  return TIME_EPOCH + msdVal * TRIAD_BASE + lsdVal;
}

export function mintAgyTimeTag(unixSeconds = Math.floor(Date.now() / 1000), isTakenFn = () => false, customPrefix = "") {
  const baseSec = Math.max(TIME_EPOCH, Math.trunc(unixSeconds));
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
  const fallback = `${encodeCompactTime(baseSec - TIME_EPOCH + AGY_OFFSET_VAL).replace(/[^0-9a-z]/g, "x")}-agy`;
  return { tag: fallback, slug: customPrefix ? `${customPrefix}-${fallback}` : fallback, unixSeconds: baseSec };
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
  const prefix = sanitizeSlug(customName);
  if (!prefix) {
    return mintAcodeTimeSlug(unixSeconds, (cand) => Boolean(existingImages[cand])).slug;
  }
  return mintAgyTimeTag(unixSeconds, (cand) => Boolean(existingImages[cand]), prefix).slug;
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

  const maxBytes = getMaxImageBytes();
  if (buffer.length > maxBytes) {
    const err = new Error(
      `Image exceeds ${(maxBytes / 1024).toFixed(0)} KB limit (${(buffer.length / 1024).toFixed(1)} KB received).`
    );
    err.statusCode = 413;
    throw err;
  }

  const prefix = sanitizeSlug(customName);
  let slug;
  let canonicalCode = null;
  if (!prefix) {
    const minted = mintAcodeTimeSlug(unixSeconds, (cand) => Boolean(existingImages[cand]));
    slug = minted.slug;
    canonicalCode = minted.canonical;
  } else {
    slug = mintAgyTimeTag(unixSeconds, (cand) => Boolean(existingImages[cand]), prefix).slug;
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
