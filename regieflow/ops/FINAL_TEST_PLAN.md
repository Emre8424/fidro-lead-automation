# RegieFlow final launch test plan

Run this after the remaining external production settings are configured.

## 1. Automated smoke test

```bash
node regieflow/ops/smoke-test.mjs
```

Expected:
- frontend 200
- CSP/security headers pass
- API health passes database/storage/integrity
- billing readiness becomes `ready: true` only when every production gate is configured

## 2. Internal company flow

1. Sign in as Primary Owner.
2. Create an internal role with only `regies.create` + view permissions.
3. Create a test internal user with that role.
4. Confirm temporary password must be replaced.
5. Confirm user cannot access Owner/billing/role administration.
6. Create a project and customer contact.
7. Set project to **Mit Büroprüfung**.
8. Monteur creates Regie with description, estimate and before photo.
9. Submit.
10. Büro approves.
11. Create secure customer approval link.
12. Customer approves and signs.
13. Open immutable PDF.
14. Start execution.
15. Add optional after photo.
16. Mark work complete.
17. Add Rapportnummer and close.
18. Confirm archive is read-only.

Repeat once with **Direkt zum Kunden**.

## 3. Revision integrity

1. Submit version 1.
2. Create version 2 before customer approval.
3. Confirm old secure links are invalid.
4. Confirm version 1 cannot be reviewed/signed.
5. Sign version 2.
6. Confirm version 1 and version 2 history/PDF labels remain coherent.

## 4. Customer account flow

1. Invite a customer account.
2. Accept invitation in private browser.
3. Confirm only assigned project is visible.
4. Create a customer request with optional request photo.
5. Büro accepts and assigns an authorized Regie creator.
6. Prepare version 1.
7. Add mandatory before photo.
8. Submit and approve.
9. Confirm customer receives notifications and can open the final archive PDF.

## 5. Notification / Push

1. Enable Push in one internal browser and one customer browser.
2. Trigger:
   - customer request,
   - awaiting customer approval,
   - customer approval,
   - comment,
   - closed Regie.
3. Confirm push opens the exact Regie deep link.
4. Confirm browser without permission still receives in-app notifications.

## 6. Permission abuse tests

Confirm:
- customer cannot read another project/company;
- customer cannot mutate Regie lifecycle directly;
- non-reviewer cannot approve customer requests or office review;
- non-project-manager cannot edit projects/customers;
- delegated admin cannot change own role;
- Primary Owner cannot deactivate self or lose ownership accidentally;
- raw signature image/evidence is unavailable to customers;
- closed Regie comments/evidence are immutable.

## 7. Billing / Stripe

Use Stripe test mode first.

1. Starter checkout.
2. Confirm email.
3. Complete paid signup.
4. Confirm company appears with correct plan/seats.
5. Add seats below allowance.
6. Add seat above allowance and confirm Stripe extra-seat quantity.
7. Remove extra seat and confirm quantity changes.
8. Open billing portal.
9. Change/cancel subscription and confirm app becomes read-only when appropriate.
10. Confirm archive/PDF remains readable while subscription is inactive.
11. Confirm webhook retries are idempotent.

Repeat a checkout for Team and Business pricing.

## 8. Legal / Auth / Recovery

Before public registration is enabled:
- published Impressum, Datenschutz and AGB are correct;
- Supabase email confirmation is enabled;
- custom/production SMTP is tested;
- leaked-password protection is enabled;
- backup job has completed successfully;
- one restore drill has passed;
- `rf-billing-readiness` returns `ready: true`;
- `rf_system_integrity_check()` returns `ok: true`.

## 9. Launch cleanup

- remove development/test customers and Regien only after explicit approval;
- point final domain to production frontend;
- update Stripe success/cancel URLs/webhook to final domain if domain changes;
- remove noindex/robots block only when public indexing is desired;
- run smoke + E2E one last time.
