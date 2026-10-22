# RegieFlow Backup & Recovery

This directory contains the production backup/restore tooling for RegieFlow.

## What is backed up

`backup-regieflow.sh` creates one encrypted package containing:

- a reproducible SQL bundle of all migrations whose name starts with `regieflow_`
- RegieFlow application rows from `public.rf_*`
- private RegieFlow operational/configuration rows from `regieflow_private.*`
- RegieFlow Auth users with their original UUIDs and password hashes
- Auth metadata export for inspection
- private Storage objects from `rf-private` and `rf-branding`
- a SHA-256 manifest
- an emergency full schema snapshot (`schema.dump`)

The final package is encrypted with AES-256-CBC + PBKDF2. Plaintext temporary files are deleted when the script exits.

## Backup

Required environment variables:

- `REGIEFLOW_DATABASE_URL`: Postgres connection string with backup privileges
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `BACKUP_PASSPHRASE`: a strong secret kept outside the repository

Run:

```bash
./backup-regieflow.sh /secure/offsite/path
```

The destination **must not** be this public Git repository. Store the encrypted output in a private/off-site location.

## Restore

Use a clean or disposable target Supabase project first. Required variables:

- `TARGET_DATABASE_URL`
- `TARGET_SUPABASE_URL`
- `TARGET_SUPABASE_SERVICE_ROLE_KEY`
- `BACKUP_PASSPHRASE`
- `RESTORE_CONFIRM=RESTORE_REGIEFLOW`

Run:

```bash
RESTORE_CONFIRM=RESTORE_REGIEFLOW \
./restore-regieflow.sh /secure/offsite/regieflow-...tar.gz.enc
```

The restore sequence is deliberately fixed:

1. decrypt + verify SHA-256 checksums
2. replay RegieFlow migrations
3. recreate Auth users with their original UUIDs/password hashes
4. truncate **only** RegieFlow application/private tables
5. restore RegieFlow database rows with triggers disabled
6. restore private Storage objects
7. run `rf_system_integrity_check()`

DriveLoop tables are not truncated by this restore script.

## Recovery limitations

- Existing browser/Auth sessions are not restored. Users sign in again.
- The current app does not use MFA. If MFA is introduced, the backup procedure must be extended to include/rebuild MFA factors before this runbook is considered complete for MFA accounts.
- Stripe itself remains the source of truth for subscription/provider objects. RegieFlow restores its provider IDs and then normal Stripe webhook/reconciliation flows resume.
- A backup that has never been restored is not a proven backup. Before public launch, run a restore drill against a non-production Supabase project and mark `backup_recovery_ready` only after the integrity check passes.

## Security

Never commit any of the following:

- database URLs containing passwords
- service-role keys
- backup passphrases
- decrypted backup directories
- encrypted production backups

The repository should contain only the tooling and runbook.
