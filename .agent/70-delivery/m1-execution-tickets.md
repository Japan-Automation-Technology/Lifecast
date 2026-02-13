# M1 Execution Tickets

Goal:
- Convert M1 contract freeze into immediately actionable implementation tickets.

Status snapshot:
- Workspace scaffolding: completed.
- Backend route skeleton: completed.
- Persistent DB integration:
  - Supports: in progress (hybrid DB + fallback + idempotency + status history implemented).
  - Stripe webhook success path: in progress (signature verify + event dedupe + support/refund/dispute handlers + outbox enqueue implemented).
  - Journal list read: completed (DB-backed query implemented).
  - Payout read model: in progress (DB-backed schedule retrieval + lazy create + release write path implemented).
  - Dispute read/recovery: in progress (DB-backed read + recovery event insert implemented).
  - Moderation report intake: completed for M1 baseline (DB-backed report + trust score trigger + idempotency).
  - Upload sessions: in progress (DB-backed create/complete/get implemented).
  - Notification queue: in progress (DB enqueue + worker dequeue skeleton implemented).
  - Migration packaging: completed (`0001` + `0002` + `0003` + `0004` applied).
- Mobile/web client implementation: pending.
- Mobile UI wireflow: completed and frozen (`40-mvp-spec/ui-m1-wireflow.md`).

## Backend tickets

BE-001: Support prepare API
- Implement `POST /v1/projects/{projectId}/supports/prepare`.
- Enforce `reward_type=physical`, `cancellation_window_hours=48`, and policy snapshot payload.
- Add idempotency-key handling.
Status: completed (M1 baseline)

BE-002: Support confirm and canonical status
- Implement `POST /v1/supports/{supportId}/confirm` and `GET /v1/supports/{supportId}`.
- Keep payment finality webhook-authoritative only.
- Emit state transition history for all status changes.
Status: in progress (history implemented for prepare/confirm/succeeded; full transition matrix pending)

BE-003: Stripe webhook finalization
- Implement `POST /v1/payments/webhooks/stripe`.
- Verify signature, idempotent event handling, and dedupe by provider event ID.
- Publish `payment_succeeded` server event after successful settlement confirmation.
Status: in progress (signature cryptographic verification + event dedupe + `payment_succeeded` server emit done; provider-authenticated event bus transport pending)

BE-004: Journal write path
- Implement journal entries/lines for:
  - support_hold
  - payout_release
  - refund
  - dispute_open
  - dispute_close
  - loss_booking
- Add reconciliation check endpoint against provider totals.
Status: in progress (`support_hold/refund/dispute_open/dispute_close/loss_booking/payout_release` implemented; reconciliation endpoint added; provider settlement matching rules pending)

BE-005: Payout scheduling and status
- Implement `project_payouts` write/read logic and `GET /v1/projects/{projectId}/payouts`.
- Apply defaults:
  - execution next business day after success finalization
  - settlement target within 2 business days
  - rolling reserve disabled

BE-006: Dispute read and recovery workflow
- Implement `GET /v1/disputes/{disputeId}` and `POST /v1/disputes/{disputeId}/recovery-attempts`.
- Track SLA windows (ack/triage/resolution) and escalation flag.

BE-007: Moderation report intake
- Implement `POST /v1/projects/{projectId}/reports`.
- Persist trust-weighted reports and auto-review trigger inputs.
- Enforce unique reporter-per-project-per-day constraint.

BE-008: Upload session APIs
- Implement create/complete/get endpoints for upload sessions.
- Keep dedupe by content hash and timeout fallback handling.

BE-009: Notification event queue
- Implement notification event producer for creator/supporter/ops matrix.
- Start with push/in-app/email/ops channels and retries.
Status: in progress (worker + ops queue status API + outbox delivery attempts logging implemented; provider-specific delivery adapters pending)

## Data/analytics tickets

DA-001: Event contract validator
- Build ingestion validator for event-contract-v1 required fields.
- Route invalid events to dead-letter storage with alerting.
Status: in progress (`/v1/events/ingest` + validator + DLQ persistence implemented; alerting/p95 monitor pending)

DA-002: Funnel materialization
- Materialize 5-step funnel views and drop-off tables.
- Compute daily KPI set:
  - support conversion rate
  - average support amount
  - repeat support rate
Status: in progress (`analytics_funnel_daily` / `analytics_kpi_daily` views + read APIs implemented; dashboard layer pending)

DA-003: Cost guardrail jobs
- Build job to evaluate low-conversion bitrate rules.
- Produce action records for 540p/360p cap and recovery window.

## iOS tickets

iOS-001: Feed and support flow
- Implement feed interactions and support CTA pipeline to checkout handoff.
- Render policy snapshot in confirmation card.

iOS-002: Support status and notifications
- Poll canonical support status endpoint after return flow.
- Surface payment success/refund/campaign updates according to matrix.

iOS-003: Upload reliability UX
- Implement resumable upload with state machine parity:
  - created -> uploading -> processing -> ready | failed
- Show retry path for failed and stuck processing.

## Cross-cutting tickets

X-001: API contract tests
- Add contract tests against OpenAPI for critical endpoints.
- Include structured error mapping assertions.
Status: in progress (`app.contract.test.ts` extended with signature-invalid and refund transition assertions)

X-002: Migration packaging
- Convert `db-schema-draft.sql` sections into ordered migrations.
- Add rollback notes for non-destructive fallback.
Status: in progress (`0001_m1_contract_freeze.sql`, `0002_idempotency_and_webhooks.sql`, `0003_event_ingestion.sql`, `db:migrate`, `db:seed` wired)

X-003: Runbook baseline
- Add operational runbooks for:
  - webhook failures
  - dispute SLA breach
  - upload processing backlog
  - notification queue backlog
Status: in progress (`runbooks/` added with four baseline procedures; threshold-based alert automation pending)

Definition of done (M1):
- Core support E2E passes with webhook-authoritative success.
- Journal balances remain zero-sum for all tested scenarios.
- Payout and dispute SLA fields are queryable.
- Funnel events are complete and dashboard-ready.

Last updated: 2026-02-12
