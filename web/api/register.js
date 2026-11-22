import { handleRegister } from "../lib/handlers.mjs";
export default function handler(req, res) {
  return handleRegister(req, res);
}
