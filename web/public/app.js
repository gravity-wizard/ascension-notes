import {
  cleanExactClockExpression,
  decodeClockExpression,
  decodeJesusClock,
  sanitizeFavorite3LetterOffset,
} from "/lib/base38.mjs";
import { inspectImageFile } from "/exif.js";

function renderSampleCanvasDataUrl(title, accentA, accentB, glyph) {
  const canvas = document.createElement("canvas");
  canvas.width = 640;
  canvas.height = 480;
  const ctx = canvas.getContext("2d");
  const grad = ctx.createLinearGradient(0, 0, 640, 480);
  grad.addColorStop(0, accentA);
  grad.addColorStop(1, accentB);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, 640, 480);

  ctx.fillStyle = "rgba(255,255,255,0.12)";
  ctx.beginPath();
  ctx.arc(490, 110, 95, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = "rgba(255,255,255,0.92)";
  ctx.font = "bold 76px sans-serif";
  ctx.fillText(glyph, 48, 150);

  ctx.font = "bold 30px sans-serif";
  ctx.fillText(title, 48, 375);

  ctx.fillStyle = "rgba(255,255,255,0.75)";
  ctx.font = "18px monospace";
  ctx.fillText("Twisted23.com · Base-38 Sample Photo", 48, 415);
  return canvas.toDataURL("image/png");
}

const SAMPLES = [
  {
    id: "willow",
    originalName: "IMG_8412.JPG",
    subject: "Weeping WilLoW Tree",
    unixSeconds: decodeJesusClock("2p41w4"),
    timestampSource: "Sample EXIF",
    dataUrl: null,
    art: ["🌳", "#134e4a", "#0f172a"],
  },
  {
    id: "gym",
    originalName: "Screenshot 2026-11-22.png",
    subject: "Air Derby Gym",
    unixSeconds: decodeJesusClock("2p7666"),
    timestampSource: "Blocked 666 Demo",
    dataUrl: null,
    art: ["🏀", "#7c2d12", "#1e1b4b"],
  },
  {
    id: "eagle",
    originalName: "DSC_0194.JPG",
    subject: "Golden Eagle Dawn",
    unixSeconds: decodeJesusClock("2p7|^a"),
    timestampSource: "Symbol |/^ Escape Demo",
    dataUrl: null,
    art: ["🦅", "#78350f", "#1e3a8a"],
  },
  {
    id: "capture",
    originalName: "Screenshot 2026-11-22 at 8.15.15 AM.png",
    subject: "",
    unixSeconds: decodeJesusClock("2p41w2"),
    timestampSource: "Stage 1 Raw Capture",
    dataUrl: null,
    art: ["📸", "#1e293b", "#090d16"],
  },
];

let currentUser = { authenticated: false, tier: 0, favoriteOffset: "" };
let devOutboxAvailable = false;
let selectedPhoto = null;
let batchItems = [];
let toastTimer = null;

function showToast(msg) {
  const el = document.getElementById("toast");
  el.textContent = msg;
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), 4200);
}

async function api(url, opts = {}) {
  const res = await fetch(url, {
    credentials: "include",
    headers: { "Content-Type": "application/json", ...(opts.headers || {}) },
    ...opts,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.error || `Request failed (${res.status})`);
  }
  return data;
}

function openModal(id) {
  document.getElementById(id).classList.add("open");
}

function closeModal(id) {
  document.getElementById(id).classList.remove("open");
}

function computePhotoNaming(photo) {
  const subject = (document.getElementById("subject-input").value || "").trim();
  const offsetRaw = (document.getElementById("offset-input").value || "").trim();
  const fav = sanitizeFavorite3LetterOffset(offsetRaw);
  const contextWords = subject ? subject.split(/[^a-zA-Z0-9]+/).filter(Boolean) : [];
  const res = cleanExactClockExpression({
    unixSeconds: photo.unixSeconds,
    contextWords,
    maxLength: 17,
    alwaysUseDifferenceFormula: true,
    favoriteOffset: fav,
  });
  const filename = subject ? `${subject} ${res.expression}.png` : `${res.expression}.png`;
  return { ...res, filename };
}

