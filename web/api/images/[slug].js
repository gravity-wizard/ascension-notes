import { handleGetImageMeta } from "../../lib/handlers.mjs";
export default function handler(req, res) {
  const url = new URL(req.url || "/", "http://localhost");
  const slug = req.query?.slug || url.pathname.split("/").pop();
  return handleGetImageMeta(req, res, slug);
}
