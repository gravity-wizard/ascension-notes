import crypto from "node:crypto";
import { cleanExactClockExpression } from "./base38.mjs";

export const DEFAULT_MAX_IMAGE_BYTES = Number(process.env.TWISTED23_MAX_IMAGE_BYTES || 575 * 1024);
export const L1_DAILY_UPLOAD_QUOTA = Number(process.env.TWISTED23_L1_DAILY_QUOTA || 10);
export const L2_DAILY_UPLOAD_QUOTA = Number(process.env.TWISTED23_L2_DAILY_QUOTA || 50);

export function getMaxImageBytes() {
  const val = Number(process.env.TWISTED23_MAX_IMAGE_BYTES || DEFAULT_MAX_IMAGE_BYTES);
  return Number.isFinite(val) && val > 0 ? val : 575 * 1024;
}

export function getDailyQuotaForTier(tier) {
  if (tier >= 2) return L2_DAILY_UPLOAD_QUOTA;
  if (tier === 1) return L1_DAILY_UPLOAD_QUOTA;
  return 0;
}

export function detectImageFormat(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 12) return null;
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return { ext: "png", mime: "image/png" };
  }
  // JPEG: FF D8 FF
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return { ext: "jpg", mime: "image/jpeg" };
  }
  // WebP: RIFF....WEBP
  if (
    buffer.subarray(0, 4).toString("ascii") === "RIFF" &&
    buffer.subarray(8, 12).toString("ascii") === "WEBP"
  ) {
    return { ext: "webp", mime: "image/webp" };
  }
  return null;
}

export function buildHostedImageSnippets({
  origin,
  storedFilename,
  slug,
  subject,
  base38Tag,
  bytes,
  shortId,
}) {
  const base = origin ? origin.replace(/\/$/, "") : "";
  const directUrl = `${base}/i/${encodeURIComponent(storedFilename)}`;
  const viewerUrl = `${base}/?img=${encodeURIComponent(slug)}`;
  const alt = subject ? `${subject} ${base38Tag}` : base38Tag;
  const escapedAlt = alt.replace(/["<>]/g, "");

  return {
    renameString: `${alt}.${storedFilename.split(".").pop()}`,
    directUrl,
    viewerUrl,
    markdown: `![${alt}](${directUrl})`,
    markdownLinked: `[![${alt}](${directUrl})](${viewerUrl})`,
    htmlLinked: `<a href="${viewerUrl}"><img src="${directUrl}" alt="${escapedAlt}" loading="lazy" /></a>`,
    bbcode: `[img]${directUrl}[/img]`,
    bbcodeLinked: `[url=${viewerUrl}][img]${directUrl}[/img][/url]`,
    axifMarker: `▸[Image: ${alt}.${storedFilename.split(".").pop()} #${shortId}]`,
    bytes,
  };
}

export function buildImageRecord({
  buffer,
  subject = "",
  unixSeconds,
  favoriteOffset = null,
  uploader,
  origin = "",
}) {
  const fmt = detectImageFormat(buffer);
  if (!fmt) {
    const err = new Error("Unsupported image format. Only PNG, JPEG, and WebP are accepted.");
    err.statusCode = 400;
    throw err;
  }

  const maxBytes = getMaxImageBytes();
  if (buffer.length > maxBytes) {
    const err = new Error(
      `Image exceeds ${(maxBytes / 1024).toFixed(0)} KB budget (${(buffer.length / 1024).toFixed(1)} KB received).`
    );
    err.statusCode = 413;
    throw err;
  }

  const cleanSubject = String(subject || "").trim().slice(0, 64);
  const contextWords = cleanSubject ? cleanSubject.split(/[^a-zA-Z0-9]+/).filter(Boolean) : [];
  const clock = cleanExactClockExpression({
    unixSeconds: unixSeconds || Math.floor(Date.now() / 1000),
    contextWords,
    maxLength: 17,
    alwaysUseDifferenceFormula: true,
    favoriteOffset,
  });

  const shortId = crypto.createHash("sha256").update(buffer).digest("hex").slice(0, 4);
  const slug = `${clock.expression}-${shortId}`.replace(/[^0-9a-z-]/g, "");
  const storedFilename = `${slug}.${fmt.ext}`;
  const etag = `"${crypto.createHash("sha256").update(buffer).digest("hex").slice(0, 16)}"`;

  const snippets = buildHostedImageSnippets({
    origin,
    storedFilename,
    slug,
    subject: cleanSubject,
    base38Tag: clock.expression,
    bytes: buffer.length,
    shortId,
  });

  return {
    slug,
    storedFilename,
    ext: fmt.ext,
    mime: fmt.mime,
    bytes: buffer.length,
    etag,
    shortId,
    subject: cleanSubject,
    base38Tag: clock.expression,
    unixSeconds: clock.unixSeconds,
    uploaderId: uploader.id,
    uploaderTier: uploader.tier,
    createdAtIso: new Date().toISOString(),
    snippets,
  };
}