function renderSelectedPhoto() {
  if (!selectedPhoto) return;
  document.getElementById("preview-img").src = selectedPhoto.dataUrl;
  const named = computePhotoNaming(selectedPhoto);
  document.getElementById("output-filename").textContent = named.filename;
  document.getElementById("output-tag").textContent = named.expression;
  document.getElementById("output-msd").textContent = named.preservedMSDPrefix || "—";
  document.getElementById("output-source").textContent = selectedPhoto.timestampSource;
  const exactOk = decodeClockExpression(named.expression) === selectedPhoto.unixSeconds;
  document.getElementById("output-exact").textContent = exactOk ? "✓ exact ±0s" : "approx";

  const activeOffset = sanitizeFavorite3LetterOffset(document.getElementById("offset-input").value) || "";
  document.querySelectorAll("#offset-chips .chip-btn[data-offset]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.offset === activeOffset);
  });
}

function renderSampleList() {
  const list = document.getElementById("sample-list");
  list.innerHTML = "";
  for (const s of SAMPLES) {
    if (!s.dataUrl) {
      s.dataUrl = renderSampleCanvasDataUrl(s.subject || "Raw Screenshot", s.art[1], s.art[2], s.art[0]);
    }
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = `sample-item ${selectedPhoto?.id === s.id ? "selected" : ""}`;
    btn.innerHTML = `
      <img class="sample-thumb" src="${s.dataUrl}" alt="" />
      <div>
        <div style="font-size: 13px; font-weight: 600;">${s.subject || s.originalName}</div>
        <div style="font-size: 11px; color: var(--muted); font-family: var(--mono);">${s.timestampSource}</div>
      </div>
    `;
    btn.addEventListener("click", () => selectPhoto(s));
    list.appendChild(btn);
  }
}

function selectPhoto(photo) {
  selectedPhoto = photo;
  document.getElementById("subject-input").value = photo.subject || "";
  renderSampleList();
  renderSelectedPhoto();
}

