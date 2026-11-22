import { handleServeImage } from "../../lib/handlers.mjs";
export default function handler(req, res) {
  const url = new URL(req.url || "/", "http://localhost");
  const name = req.query?.name || url.searchParams.get("name") || url.pathname.split("/").pop();
  return handleServeImage(req, res, name);
}
