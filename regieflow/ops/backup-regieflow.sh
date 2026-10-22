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

for cmd in pg_dump psql node openssl tar; do
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

echo "[2/6] Exporting reproducible RegieFlow migrations..."
{
  cat <<'SQL'
-- RegieFlow migration bundle
-- Generated from supabase_migrations.schema_migrations.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
SQL
  psql "$REGIEFLOW_DATABASE_URL" -X -qAt -v ON_ERROR_STOP=1 -c "
    select
      E'\\n-- ' || version || ' ' || name || E'\\n' ||
      array_to_string(statements,E'\\n')
    from supabase_migrations.schema_migrations
    where name like 'regieflow_%'
    order by version;
  "
} > "$WORK/regieflow-migrations.sql"

echo "[3/6] Exporting RegieFlow Auth restore records..."
psql "$REGIEFLOW_DATABASE_URL" -X -qAt -v ON_ERROR_STOP=1 -c "
  with ids as (
    select primary_owner_user_id as id from public.rf_companies
    union
    select user_id from public.rf_memberships
    union
    select auth_user_id from public.rf_customer_contacts where auth_user_id is not null
  )
  select jsonb_pretty(
    jsonb_build_object(
      'users',
      coalesce(jsonb_agg(
        jsonb_build_object(
          'id',u.id,
          'email',u.email,
          'phone',u.phone,
          'password_hash',u.encrypted_password,
          'email_confirm',u.email_confirmed_at is not null,
          'phone_confirm',u.phone_confirmed_at is not null,
          'user_metadata',coalesce(u.raw_user_meta_data,'{}'::jsonb),
          'app_metadata',coalesce(u.raw_app_meta_data,'{}'::jsonb)
        )
        order by u.created_at
      ),'[]'::jsonb)
    )
  )
  from auth.users u
  join ids on ids.id=u.id;
" > "$WORK/auth-users-restore.json"

echo "[4/6] Exporting Auth metadata and Storage objects..."
node "$(dirname "$0")/export-supabase-assets.mjs" "$WORK"

echo "[5/6] Writing manifest..."
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
Auth metadata export: auth-users.json
Auth restore records: auth-users-restore.json (UUID + password hash, encrypted inside package)
Migration bundle: regieflow-migrations.sql
EOF

echo "[6/6] Encrypting package..."
ARCHIVE="$TMP_ROOT/regieflow-$STAMP.tar.gz"
tar -C "$TMP_ROOT" -czf "$ARCHIVE" "regieflow-$STAMP"
OUT="$DEST/regieflow-$STAMP.tar.gz.enc"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 250000   -in "$ARCHIVE" -out "$OUT" -pass env:BACKUP_PASSPHRASE

echo "[verify] Verifying encrypted output..."
test -s "$OUT" || { echo "Encrypted backup is empty" >&2; exit 4; }
openssl enc -d -aes-256-cbc -pbkdf2 -iter 250000   -in "$OUT" -pass env:BACKUP_PASSPHRASE 2>/dev/null | tar -tzf - >/dev/null

echo "Backup written: $OUT"
echo "Encrypted package verified; plaintext working data removed automatically."
