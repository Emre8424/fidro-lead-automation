# RegieFlow backup setup

This directory contains a self-managed encrypted backup helper for the current Supabase Free deployment.

It is intentionally **not scheduled or enabled automatically** because production backup credentials and the off-site destination must never be committed to this public repository.

## What the backup contains

- RegieFlow application data from `public.rf_*`
- RegieFlow private server tables from `regieflow_private.*`
- Supabase Auth user metadata export
- all objects from `rf-private`
- all objects from `rf-branding`
- a manifest with timestamps/counts/checksums

The output is encrypted before the plaintext working directory is removed.

## Required environment variables

- `REGIEFLOW_DATABASE_URL` — direct Postgres connection string
- `SUPABASE_URL` — project API URL
- `SUPABASE_SERVICE_ROLE_KEY` — service-role key
- `BACKUP_PASSPHRASE` — strong encryption passphrase

Never put these values in Git.

## Requirements

- bash
- pg_dump
- node 20+
- openssl
- tar

## Run

```bash
chmod +x regieflow/ops/backup-regieflow.sh
./regieflow/ops/backup-regieflow.sh /secure/offsite/path
```

The command produces one encrypted file named like:

`regieflow-20261005T170000Z.tar.gz.enc`

## Production schedule

Before public launch, run this from a private scheduler/CI runner whose encrypted output is copied to a private off-site bucket. Recommended minimum:

- daily backup
- 30-day retention
- monthly restore drill
- alert when a scheduled backup does not complete

Do **not** store unencrypted production backups as artifacts of this public GitHub repository.

## Restore notes

The migration chain/source-controlled schema remains the schema authority. Restore order:

1. create a clean RegieFlow Supabase project;
2. apply RegieFlow migrations/extensions;
3. deploy Edge Functions and private secrets;
4. restore RegieFlow database data;
5. recreate Auth users as supported by Supabase (password resets may be required because password material is not exported by the Admin API);
6. recreate `rf-private` and `rf-branding` and upload backed-up objects;
7. run `rf_system_integrity_check()`;
8. run the full browser E2E workflow before DNS cutover.

For a paid Supabase production project, keep managed database backups enabled as well. Storage still needs separate protection.
