import { compressDataUrlToBudget } from "./compressor.js";

let maxImageBytes = 575 * 1024;
let stagedFile = null; // { file, dataUrl, originalName, originalBytes, mime }
let usePhpRouteFallback = false;

const dropzone = document.getElementById("dropzone");
const fileInput = document.getElementById("file-input");
const stagingArea = document.getElementById("staging-area");
const stagedImg = document.getElementById("staged-img");
const customNameInput = document.getElementById("custom-name");
const stagingMeta = document.getElementById("staging-meta");
const uploadStatus = document.getElementById("upload-status");
const btnUpload = document.getElementById("btn-upload");
const btnSaveLocal = document.getElementById("btn-save-local");
const btnClear = document.getElementById("btn-clear");
const resultsCard = document.getElementById("results-card");
const uploadCard = document.getElementById("upload-card");

function folderBaseUrl() {
  const u = new URL(window.location.href);
  u.search = "";
  u.hash = "";
  if (!u.pathname.endsWith("/") && !u.pathname.split("/").pop().includes(".")) {
    u.pathname += "/";
  } else if (u.pathname.split("/").pop().includes(".")) {
    u.pathname = u.pathname.replace(/[^/]+$/, "");
  }
  return u.toString();
}

function apiEndpoint(route) {
  const cleanRoute = route.replace(/^\/+/, "");
  const base = folderBaseUrl();
  if (usePhpRouteFallback) {
    return `${base}api.php?route=${encodeURIComponent(cleanRoute)}`;
  }
  return `${base}api/${cleanRoute}`;
}

function formatKb(bytes) {
  return `${(bytes / 1024).toFixed(1)} KB`;
}

function encodeCompactVal(n) {
  const alpha = "0123456789abcdefghijklmnopqrstuvwxyz|^";
  let v = Math.max(0, Math.trunc(n));
  if (v === 0) return "0";
  let out = "";
  while (v > 0) {
    out = alpha[v % 38] + out;
    v = Math.floor(v / 38);
  }
  return out;
}

function decodeCompactVal(s) {
  const alpha = "0123456789abcdefghijklmnopqrstuvwxyz|^";
  let total = 0;
  for (const ch of s) {
    const idx = alpha.indexOf(ch === "_" ? "0" : ch === "-" ? "^" : ch);
    if (idx < 0) return 0;
    total = total * 38 + idx;
  }
  return total;
}

function a8aFromIdx(idx) {
  const count = 5408;
  const i = ((idx % count) + count) % count;
  const c0 = String.fromCharCode(97 + Math.floor(i / 208));
  const rem = i % 208;
  const c1 = String.fromCharCode(49 + Math.floor(rem / 26));
  const c2 = String.fromCharCode(97 + (rem % 26));
  return `${c0}${c1}${c2}`;
}

function buildAcodeTimeSlug() {
  const epoch = 1584540571;
  const triadBase = 54872;
  const a8aCount = 5408;
  const sec = Math.max(epoch, Math.floor(Date.now() / 1000));
  const elapsed = sec - epoch;
  const msdVal = Math.floor(elapsed / triadBase);
  const lsdVal = elapsed % triadBase;
  const msd = encodeCompactVal(msdVal).padStart(3, "0").slice(-3).replace(/0/g, "_").replace(/\|/g, "_").replace(/\^/g, "-");

  const direct = encodeCompactVal(lsdVal);
  if (/^[a-z][1-8][a-z]$/.test(direct) && !direct.includes("666")) {
    return `${msd}-${direct}`;
  }

  for (let attempt = 0; attempt < 5000; attempt++) {
    const h1 = (Math.imul(elapsed ^ 0x9e3779b9, 2654435761) ^ Math.imul(attempt + 1, 2246822519)) >>> 0;
    const h2 = (Math.imul(elapsed ^ 0x85ebca6b, 3266489917) ^ Math.imul(attempt + 1, 668265263)) >>> 0;
    const t1 = a8aFromIdx(h1 % a8aCount);
    const t2 = a8aFromIdx(h2 % a8aCount);
    const needed = (((lsdVal - msdVal - decodeCompactVal(t1) - decodeCompactVal(t2)) % triadBase) + triadBase) % triadBase;
    const t3 = encodeCompactVal(needed);
    if (/^[a-z][1-8][a-z]$/.test(t3)) {
      return `${msd}-${t1}-${t2}-${t3}`;
    }
  }
  return `${msd}-a1a-a1a-a1a`;
}

