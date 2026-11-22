import { handleHealth } from "../lib/handlers.mjs";
export default function handler(req, res) {
  return handleHealth(req, res);
}
