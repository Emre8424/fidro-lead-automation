# WhatsApp Opt-in Form Specification

Use this specification for future FIDRO giveaway / campaign forms if leads may later receive business-initiated WhatsApp messages.

## UI

Use a **separate, unticked checkbox** for WhatsApp communication. Do not infer WhatsApp permission merely from:
- entering the giveaway,
- providing a mobile number,
- accepting general website terms,
- linking to the privacy policy.

Recommended label:

> Ich bin einverstanden, dass die FIDRO GmbH mich im Zusammenhang mit dem Gewinnspiel sowie zu Beratungs- und Marketingzwecken per WhatsApp kontaktiert. Ich kann diese Einwilligung jederzeit widerrufen, z.B. mit STOP. Datenschutzerklärung: https://fidro.ch/datenschutz

## Evidence to retain

For each consent record, retain:
- lead/contact identifier,
- phone number used for the consent,
- exact checkbox wording/version,
- timestamp,
- source/form/campaign,
- affirmative checkbox state,
- privacy-notice version or URL shown at the time.

The production automation maps those elements to:
- `lawful_acquisition_confirmed`,
- `whatsapp_opt_in_confirmed`,
- `whatsapp_opt_in_at`,
- `whatsapp_opt_in_source`,
- `whatsapp_opt_in_text`.

## Revocation

The customer can revoke consent at any time. A WhatsApp STOP/opt-out:
- sets the lead to opted out,
- clears the active WhatsApp opt-in flag,
- writes a hashed phone suppression entry,
- cancels pending follow-ups,
- prevents re-import from silently re-enabling outreach.

## Historical leads

Do **not** backfill WhatsApp consent merely because a historical lead entered a FIDRO giveaway or provided a phone number. Use the exact wording that was actually displayed to that person. If no suitable WhatsApp consent evidence exists, the automation must not initiate a WhatsApp marketing conversation with that lead.
