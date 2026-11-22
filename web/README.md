# Twisted23 Image Host (`web/`)

Minimal ImgBB-style image hosting with browser compression (`<= 575 KB`), optional custom slugs (`uncle-norman` or ultra-short 4-character links), and copy-ready embed snippets.

## Features

- **Simple Drag / Drop / Paste Upload:** Instant upload with zero sign-up or friction.
- **Ultra-Short or Custom Links:** Leave custom name blank for a 4-character slug (`/i/a9k2.webp`) or enter a custom name like `Uncle Norman` (`/i/uncle-norman.webp`).
- **575 KB Bandwidth Budget:** Client `<canvas>` auto-compresses oversized images to WebP/JPEG `<= 575 KB` before upload; server enforces magic-byte validation (`PNG`/`JPEG`/`WebP`/`GIF`), byte limit (`575 KB`), daily IP rate limit (`TWISTED23_IP_DAILY_QUOTA`), and immutable CDN cache headers (`public, max-age=31536000, immutable`).
- **Shareable Outputs:** Direct link, Viewer link (`/?img=...`), HTML `<img>`, HTML linked, BBCode, and Markdown, plus a `Download copy` local save option.

## Local Run & Tests

```bash
cd web
npm test
npm start
```

## Hostinger PHP Bundle (`FrmAnTsiTeam`)

```bash
cd web
bash hostinger-php/build_package.sh
```

Upload the contents of `web/dist/FrmAnTsiTeam/` (or extract `web/dist/FrmAnTsiTeam.zip`) into Hostinger's `public_html/FrmAnTsiTeam/` folder so `https://twisted23.com/FrmAnTsiTeam/` runs cleanly alongside your main site.
