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

## Bandwidth-Capped Image Hosting & 0 KB Mode

- **0 KB Local Rename Mode:** Pure browser Base-38 rename + JPEG EXIF `DateTimeOriginal` extraction with copy/download buttons and AXIF marker (`▸[Image: ...]`) — zero upload traffic.
- **Host on Twisted23 (ImgBB Tags):** Adaptive client-side `<canvas>` WebP/JPEG compression enforces a configurable per-image byte budget (**570 KB default**, with **385 KB** & **57 KB** quick caps or `TWISTED23_MAX_IMAGE_BYTES` env/config) *before* upload.
- **Hostinger Guardrails:** Daily upload quotas (**L0: 0**, **L1: 10/day**, **L2: 50/day**), magic-byte validation (`WebP` / `JPEG` / `PNG`), immutable cache headers (`public, max-age=31536000, immutable`) + `ETag`/`304`, and optional Referer hotlink allowlist.
- **ImgBB Outputs:** Direct `/i/<slug>` URL, `/?img=<slug>` viewer link, Markdown, Linked Markdown Badge, HTML Linked `<img>`, BBCode `[url][img]`, and Ascension AXIF marker.

## Deploying to Hostinger Shared PHP Hosting (`Twisted23.com`)

```bash
cd web
bash hostinger-php/build_package.sh
```

Upload everything inside `web/dist/hostinger-public_html/` (including `.htaccess`) to Hostinger's `public_html/` directory, set `auth_secret` and `admin_key` in `config.php` (or Hostinger environment), and enable **Cloudflare** caching in front of `twisted23.com` so repeated `/i/*` image hits serve from edge cache without consuming Hostinger bandwidth.

## Deploying to Vercel (`Twisted23.com`)

Set Vercel Root Directory to `web/` and configure environment variables:

- `TWISTED23_AUTH_SECRET`: random 32+ char secret for HMAC blind indexes and `tw23_session` cookies
- `TWISTED23_ADMIN_KEY`: secret for `/api/admin/audit` and `/api/admin/revoke` (`x-admin-key` header)
- `TWISTED23_MAX_IMAGE_BYTES`: optional byte cap override (defaults to `583680` = 570 KB; set `394240` for 385 KB)
- `RESEND_API_KEY` & `TWISTED23_FROM_EMAIL`: sends real Level 1 / Level 2 Base-38 password emails
- `KV_REST_API_URL` & `KV_REST_API_TOKEN` (Vercel KV / Upstash Redis): persistent production store (falls back to `.data/twisted23-store.json` locally)
