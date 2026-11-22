import { handlePreferences } from "../lib/handlers.mjs";
export default function handler(req, res) {
  return handlePreferences(req, res);
}
