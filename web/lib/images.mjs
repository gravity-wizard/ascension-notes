import crypto from "node:crypto";

export const DEFAULT_MAX_IMAGE_BYTES = Number(process.env.TWISTED23_MAX_IMAGE_BYTES || 575 * 1024);
export const DEFAULT_IP_DAILY_QUOTA = Number(process.env.TWISTED23_IP_DAILY_QUOTA || 60);

const SHORT_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz";

export function getMaxImageBytes() {
  const val = Number(process.env.TWISTED23_MAX_IMAGE_BYTES || DEFAULT_MAX_IMAGE_BYTES);
  return Number.isFinite(val) && val > 0 ? val : 575 * 1024;
}

export function getDailyIpQuota() {
  const val = Number(process.env.TWISTED23_IP_DAILY_QUOTA || DEFAULT_IP_DAILY_QUOTA);
  return Number.isFinite(val) && val > 0 ? val : 60;
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
    .slice(0, 48);
  return cleaned;
}

export function randomShortCode(length = 4) {
  const bytes = crypto.randomBytes(length);
  let out = "";
  for (let i = 0; i < length; i++) {
    out += SHORT_ALPHABET[bytes[i] % SHORT_ALPHABET.length];
  }
  return out;
}

export function pickUniqueSlug(customName, existingImages = {}) {
  const requested = sanitizeSlug(customName);
  if (requested) {
    if (!existingImages[requested]) return requested;
    for (let n = 2; n <= 99; n++) {
      const candidate = `${requested}-${n}`;
      if (!existingImages[candidate]) return candidate;
    }
    return `${requested}-${randomShortCode(3)}`;
  }

  for (let len = 4; len <= 6; len++) {
    for (let attempt = 0; attempt < 24; attempt++) {
      const candidate = randomShortCode(len);
      if (!existingImages[candidate]) return candidate;
    }
  }
  return randomShortCode(7);
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

  const slug = pickUniqueSlug(customName, existingImages);
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
