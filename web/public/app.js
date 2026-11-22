import { compressDataUrlToBudget } from "./compressor.js";

let maxImageBytes = 575 * 1024;
let stagedFile = null; // { dataUrl, originalName, originalBytes }

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

function formatKb(bytes) {
  return `${(bytes / 1024).toFixed(1)} KB`;
}

function sanitizeLocalFilename(raw, ext) {
  const clean = String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${clean || "image"}.${ext}`;
}

async function fetchConfig() {
  try {
    const res = await fetch("api/health");
    const data = await res.json();
    if (data?.maxImageBytes) {
      maxImageBytes = Number(data.maxImageBytes) || maxImageBytes;
      document.getElementById("limit-note").textContent =
        `JPG, PNG, WebP, GIF · ${Math.round(maxImageBytes / 1024)} KB max`;
    }
  } catch {
    // Keep default 575 KB UI hint
  }
}

function stageFile(file) {
  if (!file || !file.type.startsWith("image/")) return;
  const reader = new FileReader();
  reader.onload = () => {
    stagedFile = {
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
    const base64 = stagedFile.dataUrl.includes(",")
      ? stagedFile.dataUrl.split(",", 2)[1]
      : stagedFile.dataUrl;
    return {
      dataBase64: base64,
      bytes: stagedFile.originalBytes,
      ext: stagedFile.mime === "image/jpeg" ? "jpg" : stagedFile.mime.split("/")[1],
      dataUrl: stagedFile.dataUrl,
    };
  }
  const compressed = await compressDataUrlToBudget(stagedFile.dataUrl, { maxBytes: maxImageBytes });
  return {
    dataBase64: compressed.dataBase64,
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
});

btnSaveLocal.addEventListener("click", async () => {
  if (!stagedFile) return;
  try {
    btnSaveLocal.disabled = true;
    const prepared = await prepareBytesForUpload();
    const a = document.createElement("a");
    a.href = prepared.dataUrl;
    a.download = sanitizeLocalFilename(customNameInput.value || stagedFile.originalName.replace(/\.[^.]+$/, ""), prepared.ext);
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
  try {
    uploadStatus.textContent = "Preparing image...";
    const prepared = await prepareBytesForUpload();
    uploadStatus.textContent = `Uploading ${formatKb(prepared.bytes)}...`;

    const res = await fetch("api/images/upload", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        dataBase64: prepared.dataBase64,
        customName: customNameInput.value.trim(),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(data.error || `Upload failed (${res.status})`);
    }
    showResults(data.image);
    const url = new URL(window.location.href);
    url.searchParams.set("img", data.image.slug);
    window.history.replaceState({}, "", url.toString());
  } catch (err) {
    uploadStatus.textContent = err.message;
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
    const res = await fetch(`api/images/${encodeURIComponent(slug)}`);
    if (!res.ok) return;
    const data = await res.json();
    if (data?.image) {
      showResults(data.image);
    }
  } catch {
    // Ignore missing/offline viewer lookup
  }
}

fetchConfig();
loadExistingIfQueryParam();
