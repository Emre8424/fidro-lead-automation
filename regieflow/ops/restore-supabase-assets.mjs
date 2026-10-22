import { readdir, readFile } from "node:fs/promises";
import { join, relative, sep } from "node:path";

const root = process.argv[2];
const base = process.env.TARGET_SUPABASE_URL?.replace(/\/$/, "");
const key = process.env.TARGET_SUPABASE_SERVICE_ROLE_KEY;
if (!root || !base || !key) {
  throw new Error("Usage: restore-supabase-assets.mjs <storage-root> with TARGET_SUPABASE_URL and TARGET_SUPABASE_SERVICE_ROLE_KEY");
}
const headers = { apikey: key, Authorization: `Bearer ${key}` };

async function walk(dir) {
  const out = [];
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...await walk(p));
    else out.push(p);
  }
  return out;
}
function encPath(path) {
  return path.split("/").map(encodeURIComponent).join("/");
}
async function ensureBucket(bucket) {
  const r = await fetch(`${base}/storage/v1/bucket/${encodeURIComponent(bucket)}`, { headers });
  if (r.ok) return;
  if (r.status !== 404) throw new Error(`Check bucket ${bucket}: ${r.status} ${await r.text()}`);
  const c = await fetch(`${base}/storage/v1/bucket`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ id: bucket, name: bucket, public: false }),
  });
  if (!c.ok) throw new Error(`Create bucket ${bucket}: ${c.status} ${await c.text()}`);
}

let restored = 0;
for (const bucket of ["rf-private", "rf-branding"]) {
  const dir = join(root, bucket);
  let files = [];
  try { files = await walk(dir); } catch { continue; }
  await ensureBucket(bucket);
  for (const file of files) {
    const rel = relative(dir, file).split(sep).join("/");
    const bytes = await readFile(file);
    const r = await fetch(`${base}/storage/v1/object/${encodeURIComponent(bucket)}/${encPath(rel)}`, {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/octet-stream", "x-upsert": "true" },
      body: bytes,
    });
    if (!r.ok) throw new Error(`Restore ${bucket}/${rel}: ${r.status} ${await r.text()}`);
    restored++;
  }
}
console.log(JSON.stringify({ restored }));
