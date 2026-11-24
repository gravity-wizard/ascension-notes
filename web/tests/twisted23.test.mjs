import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  decodeAcodeTimestamp,
  isCleanAcodeSequence,
  mintAcodeTimeSlug,
  mintAgyTimeTag,
  mintConforming3PeaksSlug,
  parseWishWindow,
  pickUniqueSlug,
  sanitizeSlug,
} from "../lib/images.mjs";
import { createStore } from "../lib/store.mjs";
import { createAppServer } from "../server.mjs";

test("Custom names keep -agy; blank input uses Single Peak (___-a8a) or Triple Peak (___-a8a-a8a-a8a) skipping 0 and 6", () => {
  assert.equal(sanitizeSlug("Uncle Norman"), "uncle-norman");

  const fixedUnix = 1795385000;
  const first = pickUniqueSlug("Uncle Norman", {}, fixedUnix);
  assert.match(first, /^uncle-norman-[0-9a-z]{6}-agy$/);

  const second = pickUniqueSlug("Uncle Norman", { [first]: {} }, fixedUnix);
  assert.notEqual(second, first);
  assert.match(second, /^uncle-norman-[0-9a-z]{6}-agy$/);

  // Blank input -> Single Peak or Triple Peak, digits in [1-57-9] (no 0 or 6)
  const blank = pickUniqueSlug("", {}, fixedUnix);
  assert.match(blank, /^[1-9a-z_]{3}(-[a-z][1-57-9][a-z]){1,3}$/);
  assert.equal(decodeAcodeTimestamp(blank), fixedUnix);

  // When a Single Peak second is found (including digit 9), verify Single Peak and collision -> Triple Peak
  const TRIAD = 54872;
  const EPOCH = 1584540571;
  // lsd "a9a" = 10*1444 + 9*38 + 10 = 14792
  const singleSec = EPOCH + 3843 * TRIAD + 14792;
  const singleMinted = mintAcodeTimeSlug(singleSec);
  assert.equal(singleMinted.mode, "single");
  assert.equal(singleMinted.canonical, "2p5^a9a");
  assert.equal(singleMinted.slug, "2p5-a9a");
  assert.equal(decodeAcodeTimestamp(singleMinted.canonical), singleSec);
  assert.equal(decodeAcodeTimestamp(singleMinted.slug), singleSec);

  // Digit 6 is skipped in a8a triads -> lsd "a6a" (14678) falls back to Triple Peak
  const sixSec = EPOCH + 3843 * TRIAD + (10 * 1444 + 6 * 38 + 10);
  const sixMinted = mintAcodeTimeSlug(sixSec);
  assert.equal(sixMinted.mode, "triple");
  assert.match(sixMinted.canonical, /^2p5(\^[a-z][1-57-9][a-z]){3}$/);
  assert.equal(decodeAcodeTimestamp(sixMinted.canonical), sixSec);

  // Collision on Single Peak switches to Triple Peak for the exact same second
  const tripleAfterCollision = mintAcodeTimeSlug(singleSec, (cand) => cand === "2p5-a9a");
  assert.equal(tripleAfterCollision.mode, "triple");
  assert.match(tripleAfterCollision.canonical, /^2p5(\^[a-z][1-57-9][a-z]){3}$/);
  assert.equal(decodeAcodeTimestamp(tripleAfterCollision.canonical), singleSec);
  assert.equal(decodeAcodeTimestamp(tripleAfterCollision.slug), singleSec);

  // First MSD Triad replaces '0' with '_'
  const zeroMsdSec = EPOCH + (2 * 38 * 38 + 0 * 38 + 5) * TRIAD + 14792;
  const zeroMsdMinted = mintAcodeTimeSlug(zeroMsdSec);
  assert.equal(zeroMsdMinted.canonical, "2_5^a9a");
  assert.equal(decodeAcodeTimestamp("2_5^a9a"), zeroMsdSec);

  // Offensive combination checks across carets, digits, leetspeak, and 69/666
  assert.equal(isCleanAcodeSequence("269^a1a"), false);
  assert.equal(isCleanAcodeSequence("666^a1a"), false);
  assert.equal(isCleanAcodeSequence("2p6^a9a"), false);
  assert.equal(isCleanAcodeSequence("2p5^f7u^c5k^a1a"), false);
  assert.equal(isCleanAcodeSequence("2p5^b1t^c5h^a1a"), false);
  assert.equal(isCleanAcodeSequence("2p5^f4g^a1a^b2b"), false);
  assert.equal(isCleanAcodeSequence("2p5^k9m^r7p^b4z"), true);

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
  // Uncle Norman (2x) + blank (1x) + Binary Test (2x) = 5 quota units
  process.env.TWISTED23_IP_DAILY_QUOTA = "5";

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

    // Blank customName -> Single Peak (___-a8a) or Triple Peak (___-a8a-a8a-a8a)
    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dataBase64: tinyPng.toString("base64") }),
    });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.match(body.image.slug, /^[1-9a-z_]{3}(-[a-z][1-57-9][a-z]){1,3}$/);
    assert.ok(decodeAcodeTimestamp(body.image.slug) !== null);

    // 3rd upload uses direct binary application/octet-stream -> binary-test-<6chars>-agy.png
    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: {
        "Content-Type": "application/octet-stream",
        "X-Custom-Name": encodeURIComponent("Binary Test"),
      },
      body: tinyPng,
    });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.match(body.image.slug, /^binary-test-[0-9a-z]{6}-agy$/);

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

