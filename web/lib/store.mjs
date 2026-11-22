import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_DATA_PATH = path.resolve(__dirname, "..", ".data", "twisted23-store.json");

function emptyState() {
  return {
    usersById: {},
    userIdByEmail: {},
    credentialByIndex: {},
    ndaReceipts: [],
    devOutbox: [],
    imagesBySlug: {},
    dailyUploadsByUserDay: {},
  };
}

function getKvConfig() {
  const url = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
  if (url && token) {
    return { url: url.replace(/\/$/, ""), token };
  }
  return null;
}

const KV_KEY = process.env.TWISTED23_KV_KEY || "twisted23:photo_demo:state:v1";
const KV_BLOB_PREFIX = process.env.TWISTED23_KV_BLOB_PREFIX || "twisted23:photo_demo:blob:v1:";

async function kvGet(cfg, key = KV_KEY) {
  const res = await fetch(`${cfg.url}/get/${encodeURIComponent(key)}`, {
    headers: { Authorization: `Bearer ${cfg.token}` },
  });
  if (!res.ok) {
    throw new Error(`KV get failed: ${res.status}`);
  }
  const data = await res.json();
  if (!data || data.result == null) return null;
  return typeof data.result === "string" ? JSON.parse(data.result) : data.result;
}

async function kvSet(cfg, value, key = KV_KEY) {
  const res = await fetch(`${cfg.url}/set/${encodeURIComponent(key)}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(value),
  });
  if (!res.ok) {
    throw new Error(`KV set failed: ${res.status}`);
  }
}

function resolveFilePath(overridePath) {
  return overridePath || process.env.TWISTED23_DATA_FILE || DEFAULT_DATA_PATH;
}

async function fileGet(filePath) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    return { ...emptyState(), ...JSON.parse(raw) };
  } catch (err) {
    if (err && err.code === "ENOENT") {
      return emptyState();
    }
    throw err;
  }
}

async function fileSet(filePath, state) {
  const dir = path.dirname(filePath);
  await fs.mkdir(dir, { recursive: true });
  const tmpPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tmpPath, JSON.stringify(state, null, 2), "utf8");
  await fs.rename(tmpPath, filePath);
}

let memoryQueue = Promise.resolve();

export function createStore({ filePath = null, uploadsDir = null } = {}) {
  const targetFile = resolveFilePath(filePath);
  const targetUploadsDir =
    uploadsDir ||
    process.env.TWISTED23_UPLOADS_DIR ||
    path.resolve(path.dirname(targetFile), "uploads");

  async function readState() {
    const kv = getKvConfig();
    if (kv) {
      const parsed = await kvGet(kv, KV_KEY);
      return parsed ? { ...emptyState(), ...parsed } : emptyState();
    }
    return fileGet(targetFile);
  }

  async function updateState(mutator) {
    const run = async () => {
      const state = await readState();
      const result = await mutator(state);
      const kv = getKvConfig();
      if (kv) await kvSet(kv, state, KV_KEY);
      else await fileSet(targetFile, state);
      return result;
    };
    const next = memoryQueue.then(run, run);
    memoryQueue = next.catch(() => {});
    return next;
  }

  async function saveImageBlob(safeFilename, buffer) {
    const cleanName = path.basename(safeFilename);
    const kv = getKvConfig();
    if (kv) {
      await kvSet(kv, { base64: buffer.toString("base64") }, `${KV_BLOB_PREFIX}${cleanName}`);
      return;
    }
    await fs.mkdir(targetUploadsDir, { recursive: true });
    await fs.writeFile(path.join(targetUploadsDir, cleanName), buffer);
  }

  async function readImageBlob(safeFilename) {
    const cleanName = path.basename(safeFilename);
    const kv = getKvConfig();
    if (kv) {
      const rec = await kvGet(kv, `${KV_BLOB_PREFIX}${cleanName}`);
      return rec?.base64 ? Buffer.from(rec.base64, "base64") : null;
    }
    try {
      return await fs.readFile(path.join(targetUploadsDir, cleanName));
    } catch (err) {
      if (err && err.code === "ENOENT") return null;
      throw err;
    }
  }

  return { readState, updateState, saveImageBlob, readImageBlob };
}

export const defaultStore = createStore();
