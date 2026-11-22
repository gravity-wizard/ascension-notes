import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  handleGetImageMeta,
  handleHealth,
  handleImageUpload,
  handleServeImage,
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
  ".webp": "image/webp",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
};

export function createAppServer({ store = defaultStore } = {}) {
  return http.createServer(async (req, res) => {
    try {
      const parsed = new URL(req.url || "/", "http://localhost");
      const pathname = parsed.pathname;

      if (pathname === "/api/health") return await handleHealth(req, res);
      if (pathname === "/api/images/upload") return await handleImageUpload(req, res, store);
      if (pathname.startsWith("/api/images/")) {
        const slug = pathname.slice("/api/images/".length);
        return await handleGetImageMeta(req, res, slug, store);
      }
      if (pathname.startsWith("/i/")) {
        const name = pathname.slice("/i/".length);
        return await handleServeImage(req, res, name, store);
      }
      if (pathname.startsWith("/api/")) {
        return sendJson(res, 404, { ok: false, error: `Unknown API route: ${pathname}` });
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
    console.log(`Twisted23 Image Host listening on http://localhost:${port}`);
  });
}
