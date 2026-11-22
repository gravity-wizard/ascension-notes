# Twisted23.com · Base-38 Photo Naming Demo (`web/`)

Interactive web demo showcasing exact Base-38 `6-3` smart photo naming (`2p4uop-sun.png`) with three-tier access control:

- **Level 0 (Open Link):** Anyone with the link can explore curated sample photos, edit subjects, and generate exact Base-38 `6-3` filenames.
- **Level 1 (Registered & Email-Verified):** Register with name, email, and an optional favorite 3-letter offset/initials (`joy`, `sun`, `hmf`). A personal 10-character `6-3` Base-38 password is sent to your email; signing in verifies your email in one step and unlocks custom single-photo uploads + persistent favorite offset preferences.
- **Level 2 (Signed NDA):** Level 1 members sign the built-in mutual NDA (`nda_template.md`) with typed e-signature, exact Base-38 + UTC timestamp, and SHA-256 audit receipt hash to mint a Level 2 Base-38 password (`...-nda`) and unlock JPEG EXIF capture-time extraction, multi-photo batch naming, NDA receipt download, and AXIF Markdown export.

## Local Development (`macmini23` / local machine)

```bash
cd web
npm test
npm start
```

When `RESEND_API_KEY` is unset locally, minted Base-38 passwords appear automatically in the **Dev Inbox** (`GET /api/dev-outbox`) for 1-click testing.

## Deploying `web/` to Vercel (`Twisted23.com`)

Set Vercel Root Directory to `web/` and configure environment variables:

- `TWISTED23_AUTH_SECRET`: random 32+ char secret for HMAC blind indexes and `tw23_session` cookies
- `TWISTED23_ADMIN_KEY`: secret for `/api/admin/audit` and `/api/admin/revoke` (`x-admin-key` header)
- `RESEND_API_KEY` & `TWISTED23_FROM_EMAIL`: sends real Level 1 / Level 2 Base-38 password emails
- `KV_REST_API_URL` & `KV_REST_API_TOKEN` (Vercel KV / Upstash Redis): persistent production store (falls back to `.data/twisted23-store.json` locally)
