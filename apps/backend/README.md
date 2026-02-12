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
- Shapes and enums follow `packages/contracts/openapi/openapi.yaml`.
- Ready for BE-001..BE-009 iterative implementation.

Commands:
- `pnpm dev:backend`
- `pnpm dev:backend:worker:notifications`
- `pnpm typecheck:backend`

Next step:
- Expand persistent adapters for payouts/disputes/moderation/notifications and remove fallback-only paths.
