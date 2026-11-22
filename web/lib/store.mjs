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

async function kvGet(cfg) {
  const res = await fetch(`${cfg.url}/get/${encodeURIComponent(KV_KEY)}`, {
    headers: { Authorization: `Bearer ${cfg.token}` },
  });
  if (!res.ok) {
    throw new Error(`KV get failed: ${res.status}`);
  }
  const data = await res.json();
  if (!data || data.result == null) return emptyState();
  const parsed = typeof data.result === "string" ? JSON.parse(data.result) : data.result;
  return { ...emptyState(), ...parsed };
}

async function kvSet(cfg, state) {
  const res = await fetch(`${cfg.url}/set/${encodeURIComponent(KV_KEY)}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(state),
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

export function createStore({ filePath = null } = {}) {
  const targetFile = resolveFilePath(filePath);

  async function readState() {
    const kv = getKvConfig();
    if (kv) return kvGet(kv);
    return fileGet(targetFile);
  }

  async function updateState(mutator) {
    const run = async () => {
      const state = await readState();
      const result = await mutator(state);
      const kv = getKvConfig();
      if (kv) await kvSet(kv, state);
      else await fileSet(targetFile, state);
      return result;
    };
    const next = memoryQueue.then(run, run);
    memoryQueue = next.catch(() => {});
    return next;
  }

  return { readState, updateState };
}

export const defaultStore = createStore();
