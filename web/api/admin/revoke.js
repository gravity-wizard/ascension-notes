import { handleAdminRevoke } from "../../lib/handlers.mjs";
export default function handler(req, res) {
  return handleAdminRevoke(req, res);
}