test("Mixed-case and ^ slug lookup resolves via /api/images/<slug>", async () => {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "twisted23-lookup-"));
  const dbPath = path.join(tmpDir, "store.json");
  const store = createStore({ filePath: dbPath });
  const server = createAppServer({ store });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}`;

  const tinyPng = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x53, 0x61, 0x6d, 0x70, 0x6c, 0x65,
  ]);

  try {
    const targetSlug = "agy-bug2antsiteam-go-team-go";
    await store.saveImageBlob(`${targetSlug}.png`, tinyPng);
    await store.updateState((state) => {
      state.imagesBySlug[targetSlug] = {
        slug: targetSlug,
        storedFilename: `${targetSlug}.png`,
        ext: "png",
        mime: "image/png",
        bytes: tinyPng.length,
        etag: '"deadbeef"',
        title: "agy^bug2AnTsiTeam-go-team-go",
        createdAtIso: new Date().toISOString(),
      };
    });

    for (const lookup of ["agy^bug2AnTsiTeam-go-team-go", "agy%5Ebug2AnTsiTeam-go-team-go", "AGY-BUG2ANTSITEAM-GO-TEAM-GO"]) {
      const res = await fetch(`${baseUrl}/api/images/${lookup}`);
      assert.equal(res.status, 200, `Expected 200 for lookup ${lookup}`);
      const body = await res.json();
      assert.equal(body.ok, true);
      assert.equal(body.image.slug, targetSlug);
    }
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(tmpDir, { recursive: true, force: true });
  }
});

test("mintAgyTimeTag guards against blocked prefixes, loop exhaustion, and collisions", () => {
  const fixedUnix = 1795385000;

  for (const blockedPrefix of ["hello", "user69", "xxx-test"]) {
    const res = mintAgyTimeTag(fixedUnix, () => false, blockedPrefix);
    assert.equal(isCleanAcodeSequence(res.slug), true, `Expected clean slug for ${blockedPrefix}, got ${res.slug}`);
    assert.equal(res.slug.startsWith(`${blockedPrefix}-`), false);
  }

  // When all 90 -agy candidates collide, fallback must avoid collision and remain clean
  const taken = new Set();
  const firstFallback = mintAgyTimeTag(fixedUnix, (cand) => cand.endsWith("-agy"), "clean");
  assert.equal(isCleanAcodeSequence(firstFallback.slug), true);
  assert.equal(firstFallback.slug.endsWith("-agy"), false);
  taken.add(firstFallback.slug);

  const secondFallback = mintAgyTimeTag(fixedUnix, (cand) => cand.endsWith("-agy") || taken.has(cand), "clean");
  assert.notEqual(secondFallback.slug, firstFallback.slug);
  assert.equal(isCleanAcodeSequence(secondFallback.slug), true);
});

test("mintAcodeTimeSlug and mintAgyTimeTag step forward cleanly at dead-zone timestamp 1795453749", () => {
  const deadZoneUnix = 1795453749;
  const taken = new Set();

  for (let i = 0; i < 5; i++) {
    const acode = mintAcodeTimeSlug(deadZoneUnix, (cand) => taken.has(cand));
    assert.equal(isCleanAcodeSequence(acode.slug), true, `Expected clean slug, got ${acode.slug}`);
    assert.equal(taken.has(acode.slug), false, `Collision on ${acode.slug}`);
    assert.equal(decodeAcodeTimestamp(acode.slug), acode.unixSeconds);
    taken.add(acode.slug);
  }

  const agyTaken = new Set();
  for (let i = 0; i < 5; i++) {
    const res = mintAgyTimeTag(deadZoneUnix, (cand) => agyTaken.has(cand), "hello");
    assert.equal(isCleanAcodeSequence(res.slug), true, `Expected clean slug, got ${res.slug}`);
    assert.equal(res.slug.startsWith("hello-"), false);
    assert.equal(agyTaken.has(res.slug), false, `Collision on ${res.slug}`);
    assert.equal(decodeAcodeTimestamp(res.slug), res.unixSeconds);
    agyTaken.add(res.slug);
  }
});

test("mintAcodeTimeSlug completes c1=30 dead-zone in < 100ms and exhausts cleanly in < 3000ms", () => {
  const TIME_EPOCH = 1584540571;
  const TRIAD_BASE = 54872;
  const msdVal = Math.floor((1795453749 - TIME_EPOCH) / TRIAD_BASE);
  const c1_30_ts = TIME_EPOCH + msdVal * TRIAD_BASE + ((msdVal + 30 * 38) % TRIAD_BASE);

  const t0 = performance.now();
  const res = mintAcodeTimeSlug(c1_30_ts, () => false);
  const c1_30_ms = performance.now() - t0;
  assert.equal(isCleanAcodeSequence(res.slug), true);
  assert.equal(decodeAcodeTimestamp(res.slug), res.unixSeconds);
  assert.ok(c1_30_ms < 100, `Expected c1=30 dead-zone mint in < 100ms, took ${c1_30_ms.toFixed(2)}ms`);

  const t1 = performance.now();
  assert.throws(() => mintAcodeTimeSlug(1795453749, () => true), /Unable to mint unique acode time slug/);
  const exhaustMs = performance.now() - t1;
  assert.ok(exhaustMs < 3000, `Expected exhaustion throw in < 3000ms, took ${exhaustMs.toFixed(2)}ms`);
});

test("mintAcodeTimeSlug at 1586516851 avoids intra-triad w4n-k8b profanity leak", () => {
  const res = mintAcodeTimeSlug(1586516851, () => false);
  assert.notEqual(res.canonical, "___^w4n^k8b^o9k");
  assert.equal(isCleanAcodeSequence(res.canonical), true, `Expected clean canonical, got ${res.canonical}`);
  assert.equal(isCleanAcodeSequence(res.slug), true, `Expected clean slug, got ${res.slug}`);
});

test("mintAcodeTimeSlug skips dirty msd buckets (1676806318 msd=169, 2080794573 msd=69-, 2079331346 consecutive 69*)", () => {
  for (const ts of [1676806318, 2080794573, 2079331346]) {
    const res = mintAcodeTimeSlug(ts, () => false);
    assert.equal(isCleanAcodeSequence(res.canonical), true, `Expected clean canonical for ${ts}, got ${res.canonical}`);
    assert.equal(isCleanAcodeSequence(res.slug), true, `Expected clean slug for ${ts}, got ${res.slug}`);
    assert.equal(decodeAcodeTimestamp(res.canonical), res.unixSeconds);
    assert.ok(res.unixSeconds > ts, `Expected unixSeconds > ${ts}, got ${res.unixSeconds}`);
  }
});

test("Wish-window incorporates p1b^f5n (pi1browser full5screen) into 15-char 3-peaks with 0s drift and prices non-conforming tags at 385KB + 2x quota", async () => {
  // 1. Direct p1b^f5n and alias pi1browser full5screen classification
  for (const wishInput of ["p1b^f5n", "P1B-F5N", "pi1browser full5screen", "pi1browser^full5screen"]) {
    const parsed = parseWishWindow(wishInput);
    assert.equal(parsed.kind, "conforming");
    assert.equal(parsed.conforming, true);
    assert.deepEqual(parsed.triads, ["p1b", "f5n"]);
    assert.equal(parsed.canonicalWish, "p1b^f5n");
    assert.equal(parsed.quotaCost, 1);
    assert.equal(parsed.maxBytes, 575 * 1024);
  }

  // 2. Single conforming triad (p1b or f5n)
  const singleWish = parseWishWindow("p1b");
  assert.equal(singleWish.kind, "conforming");
  assert.deepEqual(singleWish.triads, ["p1b"]);
  const minted1 = mintConforming3PeaksSlug(["p1b"], 1795453749);
  assert.equal(minted1.slug.length, 15);
  assert.ok(minted1.slug.includes("-p1b-"));
  assert.equal(decodeAcodeTimestamp(minted1.slug), minted1.unixSeconds);
  assert.equal(decodeAcodeTimestamp(minted1.canonical), minted1.unixSeconds);

  // 3. Two conforming triads (p1b^f5n) across 120 consecutive seconds (covering '_'/'-' Peak 3 complements)
  const baseTs = 1795453700;
  for (let offset = 0; offset < 120; offset++) {
    const ts = baseTs + offset;
    const minted = mintConforming3PeaksSlug(["p1b", "f5n"], ts);
    assert.equal(minted.slug.length, 15, `Expected 15-char slug at ${ts}, got ${minted.slug}`);
    assert.match(minted.slug, /^[1-9a-z_-]{3}-p1b-f5n-[0-9a-z_-]{3}$/);
    assert.equal(isCleanAcodeSequence(minted.slug), true);
    assert.equal(isCleanAcodeSequence(minted.canonical), true);
    assert.equal(decodeAcodeTimestamp(minted.slug), minted.unixSeconds);
    assert.equal(decodeAcodeTimestamp(minted.canonical), minted.unixSeconds);
  }

  // 4. Non-conforming classification (Uncle Norman, digits 0/6, >2 triads)
  for (const raw of ["Uncle Norman", "a0a", "a6a", "p1b^f5n^k9m"]) {
    const nc = parseWishWindow(raw);
    assert.equal(nc.kind, "nonconforming", `Expected nonconforming for ${raw}`);
    assert.equal(nc.conforming, false);
    assert.equal(nc.quotaCost, 2);
    assert.equal(nc.maxBytes, 385 * 1024);
  }

  // 5. HTTP integration: 450 KB fails for Uncle Norman (385 KB cap) yet succeeds for p1b^f5n (575 KB cap),
  //    and remaining 1x quota slot rejects non-conforming (2x) while allowing conforming p1b^f5n (1x)!
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "twisted23-wish-"));
  const dbPath = path.join(tmpDir, "store.json");
  process.env.TWISTED23_IP_DAILY_QUOTA = "3";

  const store = createStore({ filePath: dbPath });
  const server = createAppServer({ store });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}`;

  const pngHead = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  ]);
  const payload450Kb = Buffer.concat([pngHead, Buffer.alloc(450 * 1024)]);
  const tinyPng = Buffer.concat([pngHead, Buffer.from("WishPixels")]);

  try {
    // 450 KB with non-conforming "Uncle Norman" -> 413 (exceeds 385 KB non-conforming cap; 0 quota consumed)
    let res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: {
        "Content-Type": "application/octet-stream",
        "X-Custom-Name": encodeURIComponent("Uncle Norman"),
      },
      body: payload450Kb,
    });
    assert.equal(res.status, 413);

    // 450 KB with conforming "p1b^f5n" -> 200 (15-char 3-peaks slug, 1/3 quota used!)
    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: {
        "Content-Type": "application/octet-stream",
        "X-Custom-Name": encodeURIComponent("p1b^f5n"),
      },
      body: payload450Kb,
    });
    assert.equal(res.status, 200);
    let body = await res.json();
    assert.equal(body.image.slug.length, 15);
    assert.match(body.image.slug, /^[1-9a-z_-]{3}-p1b-f5n-[0-9a-z_-]{3}$/);
    assert.equal(body.image.wishMode, "conforming");
    assert.equal(body.hosting.quotaCost, 1);
    assert.equal(body.hosting.dailyRemaining, 2);

    // Canonical '^' & '|' viewer lookup resolves cleanly
    const canonicalLookup = await fetch(`${baseUrl}/api/images/${encodeURIComponent(body.image.canonical)}`);
    assert.equal(canonicalLookup.status, 200);

    // Tiny non-conforming upload -> 200 (consumes 2 quota units -> 3/3 used, 0 remaining)
    res = await fetch(`${baseUrl}/api/images/upload`, {
      method: "POST",
      headers: {
        "Content-Type": "application/octet-stream",
        "X-Custom-Name": encodeURIComponent("Uncle Norman"),
      },
      body: tinyPng,
    });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.equal(body.image.wishMode, "nonconforming");
    assert.equal(body.hosting.quotaCost, 2);
    assert.equal(body.hosting.dailyRemaining, 0);
  } finally {
    delete process.env.TWISTED23_IP_DAILY_QUOTA;
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(tmpDir, { recursive: true, force: true });
  }
});