function renderBatchTable() {
  const table = document.getElementById("batch-table");
  const tbody = document.getElementById("batch-tbody");
  if (currentUser.tier < 2 || batchItems.length === 0) {
    table.classList.add("hidden");
    tbody.innerHTML = "";
    return;
  }
  table.classList.remove("hidden");
  tbody.innerHTML = "";
  const offsetRaw = (document.getElementById("offset-input").value || "").trim();
  const fav = sanitizeFavorite3LetterOffset(offsetRaw);

  for (const item of batchItems) {
    const words = item.subject ? item.subject.split(/[^a-zA-Z0-9]+/).filter(Boolean) : [];
    const res = cleanExactClockExpression({
      unixSeconds: item.unixSeconds,
      contextWords: words,
      maxLength: 17,
      alwaysUseDifferenceFormula: true,
      favoriteOffset: fav,
    });
    const finalName = item.subject ? `${item.subject} ${res.expression}.png` : `${res.expression}.png`;
    item.computedTag = res.expression;
    item.computedFilename = finalName;

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${escapeHtml(item.originalName)}</td>
      <td>${escapeHtml(item.timestampSource)}</td>
      <td><code>${escapeHtml(res.expression)}</code></td>
      <td><code>${escapeHtml(finalName)}</code></td>
    `;
    tbody.appendChild(tr);
  }
}

function syncAuthUi() {
  const tier = currentUser?.tier || 0;
  const pill = document.getElementById("user-tier-pill");
  pill.className = `pill tier-${tier}`;
  pill.textContent =
    tier >= 2
      ? `Level 2 · ${currentUser.name} (NDA Signed)`
      : tier === 1
      ? `Level 1 · ${currentUser.name}`
      : "Level 0 · Open Link";

  document.getElementById("card-tier-0").classList.toggle("active", tier === 0);
  document.getElementById("card-tier-1").classList.toggle("active", tier >= 1);
  document.getElementById("card-tier-2").classList.toggle("unlocked-l2", tier >= 2);

  document.getElementById("status-tier-1").textContent = tier >= 1 ? "Unlocked ✓" : "Locked";
  document.getElementById("status-tier-1").style.color = tier >= 1 ? "var(--gold)" : "var(--muted)";
  document.getElementById("status-tier-2").textContent = tier >= 2 ? "Unlocked ✓" : "Locked";
  document.getElementById("status-tier-2").style.color = tier >= 2 ? "var(--teal)" : "var(--muted)";

  document.getElementById("btn-open-login").classList.toggle("hidden", tier >= 2);
  document.getElementById("btn-open-register").classList.toggle("hidden", tier >= 1);
  document.getElementById("btn-open-nda").classList.toggle("hidden", tier !== 1);
  document.getElementById("btn-logout").classList.toggle("hidden", tier === 0);
  document.getElementById("btn-open-outbox").classList.toggle("hidden", !devOutboxAvailable);

  // Upload dropzone gating
  const dz = document.getElementById("upload-dropzone");
  const fileInput = document.getElementById("file-input");
  const uploadLock = document.getElementById("upload-lock-msg");
  const uploadReady = document.getElementById("upload-ready-msg");
  const modeHint = document.getElementById("upload-mode-hint");

  if (tier >= 1) {
    dz.classList.add("unlocked");
    uploadLock.classList.add("hidden");
    uploadReady.classList.remove("hidden");
    fileInput.multiple = tier >= 2;
    modeHint.textContent =
      tier >= 2
        ? "Level 2: Multi-photo batch + EXIF timestamp extraction active"
        : "Level 1: Single photo upload active (Sign NDA for batch + EXIF)";
    document.getElementById("btn-save-offset").classList.remove("hidden");
    document.getElementById("offset-tier-hint").textContent = "(Saved to your Twisted23 profile)";
    if (currentUser.favoriteOffset && !document.getElementById("offset-input").value) {
      document.getElementById("offset-input").value = currentUser.favoriteOffset;
    }
  } else {
    dz.classList.remove("unlocked");
    uploadLock.classList.remove("hidden");
    uploadReady.classList.add("hidden");
    document.getElementById("btn-save-offset").classList.add("hidden");
    document.getElementById("offset-tier-hint").textContent = "(Register for Level 1 to save default)";
  }

  // Level 2 Workspace gating
  document.getElementById("l2-locked-cta").classList.toggle("hidden", tier >= 2);
  document.getElementById("btn-l2-export-axif").classList.toggle("hidden", tier < 2);
  document.getElementById("btn-download-nda-receipt").classList.toggle("hidden", tier < 2);
  document.getElementById("l2-subtitle").textContent =
    tier >= 2
      ? `Unlocked for ${currentUser.name} · NDA ${currentUser.ndaReceipt?.receiptId || ""} verified`
      : tier === 1
      ? "Signed in at Level 1 — sign the NDA to unlock multi-photo EXIF extraction & AXIF export."
      : "Requires Level 1 registration + built-in Level 2 NDA e-signature.";

  renderSelectedPhoto();
  renderBatchTable();
}

async function refreshSession() {
  const data = await api("/api/session");
  currentUser = data.user;
  devOutboxAvailable = Boolean(data.devOutboxAvailable);
  if (currentUser.favoriteOffset) {
    document.getElementById("offset-input").value = currentUser.favoriteOffset;
  }
  syncAuthUi();
}

async function handleFilesUploaded(fileList) {
  if (currentUser.tier < 1) {
    showToast("Register & verify at Level 1 to upload your own photos.");
    openModal("modal-register");
    return;
  }
  const files = Array.from(fileList || []).filter((f) => f.type.startsWith("image/"));
  if (files.length === 0) return;

  const allowedFiles = currentUser.tier >= 2 ? files : [files[0]];
  if (currentUser.tier === 1 && files.length > 1) {
    showToast("Level 1 supports 1 photo at a time — sign the NDA for full multi-photo batch.");
  }

  const processed = [];
  for (const f of allowedFiles) {
    const meta =
      currentUser.tier >= 2
        ? await inspectImageFile(f)
        : {
            unixSeconds: f.lastModified ? Math.floor(f.lastModified / 1000) : Math.floor(Date.now() / 1000),
            timestampSource: "File modified (sign NDA for EXIF)",
          };
    const dataUrl = await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.readAsDataURL(f);
    });
    const stem = f.name.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim();
    const isBoilerplate = /^(screenshot|screen shot|img_|dsc_|pxl_|capture|image|photo)/i.test(stem);
    processed.push({
      id: `up_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      originalName: f.name,
      subject: isBoilerplate ? "" : stem.slice(0, 32),
      unixSeconds: meta.unixSeconds,
      timestampSource: meta.timestampSource,
      dataUrl,
    });
  }

  if (currentUser.tier >= 2) {
    batchItems = [...processed, ...batchItems].slice(0, 25);
  }
  selectPhoto(processed[0]);
  renderBatchTable();
}

