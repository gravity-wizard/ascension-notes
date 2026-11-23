import crypto from "node:crypto";
import {
  getClientIp,
  isHttpsRequest,
  readJsonBody,
  sendJson,
} from "./http.mjs";
import {
  buildHostedImageSnippets,
  buildImageRecord,
  getDailyIpQuota,
  getMaxImageBytes,
} from "./images.mjs";
import { defaultStore } from "./store.mjs";

function requestOrigin(req) {
  const proto = isHttpsRequest(req) ? "https" : "http";
  const host = req.headers["x-forwarded-host"] || req.headers.host || "twisted23.com";
  return `${proto}://${host}`;
}

export async function handleHealth(req, res) {
  sendJson(res, 200, {
    ok: true,
    brand: "Twisted23",
    maxImageBytes: getMaxImageBytes(),
    dailyIpQuota: getDailyIpQuota(),
  });
}

export async function handleImageUpload(req, res, store = defaultStore) {
  if (req.method !== "POST") {
    return sendJson(res, 405, { ok: false, error: "Method not allowed" });
  }

  const maxBytes = getMaxImageBytes();
  const ctype = String(req.headers["content-type"] || "").toLowerCase();
  let buffer;
  let customName = "";

  if (ctype.startsWith("application/octet-stream")) {
    const chunks = [];
    let size = 0;
    const hardLimit = maxBytes + 64 * 1024;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > hardLimit) {
        return sendJson(res, 413, { ok: false, error: `Image exceeds ${(maxBytes / 1024).toFixed(0)} KB limit.` });
      }
      chunks.push(chunk);
    }
    buffer = Buffer.concat(chunks);
    const rawHeaderName = String(req.headers["x-custom-name"] || "");
    try {
      customName = decodeURIComponent(rawHeaderName);
    } catch {
      customName = rawHeaderName;
    }
  } else {
    const body = await readJsonBody(req, Math.ceil(maxBytes * 1.45) + 64 * 1024);
    const rawDataUrlOrB64 = String(body.dataBase64 || body.dataUrl || "").trim();
    if (!rawDataUrlOrB64) {
      return sendJson(res, 400, { ok: false, error: "Choose an image file to upload." });
    }
    const b64Part = rawDataUrlOrB64.includes(",")
      ? rawDataUrlOrB64.split(",", 2)[1]
      : rawDataUrlOrB64;
    buffer = Buffer.from(b64Part, "base64");
    customName = String(body.customName || body.subject || "");
  }

  const ip = getClientIp(req);
  const ipHash = crypto.createHash("sha256").update(String(ip)).digest("hex").slice(0, 12);
  const today = new Date().toISOString().slice(0, 10);
  const quota = getDailyIpQuota();
  const dayKey = `ip:${ipHash}:${today}`;

  const preState = await store.readState();
  const used = preState.dailyUploadsByUserDay[dayKey] || 0;
  if (used >= quota) {
    return sendJson(res, 429, {
      ok: false,
      error: `Daily upload limit reached (${used}/${quota}). Try again tomorrow or save a compressed copy locally.`,
    });
  }

  const record = buildImageRecord({
    buffer,
    customName,
    existingImages: preState.imagesBySlug || {},
    clientIp: ip,
    origin: requestOrigin(req),
  });

  await store.saveImageBlob(record.storedFilename, buffer);

  const quotaAfter = await store.updateState((state) => {
    state.imagesBySlug[record.slug] = record;
    state.dailyUploadsByUserDay[dayKey] = (state.dailyUploadsByUserDay[dayKey] || 0) + 1;
    const nowUsed = state.dailyUploadsByUserDay[dayKey];
    return {
      dailyQuota: quota,
      dailyUsed: nowUsed,
      dailyRemaining: Math.max(0, quota - nowUsed),
    };
  });

  return sendJson(res, 200, {
    ok: true,
    image: record,
    hosting: {
      maxImageBytes: maxBytes,
      ...quotaAfter,
    },
  });
}

export async function handleGetImageMeta(req, res, slugInput, store = defaultStore) {
  const cleanSlug = String(slugInput || "")
    .trim()
    .replace(/\^/g, "-")
    .replace(/[^0-9a-z_-]/g, "");
  if (!cleanSlug) {
    return sendJson(res, 400, { ok: false, error: "Invalid image id." });
  }
  const state = await store.readState();
  const record = state.imagesBySlug[cleanSlug];
  if (!record) {
    return sendJson(res, 404, { ok: false, error: "Image not found." });
  }
  const snippets = buildHostedImageSnippets({
    origin: requestOrigin(req),
    storedFilename: record.storedFilename,
    slug: record.slug,
    title: record.title,
    bytes: record.bytes,
  });
  return sendJson(res, 200, {
    ok: true,
    image: {
      ...record,
      snippets,
    },
  });
}

export async function handleServeImage(req, res, filenameInput, store = defaultStore) {
  const safeName = String(filenameInput || "").trim().replace(/^\/+/, "");
  if (!/^[0-9a-z_-]+\.(webp|jpg|png|gif)$/.test(safeName)) {
    res.statusCode = 400;
    return res.end("Invalid image filename");
  }
  const slug = safeName.replace(/\.(webp|jpg|png|gif)$/, "");
  const state = await store.readState();
  const record = state.imagesBySlug[slug];
  if (!record || record.storedFilename !== safeName) {
    res.statusCode = 404;
    return res.end("Not found");
  }

  if (req.headers["if-none-match"] && req.headers["if-none-match"] === record.etag) {
    res.statusCode = 304;
    res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
    res.setHeader("CDN-Cache-Control", "public, max-age=31536000, immutable");
    res.setHeader("Cloudflare-CDN-Cache-Control", "public, max-age=31536000, immutable");
    res.setHeader("ETag", record.etag);
    return res.end();
  }

  const blob = await store.readImageBlob(safeName);
  if (!blob) {
    res.statusCode = 404;
    return res.end("Blob not found");
  }

  res.statusCode = 200;
  res.setHeader("Content-Type", record.mime);
  res.setHeader("Content-Length", String(blob.length));
  res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
  res.setHeader("CDN-Cache-Control", "public, max-age=31536000, immutable");
  res.setHeader("Cloudflare-CDN-Cache-Control", "public, max-age=31536000, immutable");
  res.setHeader("ETag", record.etag);
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.end(blob);
}
