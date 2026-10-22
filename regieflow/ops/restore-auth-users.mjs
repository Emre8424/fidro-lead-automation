import { readFile } from "node:fs/promises";

const file = process.argv[2];
const base = process.env.TARGET_SUPABASE_URL?.replace(/\/$/, "");
const key = process.env.TARGET_SUPABASE_SERVICE_ROLE_KEY;
if (!file || !base || !key) {
  throw new Error("Usage: restore-auth-users.mjs auth-users-restore.json with TARGET_SUPABASE_URL and TARGET_SUPABASE_SERVICE_ROLE_KEY");
}

const payload = JSON.parse(await readFile(file, "utf8"));
const users = Array.isArray(payload?.users) ? payload.users : [];
const headers = {
  apikey: key,
  Authorization: `Bearer ${key}`,
  "Content-Type": "application/json",
};

async function existingUsers() {
  const map = new Map();
  for (let page = 1; ; page++) {
    const r = await fetch(`${base}/auth/v1/admin/users?page=${page}&per_page=1000`, { headers });
    if (!r.ok) throw new Error(`List users failed: ${r.status} ${await r.text()}`);
    const body = await r.json();
    const batch = Array.isArray(body) ? body : (body.users || []);
    for (const u of batch) map.set(u.id, u);
    if (batch.length < 1000) break;
  }
  return map;
}

const existing = await existingUsers();
let created = 0, skipped = 0;
for (const u of users) {
  if (!u?.id) continue;
  if (existing.has(u.id)) {
    skipped++;
    continue;
  }
  const body = {
    id: u.id,
    email: u.email || undefined,
    phone: u.phone || undefined,
    password_hash: u.password_hash || undefined,
    email_confirm: !!u.email_confirm,
    phone_confirm: !!u.phone_confirm,
    user_metadata: u.user_metadata || {},
    app_metadata: u.app_metadata || {},
  };
  const r = await fetch(`${base}/auth/v1/admin/users`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`Create user ${u.id} failed: ${r.status} ${await r.text()}`);
  created++;
}
console.log(JSON.stringify({ created, skipped, total: users.length }));