function escapeHtml(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function tickLiveClock() {
  const nowSec = Math.floor(Date.now() / 1000);
  const fav = sanitizeFavorite3LetterOffset(document.getElementById("offset-input")?.value || "") || "sun";
  const expr = cleanExactClockExpression({
    unixSeconds: nowSec,
    contextWords: [fav],
    alwaysUseDifferenceFormula: true,
    favoriteOffset: fav,
  }).expression;
  document.getElementById("live-clock-pill").textContent = `Clock: ${expr}`;
}

async function openDevOutboxModal() {
  const data = await api("/api/dev-outbox");
  const container = document.getElementById("outbox-list");
  if (!data.messages || data.messages.length === 0) {
    container.innerHTML = `<div style="font-size: 13px; color: var(--muted);">No emails in local Dev Outbox yet. Register for Level 1 first.</div>`;
  } else {
    container.innerHTML = "";
    for (const m of data.messages) {
      const card = document.createElement("div");
      card.style.cssText = "padding: 12px; border: 1px solid var(--border); border-radius: 10px; background: var(--bg);";
      card.innerHTML = `
        <div style="display:flex; justify-content:space-between; align-items:center; gap:8px; flex-wrap:wrap;">
          <strong>${escapeHtml(m.subject)}</strong>
          <span style="font-size:11px; color:var(--muted);">${escapeHtml(m.toEmail)}</span>
        </div>
        <div style="margin-top:8px; display:flex; align-items:center; gap:10px; flex-wrap:wrap;">
          <code style="padding:4px 8px; border-radius:6px; background:var(--gold-dim); color:var(--gold); font-size:14px;">${escapeHtml(m.base38Password)}</code>
          <button class="sm primary use-pwd-btn">Sign In with This Password</button>
        </div>
      `;
      card.querySelector(".use-pwd-btn").addEventListener("click", () => {
        closeModal("modal-outbox");
        document.getElementById("login-password").value = m.base38Password;
        document.getElementById("login-email").value = m.toEmail;
        openModal("modal-login");
      });
      container.appendChild(card);
    }
  }
  openModal("modal-outbox");
}

async function openNdaModal() {
  if (currentUser.tier < 1) {
    showToast("Sign in at Level 1 first to sign the Level 2 NDA.");
    openModal("modal-register");
    return;
  }
  const data = await api("/api/nda");
  document.getElementById("nda-markdown-box").textContent = data.markdown;
  document.getElementById("nda-template-sha").textContent = data.templateSha256;
  document.getElementById("nda-legal-name").value = currentUser.name || "";
  openModal("modal-nda");
}

// Wire events
document.querySelectorAll("[data-close]").forEach((btn) => {
  btn.addEventListener("click", () => closeModal(btn.dataset.close));
});
document.getElementById("btn-open-register").addEventListener("click", () => openModal("modal-register"));
document.getElementById("btn-open-login").addEventListener("click", () => openModal("modal-login"));
document.getElementById("btn-open-outbox").addEventListener("click", openDevOutboxModal);
document.getElementById("btn-open-nda").addEventListener("click", openNdaModal);
document.getElementById("btn-cta-nda").addEventListener("click", openNdaModal);

document.getElementById("btn-logout").addEventListener("click", async () => {
  await api("/api/logout", { method: "POST", body: "{}" });
  currentUser = { authenticated: false, tier: 0, favoriteOffset: "" };
  batchItems = [];
  syncAuthUi();
  showToast("Signed out back to Level 0.");
});

document.getElementById("subject-input").addEventListener("input", () => {
  if (selectedPhoto) selectedPhoto.subject = document.getElementById("subject-input").value;
  renderSelectedPhoto();
});

document.getElementById("offset-input").addEventListener("input", () => {
  renderSelectedPhoto();
  renderBatchTable();
  tickLiveClock();
});

document.querySelectorAll("#offset-chips .chip-btn[data-offset]").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.getElementById("offset-input").value = btn.dataset.offset;
    renderSelectedPhoto();
    renderBatchTable();
    tickLiveClock();
  });
});

document.getElementById("btn-save-offset").addEventListener("click", async () => {
  try {
    const raw = document.getElementById("offset-input").value;
    const data = await api("/api/preferences", {
      method: "POST",
      body: JSON.stringify({ favoriteOffset: raw }),
    });
    currentUser = data.user;
    document.getElementById("offset-input").value = currentUser.favoriteOffset || "";
    renderSelectedPhoto();
    showToast(
      currentUser.favoriteOffset
        ? `Saved default 3-letter offset: -${currentUser.favoriteOffset}`
        : "Cleared default offset to Auto."
    );
  } catch (err) {
    showToast(err.message);
  }
});

