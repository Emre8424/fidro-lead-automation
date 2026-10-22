# RegieFlow Production Setup

This file lists the remaining provider/platform configuration required before public launch.

RegieFlow intentionally refuses public company signup until `rf-billing-readiness` returns `ready: true`.

## 1. Stripe

Create recurring monthly prices for each base plan and for one additional internal profile:

| Plan | Base / month | Included internal profiles | Extra profile / month |
| --- | ---: | ---: | ---: |
| Starter | CHF 29 | 3 | CHF 6 |
| Team | CHF 59 | 10 | CHF 5 |
| Business | CHF 199 | 50 | CHF 4 |

Store the Stripe Price IDs in `public.rf_plan_catalog`:

- `stripe_price_id`: base subscription Price
- `stripe_extra_price_id`: per-extra-profile recurring Price

Required Supabase Edge Function secrets:

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`

Stripe webhook endpoint:

`https://kiihabzzepoehsokglzq.supabase.co/functions/v1/rf-stripe-webhook`

Required events:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.expired`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`

After configuration, verify:

- public Checkout redirects to Stripe
- paid Checkout marks the signup intent paid
- post-payment signup creates/authenticates the Owner
- exactly one company is provisioned
- Billing Portal opens
- subscription cancellation makes the company operationally read-only while archive + billing remain accessible
- adding/deactivating internal profiles updates the extra-seat subscription item

## 2. Legal operator identity

Drafts already exist privately in `regieflow_private.legal_config`.

Before publishing, replace every placeholder and review the texts:

- operator legal name
- full postal address
- operator/privacy contact email
- representative/function if applicable
- Impressum
- Datenschutzerklärung
- AGB

Only then set `published=true`.

Do not publish placeholder legal text.

## 3. Supabase Auth production settings

In Supabase Auth:

- require email confirmation for public owner accounts
- configure a production SMTP provider
- test that confirmation and password-reset emails arrive
- enable leaked-password protection
- confirm redirect URL `https://regieflow.pages.dev/` is allowed

Only after real tests update the private production readiness flags:

- `email_confirmation_ready=true`
- `leaked_password_protection_ready=true`

## 4. Backup / recovery

Source-controlled tooling:

- `regieflow/ops/backup-regieflow.sh`
- `regieflow/ops/restore-regieflow.sh`
- `regieflow/ops/export-supabase-assets.mjs`
- `regieflow/ops/restore-supabase-assets.mjs`
- `regieflow/ops/README.md`
- `regieflow/ops/github-actions-backup.yml`

The backup contains RegieFlow DB rows, Auth restore records, Storage files and checksums, and is encrypted.

Required backup secrets/configuration:

- database connection URL with backup permissions
- Supabase URL
- service-role key
- strong backup passphrase
- secure off-site destination

Before public launch:

1. create an encrypted backup
2. restore it into a disposable non-production Supabase project
3. run `rf_system_integrity_check()`
4. verify at least one signed PDF and image can be opened
5. only then set `backup_recovery_ready=true`

## 5. Browser Push

Backend and VAPID/private hook are already implemented and tested.

Final device test:

1. log into RegieFlow in a supported real browser/device
2. enable Push
3. verify a row appears in `rf_push_subscriptions`
4. trigger a Regie notification
5. verify the OS/browser notification arrives
6. click it and confirm the exact Regie opens

## 6. Final readiness

Call:

`GET https://kiihabzzepoehsokglzq.supabase.co/functions/v1/rf-billing-readiness`

Public registration may be opened only when the response contains:

`"ready": true`

Current hard gates:

- legalReady
- priceReady
- secretsReady
- emailReady
- leakedPasswordReady
- backupReady

## 7. Final smoke test

Before announcing the product:

1. Login as Owner
2. Create/edit project
3. Add customer + signing right
4. Create Regie with before photo
5. Edit sent Regie and confirm new version is created
6. Submit using Büro review
7. Submit another using Direct-to-customer
8. Approve once with account and once with secure link
9. Open immutable PDF
10. Start work
11. add optional after photo
12. mark work complete
13. enter Rapportnummer and close
14. open customer archive
15. customer creates a new request
16. office accepts and prepares it
17. verify notifications/deep links
18. verify Push
19. verify Billing Portal
20. run `rf_system_integrity_check()`

The protected `rf-qa-selftest` already automates the core technical path with temporary real Auth users and removes its QA data after a successful run.
