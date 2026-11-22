import { handleDevOutbox } from "../lib/handlers.mjs";
export default function handler(req, res) {
  return handleDevOutbox(req, res);
}
