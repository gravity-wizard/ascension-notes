import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  cleanExactClockExpression,
  decodeClockExpression,
  decodeJesusClock,
  sanitizeFavorite3LetterOffset,
} from "../lib/base38.mjs";
import { extractExifFromJpeg } from "../public/exif.js";
import { createStore } from "../lib/store.mjs";
import { createAppServer } from "../server.mjs";

test("JS Base-38 engine matches Python/Swift canonical vectors and 6-3 format", () => {
  const ts = decodeJesusClock("2p41w4");
  for (const [fav, word] of [["joy", "joy"], ["sun", "sun"], ["HMF", "hmf"]]) {
    const res = cleanExactClockExpression({
      unixSeconds: ts,
      contextWords: ["Weeping", "Willow"],
      alwaysUseDifferenceFormula: true,
      favoriteOffset: fav,
    });
    assert.equal(res.expression.length, 10);
    assert.ok(res.expression.endsWith(`-${word}`), res.expression);
    assert.equal(decodeClockExpression(res.expression), ts);
  }

  for (const bad of ["2p7fuk", "2shit1", "2p7|^a", "2||000", "2^0000", "|00000", "^|||||"]) {
    const badTs = decodeJesusClock(bad);
    const res = cleanExactClockExpression({ unixSeconds: badTs, maxLength: 17 });
    assert.ok(!res.expression.includes("|"), res.expression);
    assert.ok(!res.expression.includes("^"), res.expression);
    assert.ok(res.expression.length <= 17);
    assert.equal(decodeClockExpression(res.expression), badTs);
  }

  assert.equal(sanitizeFavorite3LetterOffset("  HMF "), "hmf");
  assert.equal(sanitizeFavorite3LetterOffset("fuk"), null);
});

test("JPEG EXIF extractor reads DateTimeOriginal from APP1 header", () => {
  // Minimal big-endian JPEG APP1 Exif header with 1 ExifIFD pointer -> 1 DateTimeOriginal ASCII entry
  const dateStr = "2026:11:22 08:15:15\0"; // 20 bytes
  const buf = new ArrayBuffer(128);
  const view = new DataView(buf);
  const bytes = new Uint8Array(buf);
  view.setUint16(0, 0xffd8, false); // SOI
  view.setUint16(2, 0xffe1, false); // APP1
  view.setUint16(4, 110, false);    // segment length
  bytes.set([0x45, 0x78, 0x69, 0x66, 0x00, 0x00], 6); // "Exif\0\0"
  const tiff = 12;
  view.setUint16(tiff, 0x4d4d, false); // 'MM' big endian
  view.setUint16(tiff + 2, 42, false);
  view.setUint32(tiff + 4, 8, false);  // IFD0 offset = 8
  const ifd0 = tiff + 8;
  view.setUint16(ifd0, 1, false);      // 1 entry in IFD0
  view.setUint16(ifd0 + 2, 0x8769, false); // ExifIFD pointer
  view.setUint16(ifd0 + 4, 4, false);      // LONG
  view.setUint32(ifd0 + 6, 1, false);
  view.setUint32(ifd0 + 10, 26, false);    // ExifIFD at tiff + 26
  const exifIfd = tiff + 26;
  view.setUint16(exifIfd, 1, false);
  view.setUint16(exifIfd + 2, 0x9003, false); // DateTimeOriginal
  view.setUint16(exifIfd + 4, 2, false);      // ASCII
  view.setUint32(exifIfd + 6, 20, false);
  view.setUint32(exifIfd + 10, 44, false);    // value at tiff + 44
  for (let i = 0; i < dateStr.length; i++) {
    bytes[tiff + 44 + i] = dateStr.charCodeAt(i);
  }

  const parsed = extractExifFromJpeg(buf);
  assert.ok(parsed);
  assert.equal(parsed.unixSeconds, Math.floor(Date.UTC(2026, 10, 22, 8, 15, 15) / 1000));
});

