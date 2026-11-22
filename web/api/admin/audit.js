import { handleAdminAudit } from "../../lib/handlers.mjs";
export default function handler(req, res) {
  return handleAdminAudit(req, res);
}
