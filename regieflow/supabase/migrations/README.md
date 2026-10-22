# RegieFlow database migrations

These files are deterministic snapshots of the **applied RegieFlow migrations** read from `supabase_migrations.schema_migrations`.

They intentionally contain only migrations whose name starts with `regieflow_`, so unrelated DriveLoop schema changes in the shared Supabase project are excluded.

Files are grouped by application date and ordered by migration version:

- `20261001_regieflow_applied.sql`
- `20261005_regieflow_applied.sql`
- `20261022_regieflow_applied.sql`

## Purpose

The live project remains the current source for migration history, while these checked-in snapshots make the RegieFlow database reproducible from source control and provide an independent disaster-recovery path.

The encrypted backup script also exports a fresh migration bundle directly from the live migration table at backup time.

## Going forward

For every new RegieFlow database change:

1. apply it through a named Supabase migration beginning with `regieflow_`
2. keep the migration SQL in source control
3. run `public.rf_system_integrity_check()`
4. verify `rf-health`
5. update the private development log when the change is material

Do not add DriveLoop migrations to this directory.
