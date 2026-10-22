# RegieFlow recovery and production notes

## Canonical deployment

- Frontend: https://regieflow.pages.dev/
- Frontend source: `regieflow/index.html`, `regieflow/app.js`, `regieflow/sw.js`
- Supabase project ref: `kiihabzzepoehsokglzq`
- RegieFlow currently shares this development Supabase project with DriveLoop.
- RegieFlow public database objects use the `rf_` prefix.
- Server-only RegieFlow state is in the `regieflow_private` schema.
- Do not modify DriveLoop tables/functions while restoring RegieFlow.

## Active RegieFlow Edge Function source snapshots

Current function source snapshots are stored below `regieflow/supabase/functions/`:

- rf-public-approval
- rf-auth-approval
- rf-create-internal-user
- rf-claim-customer-invite
- rf-customer-signup
- rf-push
- rf-upload-evidence
- rf-upload-branding
- rf-create-checkout
- rf-stripe-webhook
- rf-onboarding-status
- rf-complete-paid-signup
- rf-billing-portal
- rf-sync-seat-billing
- rf-health
- rf-billing-readiness
- rf-public-legal

Retired development/static endpoints may still exist in the Supabase project but are JWT-protected and are not part of the production flow.

Secrets are intentionally not committed. Service-role keys, Stripe secrets/webhook secrets, VAPID private keys and internal hook secrets must remain outside Git.

## Core production invariants

- Every Regie belongs to one company and one project.
- Submitted Regie versions are immutable.
- At least one before-work image is mandatory before submission.
- A customer may approve only the current submitted version and only when authorized for that project.
- Signed Regie PDFs and approval records are append-only and version-bound.
- Closed Regien require a Rapportnummer.
- Historical signed PDFs remain accessible; current evidence is shown per current version.
- Customer accounts are free and are not counted as paid internal seats.
- Paid companies become read-only if their subscription is not in an allowed write state.
- Primary Owner cannot be accidentally deactivated or stripped of ownership through normal member management.

## Production readiness gate

Public paid onboarding is implemented but deliberately hard-gated. `rf-billing-readiness` must report `ready: true` before public signup can proceed.

The following must all be true:

1. Published legal pages exist.
2. Stripe plan Price IDs and required Stripe secrets are configured.
3. Email confirmation + production SMTP have been verified.
4. Leaked-password protection has been enabled and verified.
5. Backup/recovery has been configured and tested.

The private checklist is authoritative:
`regieflow_private.launch_checklist`.

## Backup / recovery

The current Supabase Free setup must not be treated as sufficient production backup.

Before public launch choose one:

### Preferred production setup
Move RegieFlow to its own paid Supabase project and enable managed backups appropriate to the required retention/RPO. Storage still needs its own off-site protection because database backups do not restore deleted Storage objects.

### Temporary/self-managed setup

The executable runbook is in `regieflow/ops/`:

- `backup-regieflow.sh`
- `export-supabase-assets.mjs`
- `restore-regieflow.sh`
- `restore-auth-users.mjs`
- `restore-supabase-assets.mjs`
- `ops/README.md`

The encrypted backup contains:

- deterministic applied RegieFlow migration SQL,
- RegieFlow database/private rows,
- RegieFlow Auth users with their original UUIDs and password hashes,
- `rf-private` and `rf-branding` objects,
- checksums and an emergency full schema snapshot.

The restore procedure preserves Auth UUIDs before restoring FK-dependent RegieFlow rows, restores Storage with correct image/PDF MIME types, and finishes with `rf_system_integrity_check()`.

A **real off-site destination and a restore drill against a non-production project are still mandatory** before marking production backup readiness true. Do not commit encrypted production backups or backup secrets to this public repository.

## Tested live flows

Live test milestones already completed:

- Owner/company bootstrap
- Project + customer contacts
- Internal Regie creation
- Mandatory before image
- Direct-to-customer flow
- Revision/version lock
- Secure public approval link
- Customer signature + explicit consent
- Immutable signed PDF + SHA-256
- Execution start
- Work completion
- Rapportnummer closeout
- Archive access
- Customer account invitation/signup
- Customer-created request
- Office acceptance/assignment
- Customer/office comments
- Notification deep links

The remaining browser-only tests are tracked in the private launch checklist.

## Migration history

The live authoritative migration history remains in `supabase_migrations.schema_migrations`. Applied RegieFlow migrations are also source-controlled under:

`regieflow/supabase/migrations/`

These snapshots contain only migrations whose names start with `regieflow_`, ordered by migration version, and intentionally exclude DriveLoop migrations. The backup script independently generates a fresh migration bundle from the live migration table at backup time.

RegieFlow migrations start at `20261001071253_regieflow_core_tables_v1`.

## Production move recommendation

Before public paid launch, prefer giving RegieFlow its own Supabase project instead of sharing the DriveLoop development project.

Migration sequence:

1. Create a dedicated Supabase project.
2. Apply only RegieFlow schema/migrations and required extensions.
3. Create private Storage buckets `rf-private` and `rf-branding`.
4. Deploy all active RegieFlow Edge Functions from the snapshots above.
5. Recreate private configuration/secrets.
6. Configure Stripe webhook destination and Price IDs.
7. Configure email confirmation, SMTP and password protection.
8. Restore/copy production data if needed.
9. Update frontend Supabase URL/publishable key.
10. Run the full E2E test and integrity self-check.
11. Only then point the public domain to the production deployment.

The chronological implementation log remains in `regieflow_private.dev_log`.
