import { handleSession } from "../lib/handlers.mjs";
export default function handler(req, res) {
  return handleSession(req, res);
}
