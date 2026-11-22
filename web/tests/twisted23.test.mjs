import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { mintAgyTimeTag, pickUniqueSlug, sanitizeSlug } from "../lib/images.mjs";
import { createStore } from "../lib/store.mjs";
import { createAppServer } from "../server.mjs";

test("Slug sanitizer appends exact time ending in -agy for custom and blank names", () => {
  assert.equal(sanitizeSlug("Uncle Norman"), "uncle-norman");

  const fixedUnix = 1795385000;
  const first = pickUniqueSlug("Uncle Norman", {}, fixedUnix);
  assert.match(first, /^uncle-norman-[0-9a-z]{6}-agy$/);

  const second = pickUniqueSlug("Uncle Norman", { [first]: {} }, fixedUnix);
  assert.notEqual(second, first);
  assert.match(second, /^uncle-norman-[0-9a-z]{6}-agy$/);

  const blank = pickUniqueSlug("", {}, fixedUnix);
  assert.match(blank, /^[0-9a-z]{6}-agy$/);
  assert.equal(blank.length, 10);

  const tag = mintAgyTimeTag(fixedUnix);
  assert.ok(tag.tag.endsWith("-agy"));
});

test("Public UI contains zero references to NDA, Levels, or Base38", async () => {
  const html = await fs.readFile(new URL("../public/index.html", import.meta.url), "utf8");
  const js = await fs.readFile(new URL("../public/app.js", import.meta.url), "utf8");
  for (const text of [html, js]) {
    assert.equal(/\bnda\b/i.test(text), false);
    assert.equal(/\blevel\s*[012]\b/i.test(text), false);
    assert.equal(/base[- ]?38/i.test(text), false);
  }
});

test("Minimal ImgBB flow: custom/short -agy filenames, 575KB limit, cache headers, and IP quota", async () => {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "twisted23-agy-"));
  const dbPath = path.join(tmpDir, "store.json");
  process.env.TWISTED23_IP_DAILY_QUOTA = "3";

  const store = createStore({ filePath: dbPath });
  const server = createAppServer({ store });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}`;

  const validPngHead = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  ]);

  try {
    let res = await fetch(`${baseUrl}/api/health`);
    let body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.maxImageBytes, 575 * 1024);

    // Reject non-image bytes (400) and > 575 KB payload (413)
    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dataBase64: Buffer.from("plain text").toString("base64") }),
    });
    assert.equal(res.status, 400);
    assert.equal(res.headers.get("cloudflare-cdn-cache-control"), "no-store");

    const oversized = Buffer.concat([validPngHead, Buffer.alloc(576 * 1024)]);
    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dataBase64: oversized.toString("base64") }),
    });
    assert.equal(res.status, 413);

    // Upload with custom name "Uncle Norman" -> uncle-norman-<6chars>-agy.png
    const tinyPng = Buffer.concat([validPngHead, Buffer.from("SamplePixels1")]);
    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        dataBase64: tinyPng.toString("base64"),
        customName: "Uncle Norman",
      }),
    });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.match(body.image.slug, /^uncle-norman-[0-9a-z]{6}-agy$/);
    assert.match(body.image.storedFilename, /^uncle-norman-[0-9a-z]{6}-agy\.png$/);
    assert.ok(body.image.snippets.directUrl.includes(`/i/${body.image.storedFilename}`));
    assert.ok(body.image.snippets.html.includes("<img src="));
    assert.ok(body.image.snippets.bbcodeLinked.includes("[url="));
    assert.ok(body.image.snippets.markdown.startsWith("!["));

    // Serve hosted file with immutable cache + 304 ETag
    const imgPath = new URL(body.image.snippets.directUrl).pathname;
    const imgRes = await fetch(`${baseUrl}${imgPath}`);
    assert.equal(imgRes.status, 200);
    assert.equal(imgRes.headers.get("cloudflare-cdn-cache-control"), "public, max-age=31536000, immutable");
    const etag = imgRes.headers.get("etag");
    assert.ok(etag);
    const notMod = await fetch(`${baseUrl}${imgPath}`, {
      headers: { "If-None-Match": etag },
    });
    assert.equal(notMod.status, 304);

    // Blank customName -> <6chars>-agy.png
    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dataBase64: tinyPng.toString("base64") }),
    });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.match(body.image.slug, /^[0-9a-z]{6}-agy$/);

    // 3rd upload succeeds, 4th hits IP quota (429)
    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dataBase64: tinyPng.toString("base64") }),
    });
    assert.equal(res.status, 200);

    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dataBase64: tinyPng.toString("base64") }),
    });
    assert.equal(res.status, 429);
  } finally {
    delete process.env.TWISTED23_IP_DAILY_QUOTA;
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(tmpDir, { recursive: true, force: true });
  }
});
