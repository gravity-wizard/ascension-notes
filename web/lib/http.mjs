import { parseCookies, verifySessionToken } from "./auth.mjs";

export function isHttpsRequest(req) {
  const proto = req.headers["x-forwarded-proto"];
  if (typeof proto === "string") return proto.split(",")[0].trim() === "https";
  return Boolean(req.socket && req.socket.encrypted);
}

export function getClientIp(req) {
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

export function sendJson(res, statusCode, payload, { setCookie = null } = {}) {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  if (setCookie) {
    res.setHeader("Set-Cookie", setCookie);
  }
  res.end(JSON.stringify(payload));
}

export function devOutboxEnabled(req) {
  if (process.env.TWISTED23_DEV_OUTBOX === "true") return true;
  if (process.env.TWISTED23_DEV_OUTBOX === "false") return false;
  if (process.env.VERCEL_ENV === "production" || process.env.RESEND_API_KEY) return false;
  const host = String(req?.headers?.host || "");
  return (
    process.env.NODE_ENV !== "production" ||
    host.startsWith("localhost") ||
    host.startsWith("127.0.0.1")
  );
}

export async function resolveAuthenticatedUser(req, store) {
  const cookies = parseCookies(req.headers.cookie);
  const token = cookies.tw23_session;
  const claims = verifySessionToken(token);
  if (!claims || !claims.userId) return null;
  const state = await store.readState();
  const user = state.usersById[claims.userId];
  if (!user || user.revokedAt) return null;
  return user;
}

export function sanitizePublicUser(user) {
  if (!user) {
    return {
      authenticated: false,
      tier: 0,
      tierLabel: "Level 0 · Open Link",
      name: "Guest",
      email: null,
      emailVerified: false,
      favoriteOffset: "",
      ndaSigned: false,
      ndaReceipt: null,
    };
  }
  return {
    authenticated: true,
    id: user.id,
    tier: user.tier,
    tierLabel: user.tier >= 2 ? "Level 2 · Signed NDA" : "Level 1 · Registered",
    name: user.name,
    email: user.email,
    emailVerified: Boolean(user.emailVerified),
    favoriteOffset: user.favoriteOffset || "",
    ndaSigned: Boolean(user.ndaReceipt),
    ndaReceipt: user.ndaReceipt
      ? {
          receiptId: user.ndaReceipt.receiptId,
          signedAtIso: user.ndaReceipt.signedAtIso,
          signedAtBase38: user.ndaReceipt.signedAtBase38,
          receiptHash: user.ndaReceipt.receiptHash,
        }
      : null,
  };
}
