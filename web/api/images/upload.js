import { handleImageUpload } from "../../lib/handlers.mjs";
export default function handler(req, res) {
  return handleImageUpload(req, res);
}
