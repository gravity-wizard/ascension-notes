import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  handleAdminAudit,
  handleAdminRevoke,
  handleDevOutbox,
  handleGetNda,
  handleHealth,
  handleLogin,
  handleLogout,
  handlePreferences,
  handleRegister,
  handleSession,
  handleSignNda,
} from "./lib/handlers.mjs";
import { sendJson } from "./lib/http.mjs";
import { defaultStore } from "./lib/store.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.resolve(__dirname, "public");

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
};

export function createAppServer({ store = defaultStore } = {}) {
  return http.createServer(async (req, res) => {
    try {
      const parsed = new URL(req.url || "/", "http://localhost");
      const pathname = parsed.pathname;

      if (pathname === "/api/health") return await handleHealth(req, res);
      if (pathname === "/api/session") return await handleSession(req, res, store);
      if (pathname === "/api/register") return await handleRegister(req, res, store);
      if (pathname === "/api/login") return await handleLogin(req, res, store);
      if (pathname === "/api/logout") return await handleLogout(req, res);
      if (pathname === "/api/preferences") return await handlePreferences(req, res, store);
      if (pathname === "/api/nda") return await handleGetNda(req, res, store);
      if (pathname === "/api/nda/sign") return await handleSignNda(req, res, store);
      if (pathname === "/api/dev-outbox") return await handleDevOutbox(req, res, store);
      if (pathname === "/api/admin/audit") return await handleAdminAudit(req, res, store);
      if (pathname === "/api/admin/revoke") return await handleAdminRevoke(req, res, store);
      if (pathname.startsWith("/api/")) {
        return sendJson(res, 404, { ok: false, error: `Unknown API route: ${pathname}` });
      }

      if (pathname === "/lib/base38.mjs") {
        const b38 = await fs.readFile(path.resolve(__dirname, "lib", "base38.mjs"));
        res.statusCode = 200;
        res.setHeader("Content-Type", "application/javascript; charset=utf-8");
        return res.end(b38);
      }

      const relPath = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
      const safePath = path.resolve(PUBLIC_DIR, relPath);
      if (!safePath.startsWith(PUBLIC_DIR)) {
        res.statusCode = 403;
        return res.end("Forbidden");
      }

      let fileBuf;
      let targetPath = safePath;
      try {
        fileBuf = await fs.readFile(targetPath);
      } catch {
        targetPath = path.resolve(PUBLIC_DIR, "index.html");
        fileBuf = await fs.readFile(targetPath);
      }

      const ext = path.extname(targetPath);
      res.statusCode = 200;
      res.setHeader("Content-Type", MIME_TYPES[ext] || "application/octet-stream");
      res.end(fileBuf);
    } catch (err) {
      console.error("[Twisted23 Server Error]", err);
      sendJson(res, err.statusCode || 500, { ok: false, error: err.message || "Internal server error" });
    }
  });
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const port = Number(process.env.PORT || 3023);
  const server = createAppServer();
  server.listen(port, "0.0.0.0", () => {
    console.log(`Twisted23.com Photo Naming Demo listening on http://localhost:${port}`);
  });
}