function buildAgyTimeTag() {
  const epoch = 1584540571;
  const agyOffset = 15082;
  const baseSec = Math.max(epoch, Math.floor(Date.now() / 1000));
  for (let bump = 0; bump < 60; bump++) {
    const out = encodeCompactVal((baseSec + bump) - epoch + agyOffset);
    if (/^[0-9a-z]+$/.test(out) && !out.includes("666")) {
      return `${out}-agy`;
    }
  }
  return "now-agy";
}

function sanitizeLocalFilename(raw, ext) {
  const clean = String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
  if (!clean) {
    return `${buildAcodeTimeSlug()}.${ext}`;
  }
  return `${clean}-${buildAgyTimeTag()}.${ext}`;
}

async function fetchConfig() {
  for (const usePhp of [false, true]) {
    usePhpRouteFallback = usePhp;
    const url = apiEndpoint("health");
    try {
      const res = await fetch(url, { cache: "no-store" });
      if (!res.ok) continue;
      const data = await res.json();
      if (data?.ok) {
        if (data.maxImageBytes) {
          maxImageBytes = Number(data.maxImageBytes) || maxImageBytes;
          document.getElementById("limit-note").textContent =
            `JPG, PNG, WebP, GIF · ${Math.round(maxImageBytes / 1024)} KB max`;
        }
        return;
      }
    } catch {
      // Try next route form
    }
  }
  usePhpRouteFallback = false;
}

function stageFile(file) {
  if (!file || !file.type.startsWith("image/")) return;
  const reader = new FileReader();
  reader.onload = () => {
    stagedFile = {
      file,
      dataUrl: String(reader.result || ""),
      originalName: file.name || "image.png",
      originalBytes: file.size || 0,
      mime: file.type || "image/png",
    };
    stagedImg.src = stagedFile.dataUrl;
    stagingMeta.textContent = `${stagedFile.originalName} (${formatKb(stagedFile.originalBytes)})`;
    uploadStatus.textContent = "";
    uploadStatus.className = "status-line";
    stagingArea.classList.remove("hidden");
    resultsCard.classList.add("hidden");
  };
  reader.readAsDataURL(file);
}

function showResults(imageRecord) {
  uploadCard.classList.add("hidden");
  resultsCard.classList.remove("hidden");
  document.getElementById("result-img").src = imageRecord.snippets.directUrl;
  document.getElementById("result-title").textContent = imageRecord.storedFilename;
  document.getElementById("result-size").textContent =
    `${formatKb(imageRecord.bytes)} · ${imageRecord.ext.toUpperCase()}`;

  document.getElementById("out-direct").value = imageRecord.snippets.directUrl;
  document.getElementById("out-viewer").value = imageRecord.snippets.viewerUrl;
  document.getElementById("out-html").value = imageRecord.snippets.html;
  document.getElementById("out-html-linked").value = imageRecord.snippets.htmlLinked;
  document.getElementById("out-bbcode").value = imageRecord.snippets.bbcodeLinked;
  document.getElementById("out-markdown").value = imageRecord.snippets.markdown;
}

async function prepareBytesForUpload() {
  if (!stagedFile) return null;
  if (
    stagedFile.originalBytes > 0 &&
    stagedFile.originalBytes <= maxImageBytes &&
    /^image\/(png|jpeg|webp|gif)$/.test(stagedFile.mime)
  ) {
    return {
      blob: stagedFile.file,
      bytes: stagedFile.originalBytes,
      ext: stagedFile.mime === "image/jpeg" ? "jpg" : stagedFile.mime.split("/")[1],
      dataUrl: stagedFile.dataUrl,
    };
  }
  const compressed = await compressDataUrlToBudget(stagedFile.dataUrl, { maxBytes: maxImageBytes });
  return {
    blob: compressed.blob,
    bytes: compressed.bytes,
    ext: compressed.mime === "image/jpeg" ? "jpg" : "webp",
    dataUrl: `data:${compressed.mime};base64,${compressed.dataBase64}`,
  };
}

dropzone.addEventListener("click", () => fileInput.click());
dropzone.addEventListener("keydown", (e) => {
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    fileInput.click();
  }
});
dropzone.addEventListener("dragover", (e) => {
  e.preventDefault();
  dropzone.classList.add("dragover");
});
dropzone.addEventListener("dragleave", () => dropzone.classList.remove("dragover"));
dropzone.addEventListener("drop", (e) => {
  e.preventDefault();
  dropzone.classList.remove("dragover");
  const f = e.dataTransfer?.files?.[0];
  if (f) stageFile(f);
});
fileInput.addEventListener("change", (e) => {
  const f = e.target.files?.[0];
  if (f) stageFile(f);
});

