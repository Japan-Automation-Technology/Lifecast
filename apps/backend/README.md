# LifeCast Backend (M1 Skeleton)

Fastify + TypeScript API skeleton aligned to M1 contract freeze.

Implemented route groups:
- Supports
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
- Adds Stripe webhook dedupe by provider event ID.
- Shapes and enums follow `packages/contracts/openapi/openapi.yaml`.
- Ready for BE-001..BE-009 iterative implementation.

Commands:
- `pnpm dev:backend`
- `pnpm dev:backend:worker:notifications`
- `pnpm typecheck:backend`
- `pnpm test:backend`
- `pnpm db:migrate:backend`
- `pnpm db:seed:backend`

Next step:
- Complete journal entry coverage (`payout_release` / `refund` / `dispute_*` / `loss_booking`).
- Wire Stripe signature verification with secret-based validation.
