# RegieFlow Launch Status

Last updated: 2026-10-22

## Runtime

- Frontend: https://regieflow.pages.dev/
- Frontend source branch: `regieflow-web-preview`
- Supabase project: DriveLoop Development (RegieFlow isolated by `rf_*` tables + `regieflow_private`)
- Cloudflare Pages production branch: `regieflow-web-preview`
- RegieFlow public registration remains hard-gated until all production readiness checks pass.

## Proven working

- Primary Owner company context
- Granular roles and permission-driven Büro/Monteur UI
- Projects and per-project approval flow
- Customer contacts and arbitrary authorized signers
- Customer accounts and customer-created requests
- Mandatory before-work evidence
- Real evidence upload via `rf-upload-evidence`
- Versioned immutable submitted Regien
- Büro review workflow
- Direct-to-customer workflow
- Secure one-time approval links
- Authenticated customer approval
- Explicit approval consent
- Signature SHA-256 and signed PDF SHA-256
- Immutable final signed PDF
- Before/after evidence lifecycle rules
- Execution start/completion
- Required Rapportnummer closeout
- Customer archive access
- Comments and status notifications
- Clickable grouped notifications
- Push backend/VAPID/private-hook authorization
- Subscription read-only mode after cancellation
- Stripe Checkout/Webhook/Portal/seat-sync implementation
- Paid-company provisioning is idempotent
- Rate limiting for public onboarding
- Backup + restore tooling for DB/Auth/Storage
- Daily database integrity checks and operational cleanup

## Automated E2E proof

Protected QA selftest `rf-qa-selftest` uses temporary real Auth users and production paths.

Latest proven run: `86837d3a`

Passed:
1. temporary internal/customer Auth users
2. real login
3. project/customer access
4. customer-created request
5. office acceptance/preparation
6. real before-photo upload through `rf-upload-evidence`
7. mandatory-photo submission
8. authenticated customer approval
9. signed PDF creation
10. execution closeout
11. database integrity check
12. cleanup of QA data

## Security

- RLS on all public RegieFlow tables
- Private schema has no USAGE/table grants for anon/authenticated
- No anon/PUBLIC execute on RegieFlow internal RPCs
- SECURITY DEFINER functions use fixed search paths
- Lifecycle state mutations are controlled by permission-checked RPCs
- Raw signature images and forensic signature metadata are hidden from customers
- Customer tenant isolation was QA-tested
- CSP, no-referrer, frame denial and noindex enabled
- Public onboarding rate-limited
- Stale approval versions cannot be approved/shared
- Only one approved signature + signed PDF per version
- Daily integrity check persisted privately for 90 days

## External launch gates still required

These are deliberately NOT bypassed in code:

1. **Stripe live configuration**
   - Set Stripe secret + webhook secret in Supabase Edge Function secrets
   - Create base + extra-seat Price IDs for Starter/Team/Business
   - Configure webhook to `rf-stripe-webhook`
   - Complete one real Stripe test checkout and billing portal test

2. **Legal operator identity**
   - Add final operator legal name, address and contact email
   - Review prepared Swiss draft Impressum/Datenschutz/AGB
   - Publish legal configuration only after review

3. **Auth production settings**
   - Enable and verify email confirmation
   - Configure production SMTP and test delivery
   - Enable leaked-password protection
   - Mark production readiness flags only after verification

4. **Backup/recovery activation**
   - Configure off-site encrypted backup credentials / destination or move production to paid managed backups
   - Run one restore drill on a non-production Supabase project
   - Mark backup recovery ready only after integrity passes

5. **Push delivery**
   - Grant browser notification permission on a real device
   - Create a real Push subscription
   - Verify one live notification delivery and deep-link

## Current product gate

`rf-billing-readiness` must return `ready: true` before public company signup can start Checkout.

The registration screen remains disabled if any of the following is missing:
- published legal texts
- Stripe prices/secrets
- email confirmation readiness
- leaked-password protection readiness
- backup/recovery readiness

Do not bypass this gate for production.