window.addEventListener("paste", (e) => {
  const items = Array.from(e.clipboardData?.items || []);
  const imgItem = items.find((it) => it.type.startsWith("image/"));
  if (imgItem) {
    const f = imgItem.getAsFile();
    if (f) stageFile(f);
  }
});

btnClear.addEventListener("click", () => {
  stagedFile = null;
  fileInput.value = "";
  customNameInput.value = "";
  stagingArea.classList.add("hidden");
  uploadStatus.textContent = "";
  document.querySelector(".container")?.classList.remove("is-expanded");
});

btnSaveLocal.addEventListener("click", async () => {
  if (!stagedFile) return;
  try {
    btnSaveLocal.disabled = true;
    const prepared = await prepareBytesForUpload();
    const a = document.createElement("a");
    a.href = prepared.dataUrl;
    a.download = sanitizeLocalFilename(customNameInput.value.trim(), prepared.ext);
    a.click();
    uploadStatus.textContent = `Saved locally (${formatKb(prepared.bytes)}).`;
    uploadStatus.className = "status-line";
  } catch (err) {
    uploadStatus.textContent = err.message;
    uploadStatus.className = "status-line error";
  } finally {
    btnSaveLocal.disabled = false;
  }
});

btnUpload.addEventListener("click", async () => {
  if (!stagedFile) return;
  btnUpload.disabled = true;
  uploadStatus.className = "status-line";
  let targetUrl = apiEndpoint("images/upload");
  try {
    uploadStatus.textContent = "Preparing image...";
    const prepared = await prepareBytesForUpload();
    uploadStatus.textContent = `Uploading ${formatKb(prepared.bytes)}...`;

    let res = await fetch(targetUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/octet-stream",
        "X-Custom-Name": encodeURIComponent(customNameInput.value.trim()),
      },
      body: prepared.blob,
    });
    if ((res.status === 404 || res.status === 405) && !usePhpRouteFallback) {
      usePhpRouteFallback = true;
      targetUrl = apiEndpoint("images/upload");
      res = await fetch(targetUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/octet-stream",
          "X-Custom-Name": encodeURIComponent(customNameInput.value.trim()),
        },
        body: prepared.blob,
      });
    }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(data.error || `Upload failed (${res.status}) at ${targetUrl}`);
    }
    showResults(data.image);
    const url = new URL(window.location.href);
    url.searchParams.set("img", data.image.slug);
    window.history.replaceState({}, "", url.toString());
  } catch (err) {
    const msg = err?.message || "Network error";
    uploadStatus.textContent = msg.includes(targetUrl) ? msg : `Failed to fetch ${folderBaseUrl()} (${msg})`;
    uploadStatus.className = "status-line error";
  } finally {
    btnUpload.disabled = false;
  }
});

document.getElementById("btn-upload-another").addEventListener("click", () => {
  stagedFile = null;
  fileInput.value = "";
  customNameInput.value = "";
  stagingArea.classList.add("hidden");
  resultsCard.classList.add("hidden");
  uploadCard.classList.remove("hidden");
  document.querySelector(".container")?.classList.remove("is-expanded");
  const url = new URL(window.location.href);
  url.searchParams.delete("img");
  window.history.replaceState({}, "", url.toString());
});

document.querySelectorAll(".copy-btn").forEach((btn) => {
  btn.addEventListener("click", async () => {
    const input = document.getElementById(btn.dataset.target);
    if (!input) return;
    await navigator.clipboard?.writeText(input.value).catch(() => {});
    const old = btn.textContent;
    btn.textContent = "Copied";
    setTimeout(() => {
      btn.textContent = old;
    }, 1200);
  });
});

async function loadExistingIfQueryParam() {
  const slug = new URLSearchParams(window.location.search).get("img");
  if (!slug) return;
  try {
    const res = await fetch(apiEndpoint(`images/${encodeURIComponent(slug)}`));
    if (!res.ok) return;
    const data = await res.json();
    if (data?.image) {
      showResults(data.image);
    }
  } catch {
    // Ignore offline/missing viewer lookup
  }
}

fetchConfig().then(() => loadExistingIfQueryParam());