test("End-to-end Tier 0 -> Level 1 Register/Verify -> Level 2 NDA E-Sign -> Admin Revoke", async () => {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "twisted23-test-"));
  const dbPath = path.join(tmpDir, "store.json");
  process.env.TWISTED23_ADMIN_KEY = "test-admin-secret-23";
  process.env.TWISTED23_AUTH_SECRET = "test-auth-secret-super-long-key-123";
  process.env.TWISTED23_DEV_OUTBOX = "true";

  const store = createStore({ filePath: dbPath });
  const server = createAppServer({ store });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    // 1. Level 0 session check
    let res = await fetch(`${baseUrl}/api/session`);
    let body = await res.json();
    assert.equal(body.user.tier, 0);
    assert.equal(body.user.authenticated, false);

    // 2. Protected routes reject unauthenticated Tier 0
    res = await fetch(`${baseUrl}/api/preferences`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ favoriteOffset: "joy" }),
    });
    assert.equal(res.status, 401);

    // 3. Register for Level 1 with initials "HMF"
    res = await fetch(`${baseUrl}/api/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: "Norma Ascender",
        email: "norma@twisted23.com",
        favoriteOffset: "HMF",
      }),
    });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.equal(body.ok, true);

    // 4. Inspect Dev Outbox for emailed 6-3 Base-38 L1 password
    res = await fetch(`${baseUrl}/api/dev-outbox?email=norma@twisted23.com`);
    const outbox = await res.json();
    assert.equal(outbox.messages.length, 1);
    const l1Password = outbox.messages[0].base38Password;
    assert.equal(l1Password.length, 10, l1Password);
    assert.ok(l1Password.includes("-"), l1Password);

    // Ensure plaintext password is NOT stored in database file
    const rawDbText = await fs.readFile(dbPath, "utf8");
    const rawDb = JSON.parse(rawDbText);
    assert.equal(JSON.stringify(rawDb.credentialByIndex).includes(l1Password), false);

    // 5. Log in with emailed L1 password -> verifies email + sets session cookie
    res = await fetch(`${baseUrl}/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password: l1Password }),
    });
    assert.equal(res.status, 200);
    const cookie = res.headers.get("set-cookie").split(";")[0];
    body = await res.json();
    assert.equal(body.user.tier, 1);
    assert.equal(body.user.emailVerified, true);
    assert.equal(body.user.favoriteOffset, "hmf");

    // 6. Update favorite offset preference to "joy"
    res = await fetch(`${baseUrl}/api/preferences`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({ favoriteOffset: "joy" }),
    });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.equal(body.user.favoriteOffset, "joy");

    // 7. Sign Level 2 NDA
    res = await fetch(`${baseUrl}/api/nda/sign`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({
        legalName: "Norma Ascender",
        typedSignature: "/s/ Norma Ascender",
        companyOrRole: "Researcher",
        agreed: true,
      }),
    });
    assert.equal(res.status, 200);
    const l2Cookie = res.headers.get("set-cookie").split(";")[0];
    body = await res.json();
    assert.equal(body.user.tier, 2);
    assert.equal(body.user.ndaSigned, true);
    assert.ok(body.ndaReceipt.receiptHash);
    assert.equal(body.level2Password.length, 10);

    // 8. Admin audit check
    res = await fetch(`${baseUrl}/api/admin/audit`, {
      headers: { "x-admin-key": "test-admin-secret-23" },
    });
    assert.equal(res.status, 200);
    const audit = await res.json();
    assert.equal(audit.ndaReceipts.length, 1);
    assert.equal(audit.users[0].tier, 2);

    // 9. Admin revoke invalidates both session & login
    res = await fetch(`${baseUrl}/api/admin/revoke`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-admin-key": "test-admin-secret-23",
      },
      body: JSON.stringify({ email: "norma@twisted23.com", revoke: true }),
    });
    assert.equal(res.status, 200);

    res = await fetch(`${baseUrl}/api/session`, { headers: { Cookie: l2Cookie } });
    body = await res.json();
    assert.equal(body.user.tier, 0);

    res = await fetch(`${baseUrl}/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password: body.level2Password || l1Password }),
    });
    assert.equal(res.status, 401);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(tmpDir, { recursive: true, force: true });
  }
});
