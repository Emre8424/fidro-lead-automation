# FIDRO Lead Automation — Compliance & Operations

This repository contains the operator UI for FIDRO's WhatsApp appointment-setting workflow.

## Scope

The WhatsApp automation is limited to:
- first contact to eligible giveaway leads,
- explaining the free and non-binding analysis,
- appointment type/date/time collection,
- customer address only when the appointment is at the customer's location,
- customer email for appointment confirmation,
- explicit appointment confirmation,
- human handoff when the reply is unclear or outside the supported flow.

It is **not** intended to provide financial, insurance, tax, investment or pension advice over WhatsApp.

## Mandatory WhatsApp consent gate

A lead may only receive a business-initiated WhatsApp first contact when all of the following are true:
- the lead is not in Arilla phase `Nicht brauchbar`,
- the lead is at least 18 years old when a birth date is available,
- lawful acquisition is confirmed,
- an explicit WhatsApp opt-in is documented,
- the evidence records the consent timestamp, source and wording,
- the wording explicitly identifies FIDRO and WhatsApp,
- the lead has not opted out,
- global automation is active,
- Meta production readiness checks are green,
- the approved first-contact template is available.

The backend enforces these checks again immediately before sending. UI state alone is never sufficient.

## First-contact transparency

The production first-contact template:
- identifies Emre and FIDRO,
- refers to the giveaway context,
- asks permission before continuing,
- tells the recipient how to opt out with STOP,
- links to FIDRO's privacy notice.

## Opt-out

Opt-out requests stop automation. Manual opt-outs and WhatsApp opt-outs are logged. A previous opt-in is not treated as active after an opt-out.

## Sensitive data

The automation must not request financial documents, insurance policies, health data, identity documents, account credentials or similar sensitive material through WhatsApp. On human handoff the customer is explicitly warned not to send such material in the chat.

## Human handoff

Unknown or ambiguous replies are not interpreted as financial advice. They are escalated to a human operator and recorded in the audit log.

## Appointment rules

Appointments are restricted server-side to:
- Monday–Saturday,
- start times from 07:00 through 19:00 Europe/Zurich,
- 45 or 60 minutes,
- Büro Brüttisellen, Beim Kunden, or Microsoft Teams,
- full address required for Beim Kunden,
- customer email required,
- explicit customer confirmation before booking.

A Teams link is not generated automatically.

## Auditability

The system records relevant events including:
- WhatsApp opt-in evidence,
- manual and customer opt-outs,
- first-contact sends,
- human handoffs,
- automation errors,
- appointment confirmations,
- manual email-send confirmations,
- operator-key rotation.

## Security controls

- Direct database privileges for `anon` and `authenticated` are revoked.
- RLS remains enabled on application tables.
- Operator actions go through authenticated Edge Functions.
- Browser access is restricted by CORS to the GitHub Pages operator UI.
- Webhook POST requests require valid Meta HMAC signatures.
- Duplicate inbound provider message IDs are rejected.
- Duplicate active first-contact jobs are prevented.
- Global pause is fail-closed.
- Legacy one-time setup/publish helper functions are disabled.
- The operator access key must be rotated before production activation.

## Production gate

Do not activate production unless every readiness check is green and a real production test has completed successfully.

The remaining external dependencies are intentionally fail-closed: Meta template approval and operator-key rotation cannot be bypassed by the UI.

## Legal / governance note

These controls are designed to support lawful and auditable operation. They are not a regulatory certification. FIDRO remains responsible for its legal basis, privacy notices, internal authorisation, retention policy, and the accuracy of consent evidence entered into the system.
