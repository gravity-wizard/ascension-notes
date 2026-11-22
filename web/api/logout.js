import { handleLogout } from "../lib/handlers.mjs";
export default function handler(req, res) {
  return handleLogout(req, res);
}
