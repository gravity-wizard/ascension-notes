import crypto from "node:crypto";

export const DEFAULT_MAX_IMAGE_BYTES = Number(process.env.TWISTED23_MAX_IMAGE_BYTES || 575 * 1024);
export const DEFAULT_IP_DAILY_QUOTA = Number(process.env.TWISTED23_IP_DAILY_QUOTA || 60);

const TIME_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz|^";
const TIME_BASE = 38;
const TIME_EPOCH = 1584540571;
const AGY_OFFSET_VAL = 10 * TIME_BASE * TIME_BASE + 16 * TIME_BASE + 34; // decode("agy") = 15082
const BLOCKED_PARTS = ["666", "anal", "anus", "arse", "bitch", "btch", "cock", "c0ck", "cunt", "damn", "dick", "d1ck", "dyke", "fag", "fck", "fuk", "fuck", "hell", "jizz", "kike", "klan", "nazi", "nig", "n1g", "porn", "p0rn", "puss", "rape", "shit", "sh1t", "slut", "spic", "twat", "wank", "whor", "xxx"];

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

function isCleanAlnumTag(s) {
  if (!/^[0-9a-z]+$/.test(s)) return false;
  const leet = s.replace(/[0134578]/g, (c) => ({ 0: "o", 1: "i", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b" }[c]));
  return !BLOCKED_PARTS.some((b) => s.includes(b) || leet.includes(b));
}

export function mintAgyTimeTag(unixSeconds = Math.floor(Date.now() / 1000), isTakenFn = () => false, customPrefix = "") {
  const baseSec = Math.max(TIME_EPOCH, Math.trunc(unixSeconds));
  for (let bump = 0; bump < 90; bump++) {
    const elapsed = (baseSec + bump) - TIME_EPOCH;
    const anchor = encodeCompactTime(elapsed + AGY_OFFSET_VAL);
    if (!isCleanAlnumTag(anchor)) continue;
    const tag = `${anchor}-agy`;
    const fullSlug = customPrefix ? `${customPrefix}-${tag}` : tag;
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

  const slug = pickUniqueSlug(customName, existingImages, unixSeconds);
  const storedFilename = `${slug}.${fmt.ext}`;
  const title = String(customName || "").trim().slice(0, 64) || slug;
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