document.getElementById("btn-copy-filename").addEventListener("click", async () => {
  const txt = document.getElementById("output-filename").textContent;
  await navigator.clipboard?.writeText(txt).catch(() => {});
  showToast(`Copied: ${txt}`);
});

document.getElementById("btn-download-renamed").addEventListener("click", () => {
  if (!selectedPhoto) return;
  const named = computePhotoNaming(selectedPhoto);
  const a = document.createElement("a");
  a.href = selectedPhoto.dataUrl;
  a.download = named.filename;
  a.click();
});

const dz = document.getElementById("upload-dropzone");
const fileInput = document.getElementById("file-input");
dz.addEventListener("click", () => {
  if (currentUser.tier < 1) {
    openModal("modal-register");
    return;
  }
  fileInput.click();
});
dz.addEventListener("dragover", (e) => {
  e.preventDefault();
});
dz.addEventListener("drop", (e) => {
  e.preventDefault();
  handleFilesUploaded(e.dataTransfer.files);
});
fileInput.addEventListener("change", (e) => handleFilesUploaded(e.target.files));

document.getElementById("form-register").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    const name = document.getElementById("reg-name").value;
    const email = document.getElementById("reg-email").value;
    const favoriteOffset = document.getElementById("reg-offset").value;
    const res = await api("/api/register", {
      method: "POST",
      body: JSON.stringify({ name, email, favoriteOffset }),
    });
    closeModal("modal-register");
    showToast(res.message);
    if (res.deliveryMode === "dev-outbox" && devOutboxAvailable) {
      await openDevOutboxModal();
    } else {
      document.getElementById("login-email").value = email;
      openModal("modal-login");
    }
  } catch (err) {
    showToast(err.message);
  }
});

document.getElementById("form-login").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    const password = document.getElementById("login-password").value;
    const email = document.getElementById("login-email").value;
    const res = await api("/api/login", {
      method: "POST",
      body: JSON.stringify({ password, email }),
    });
    currentUser = res.user;
    if (currentUser.favoriteOffset) {
      document.getElementById("offset-input").value = currentUser.favoriteOffset;
    }
    closeModal("modal-login");
    syncAuthUi();
    showToast(`Signed in at ${currentUser.tierLabel}!`);
  } catch (err) {
    showToast(err.message);
  }
});

document.getElementById("form-nda").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    const res = await api("/api/nda/sign", {
      method: "POST",
      body: JSON.stringify({
        legalName: document.getElementById("nda-legal-name").value,
        companyOrRole: document.getElementById("nda-company").value,
        typedSignature: document.getElementById("nda-signature").value,
        agreed: document.getElementById("nda-agreed").checked,
      }),
    });
    currentUser = res.user;
    closeModal("modal-nda");
    syncAuthUi();
    showToast(`NDA signed! Level 2 Base-38 Password: ${res.level2Password}`);
  } catch (err) {
    showToast(err.message);
  }
});

document.getElementById("btn-download-nda-receipt").addEventListener("click", () => {
  if (!currentUser.ndaReceipt) return;
  const blob = new Blob([JSON.stringify(currentUser.ndaReceipt, null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `${currentUser.ndaReceipt.receiptId || "Twisted23-NDA"}.json`;
  a.click();
});

document.getElementById("btn-l2-export-axif").addEventListener("click", () => {
  if (currentUser.tier < 2) return;
  const items = batchItems.length ? batchItems : [selectedPhoto];
  const lines = [
    "---",
    `platform: "Twisted23.com"`,
    `signer: "${currentUser.name}"`,
    `nda_receipt: "${currentUser.ndaReceipt?.receiptId || ""}"`,
    "---",
    "",
    "# Twisted23 Level 2 Batch Export",
    "",
  ];
  for (const item of items) {
    const named = computePhotoNaming(item);
    lines.push(`- ![${named.filename}](${named.filename}) — \`${named.expression}\` (${item.timestampSource})`);
  }
  const blob = new Blob([lines.join("\n")], { type: "text/markdown;charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `Twisted23-AXIF-Export-${currentUser.ndaReceipt?.signedAtBase38 || "batch"}.md`;
  a.click();
});

// Init
renderSampleList();
selectPhoto(SAMPLES[0]);
tickLiveClock();
setInterval(tickLiveClock, 1000);
refreshSession().catch((err) => console.error(err));
