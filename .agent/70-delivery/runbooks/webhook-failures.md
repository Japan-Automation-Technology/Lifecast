# Webhook Failures

Trigger conditions:
- Stripe webhook endpoint returns non-2xx.
- `processed_webhooks` growth stalls while Stripe dashboard shows delivered events.

Immediate checks:
- Verify backend health: `GET /health`.
- Verify signature secret alignment: `LIFECAST_STRIPE_WEBHOOK_SECRET`.
- Inspect app logs for `VALIDATION_ERROR` or signature mismatch.

Containment:
- Keep webhook endpoint live; do not disable signature checks.
- If secret drift is confirmed, rotate to current Stripe endpoint secret and restart backend.

Recovery:
- Re-send failed events from Stripe dashboard (or Stripe CLI replay).
- Confirm `processed_webhooks` rows increase and support statuses recover.
- Validate `payment_succeeded` events appear in `analytics_events`.

Post-incident:
- Document root cause (secret drift, payload mismatch, deployment regression).
- Add regression test for discovered failure pattern.
