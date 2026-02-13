# Notification and Outbox Backlog

Trigger conditions:
- `/v1/ops/queues` shows sustained `pending` growth.
- `failed` counts increase for `notification_events` or `outbox_events`.

Immediate checks:
- Confirm workers are running:
  - `dev:backend:worker:notifications`
  - `dev:backend:worker:outbox`
- Inspect latest `outbox_delivery_attempts` failures.

Containment:
- If external transport is down, keep retry loop active and avoid manual mass requeue.
- Raise retry backoff only if downstream rate-limits are causing repeated failures.

Recovery:
- Restore downstream endpoint or credentials (`LIFECAST_OUTBOX_WEBHOOK_URL`, bearer token).
- Validate queue drain trend via `/v1/ops/queues`.

Post-incident:
- Capture failure class (network, auth, 4xx schema, 5xx downstream).
- Add targeted retry policy and alert thresholds per failure class.
