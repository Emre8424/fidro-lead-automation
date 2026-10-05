#!/usr/bin/env bash
set -euo pipefail

DEST="${1:-}"
if [[ -z "$DEST" ]]; then
  echo "Usage: $0 /secure/offsite/path" >&2
  exit 2
fi

: "${REGIEFLOW_DATABASE_URL:?REGIEFLOW_DATABASE_URL is required}"
: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY is required}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}"

for cmd in pg_dump node openssl tar; do
  command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 3; }
done

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TMP_ROOT="$(mktemp -d)"
WORK="$TMP_ROOT/regieflow-$STAMP"
mkdir -p "$WORK" "$DEST"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

echo "[1/5] Exporting database schema and RegieFlow rows..."
# Schema-only snapshot is intentionally broader than rf_* so functions, triggers,
# policies, extensions and migration history needed for a disaster rebuild are captured.
pg_dump "$REGIEFLOW_DATABASE_URL"   --format=custom   --no-owner   --no-acl   --schema-only   --file="$WORK/schema.dump"

pg_dump "$REGIEFLOW_DATABASE_URL"   --format=custom   --no-owner   --no-acl   --data-only   --table='public.rf_*'   --table='regieflow_private.*'   --file="$WORK/database.dump"

echo "[2/5] Exporting Auth metadata and Storage objects..."
node "$(dirname "$0")/export-supabase-assets.mjs" "$WORK"

echo "[3/5] Writing manifest..."
(
  cd "$WORK"
  find . -type f -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS
)
cat > "$WORK/MANIFEST.txt" <<EOF
RegieFlow backup
Created UTC: $STAMP
Supabase URL: $SUPABASE_URL
Schema payload: full Postgres schema snapshot (schema.dump)
Database payload: public.rf_* and regieflow_private.* rows
Storage buckets: rf-private, rf-branding
Auth export: auth-users.json
EOF

echo "[4/5] Encrypting package..."
ARCHIVE="$TMP_ROOT/regieflow-$STAMP.tar.gz"
tar -C "$TMP_ROOT" -czf "$ARCHIVE" "regieflow-$STAMP"
OUT="$DEST/regieflow-$STAMP.tar.gz.enc"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 250000   -in "$ARCHIVE" -out "$OUT" -pass env:BACKUP_PASSPHRASE

echo "[5/5] Verifying encrypted output..."
test -s "$OUT" || { echo "Encrypted backup is empty" >&2; exit 4; }
openssl enc -d -aes-256-cbc -pbkdf2 -iter 250000   -in "$OUT" -pass env:BACKUP_PASSPHRASE 2>/dev/null | tar -tzf - >/dev/null

echo "Backup written: $OUT"
echo "Encrypted package verified; plaintext working data removed automatically."
