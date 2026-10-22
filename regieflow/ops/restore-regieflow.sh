#!/usr/bin/env bash
set -euo pipefail

BACKUP="${1:-}"
if [[ -z "$BACKUP" || ! -f "$BACKUP" ]]; then
  echo "Usage: $0 /path/to/regieflow-YYYYMMDDTHHMMSSZ.tar.gz.enc" >&2
  exit 2
fi

: "${TARGET_DATABASE_URL:?TARGET_DATABASE_URL is required}"
: "${TARGET_SUPABASE_URL:?TARGET_SUPABASE_URL is required}"
: "${TARGET_SUPABASE_SERVICE_ROLE_KEY:?TARGET_SUPABASE_SERVICE_ROLE_KEY is required}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}"
: "${RESTORE_CONFIRM:?Set RESTORE_CONFIRM=RESTORE_REGIEFLOW after reviewing the target}"

if [[ "$RESTORE_CONFIRM" != "RESTORE_REGIEFLOW" ]]; then
  echo "Refusing restore: RESTORE_CONFIRM must equal RESTORE_REGIEFLOW" >&2
  exit 3
fi

for cmd in psql pg_restore node openssl tar shasum; do
  command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 4; }
done

TMP="$(mktemp -d)"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

echo "[1/7] Decrypting backup..."
ARCHIVE="$TMP/backup.tar.gz"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 250000 \
  -in "$BACKUP" -out "$ARCHIVE" -pass env:BACKUP_PASSPHRASE

tar -C "$TMP" -xzf "$ARCHIVE"
WORK="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name 'regieflow-*' | head -n 1)"
[[ -n "$WORK" ]] || { echo "Backup payload directory not found" >&2; exit 5; }

echo "[2/7] Verifying checksums..."
(
  cd "$WORK"
  shasum -a 256 -c SHA256SUMS
)

for required in regieflow-migrations.sql database.dump auth-users-restore.json; do
  [[ -s "$WORK/$required" ]] || { echo "Missing backup payload: $required" >&2; exit 6; }
done

echo "[3/7] Applying RegieFlow schema migrations..."
psql "$TARGET_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$WORK/regieflow-migrations.sql"

echo "[4/7] Restoring Auth users with original UUIDs..."
TARGET_SUPABASE_URL="$TARGET_SUPABASE_URL" \
TARGET_SUPABASE_SERVICE_ROLE_KEY="$TARGET_SUPABASE_SERVICE_ROLE_KEY" \
node "$(dirname "$0")/restore-auth-users.mjs" "$WORK/auth-users-restore.json"

echo "[5/7] Replacing RegieFlow application data..."
psql "$TARGET_DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
do $$
declare
  v_tables text;
begin
  select string_agg(format('%I.%I',schemaname,tablename),', ')
    into v_tables
  from pg_tables
  where (schemaname='public' and tablename like 'rf_%')
     or schemaname='regieflow_private';

  if v_tables is not null then
    execute 'truncate table '||v_tables||' restart identity cascade';
  end if;
end
$$;
SQL

pg_restore \
  --dbname="$TARGET_DATABASE_URL" \
  --data-only \
  --disable-triggers \
  --no-owner \
  --no-acl \
  --exit-on-error \
  "$WORK/database.dump"

echo "[6/7] Restoring private Storage objects..."
if [[ -d "$WORK/storage" ]]; then
  TARGET_SUPABASE_URL="$TARGET_SUPABASE_URL" \
  TARGET_SUPABASE_SERVICE_ROLE_KEY="$TARGET_SUPABASE_SERVICE_ROLE_KEY" \
  node "$(dirname "$0")/restore-supabase-assets.mjs" "$WORK/storage"
fi

echo "[7/7] Running RegieFlow integrity check..."
psql "$TARGET_DATABASE_URL" -X -v ON_ERROR_STOP=1 -c \
  "select public.rf_system_integrity_check();"

echo
echo "Restore completed."
echo "Users keep their original UUIDs/password hashes. Existing sessions are intentionally not restored; users sign in again."
echo "If MFA is introduced later, extend the backup/restore procedure for MFA factors before relying on this runbook."
