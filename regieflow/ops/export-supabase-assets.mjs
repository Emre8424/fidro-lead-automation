import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const out = process.argv[2];
const base = process.env.SUPABASE_URL?.replace(/\/$/, "");
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!out || !base || !key) {
  throw new Error("Output path, SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
}
const headers = { apikey: key, Authorization: `Bearer ${key}` };

async function api(path, init = {}) {
  const response = await fetch(base + path, {
    ...init,
    headers: { ...headers, ...(init.headers || {}) },
  });
  if (!response.ok) {
    throw new Error(`${init.method || "GET"} ${path}: ${response.status} ${await response.text()}`);
  }
  return response;
}

async function exportUsers() {
  const users = [];
  for (let page = 1; ; page++) {
    const r = await api(`/auth/v1/admin/users?page=${page}&per_page=1000`);
    const body = await r.json();
    const batch = Array.isArray(body) ? body : (body.users || []);
    users.push(...batch);
    if (batch.length < 1000) break;
  }
  await writeFile(join(out, "auth-users.json"), JSON.stringify({ users }, null, 2));
  return users.length;
}

function encPath(path) {
  return path.split("/").map(encodeURIComponent).join("/");
}

async function listFolder(bucket, prefix = "") {
  const r = await api(`/storage/v1/object/list/${encodeURIComponent(bucket)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      prefix,
      limit: 1000,
      offset: 0,
      sortBy: { column: "name", order: "asc" },
    }),
  });
  const rows = await r.json();
  const files = [];
  for (const row of rows || []) {
    const full = prefix ? `${prefix}/${row.name}` : row.name;
    if (row.metadata) files.push(full);
    else files.push(...await listFolder(bucket, full));
  }
  return files;
}

async function exportBucket(bucket) {
  const paths = await listFolder(bucket);
  let count = 0;
  for (const path of paths) {
    const r = await api(`/storage/v1/object/authenticated/${encodeURIComponent(bucket)}/${encPath(path)}`);
    const bytes = new Uint8Array(await r.arrayBuffer());
    const target = join(out, "storage", bucket, ...path.split("/"));
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, bytes);
    count++;
  }
  return count;
}

await mkdir(out, { recursive: true });
const authUsers = await exportUsers();
const storage = {};
for (const bucket of ["rf-private", "rf-branding"]) {
  storage[bucket] = await exportBucket(bucket);
}
await writeFile(join(out, "export-summary.json"), JSON.stringify({
  createdAt: new Date().toISOString(),
  authUsers,
  storage,
}, null, 2));

console.log(JSON.stringify({ authUsers, storage }));
