import { handleLogin } from "../lib/handlers.mjs";
export default function handler(req, res) {
  return handleLogin(req, res);
}
