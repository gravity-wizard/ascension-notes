export function isHttpsRequest(req) {
  const proto = req.headers["x-forwarded-proto"];
  if (typeof proto === "string") return proto.split(",")[0].trim() === "https";
  return Boolean(req.socket && req.socket.encrypted);
}

export function getClientIp(req) {
  const cfIp = req.headers["cf-connecting-ip"];
  if (typeof cfIp === "string" && cfIp.trim()) {
    return cfIp.trim();
  }
  const fwd = req.headers["x-forwarded-for"];
  if (typeof fwd === "string" && fwd.trim()) {
    return fwd.split(",")[0].trim();
  }
  return req.socket?.remoteAddress || "127.0.0.1";
}

export async function readJsonBody(req, maxBytes = 1024 * 256) {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string") {
    return req.body.trim() ? JSON.parse(req.body) : {};
  }
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxBytes) {
      const err = new Error("Payload too large.");
      err.statusCode = 413;
      throw err;
    }
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) return {};
  return JSON.parse(raw);
}

export function sendJson(res, statusCode, payload) {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, private");
  res.setHeader("CDN-Cache-Control", "no-store");
  res.setHeader("Cloudflare-CDN-Cache-Control", "no-store");
  res.end(JSON.stringify(payload));
}
