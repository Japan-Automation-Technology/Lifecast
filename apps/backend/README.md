# LifeCast Backend (M1 Skeleton)

Fastify + TypeScript API skeleton aligned to M1 contract freeze.

Implemented route groups:
- Supports
- Events ingestion
- Analytics (daily funnel/KPI read)
- Payments (webhook entry)
- Uploads
- Journal (read stub)
- Disputes
- Payouts
- Moderation reports

Current state:
- Uses hybrid store:
  - Postgres-first for supports/payments webhook success/journal reads.
  - Postgres-first for payouts/disputes/moderation reports/upload sessions.
  - In-memory fallback when DB is unavailable or bootstrap data is missing.
- Adds idempotency handling for POST APIs via `Idempotency-Key` (DB-backed when available).
- Adds Stripe webhook dedupe by provider event ID and signature verification via `LIFECAST_STRIPE_WEBHOOK_SECRET`.
- Adds journal write handlers for `support_hold`, `refund`, `dispute_open`, `dispute_close`, `loss_booking`, and `payout_release`.
- Adds reconciliation API baseline at `GET /v1/journal/reconciliation`.
- Adds event ingestion API (`POST /v1/events/ingest`) with contract validation + DLQ persistence.
- Emits server-side `payment_succeeded` event after webhook-authoritative settlement.
- Adds outbox transport baseline (`outbox_events` + worker) for server-emitted events.
- Adds daily analytics views (`analytics_funnel_daily`, `analytics_kpi_daily`) and read APIs.
- Shapes and enums follow `packages/contracts/openapi/openapi.yaml`.
- Ready for BE-001..BE-009 iterative implementation.

Commands:
- `pnpm dev:backend`
- `pnpm dev:backend:worker:notifications`
- `pnpm dev:backend:worker:outbox`
- `pnpm typecheck:backend`
- `pnpm test:backend`
- `pnpm db:migrate:backend`
- `pnpm db:seed:backend`
- `pnpm smoke:payments:backend`

Next step:
- Replace outbox placeholder delivery with provider-authenticated bus publish.
- Harden reconciliation rules against provider settlement exports and chargeback lifecycle edge cases.
