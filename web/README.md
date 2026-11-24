# Twisted23 Image Host (`web/`)

Minimal ImgBB-style image hosting with browser compression (`<= 575 KB`), optional custom slugs (`uncle-norman` or ultra-short 4-character links), and copy-ready embed snippets.

## Features

- **Simple Drag / Drop / Paste Upload:** Instant upload with zero sign-up or friction.
- **Wish-Window Conforming `3peaks` vs. Non-Conforming Tags:**
  - **Blank Wish-Window:** Mints a 7-char Single Peak (`/i/2p5-a9a.webp`) or 15-char Triple Peak (`/i/2p5-k9m-r7p-b4z.webp`) at `575 KB` max and `1×` daily quota.
  - **Conforming `a8a` Tags (Smart Ascenders):** Enter 1 or 2 conforming `[a-z][1-57-9][a-z]` triads—such as **`p1b^f5n`** (or **`pi1browser full5screen`**)—to weave them directly into a 15-char 3-peaks link (`/i/2p5-p1b-f5n-ms7.webp`) with exact 0-second timestamp recovery, full `575 KB` budget, and `1×` quota cost.
  - **Non-Conforming Tags (Come at a Price):** Arbitrary phrases like `Uncle Norman` pay the `-<clock>-agy` length tax (`/i/uncle-norman-2p9ck1-agy.webp`), cap at `385 KB`, and consume `2×` daily upload quota units.
- **Bandwidth & Safety Guardrails:** Client `<canvas>` auto-compresses images within the active tier budget before upload; server enforces magic-byte validation (`PNG`/`JPEG`/`WebP`/`GIF`), byte limits, daily IP rate limit (`TWISTED23_IP_DAILY_QUOTA`), and immutable CDN cache headers (`public, max-age=31536000, immutable`).
- **Shareable Outputs:** Direct link, Viewer link (`/?img=...`), SLogBog `sup×2` centered BBCode, HTML `<img>`, HTML linked, BBCode, and Markdown, plus a `Download copy` local save option.

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
