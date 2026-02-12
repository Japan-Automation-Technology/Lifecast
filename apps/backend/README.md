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
- Uses in-memory store only (no DB wiring yet).
- Shapes and enums follow `packages/contracts/openapi/openapi.yaml`.
- Ready for BE-001..BE-009 iterative implementation.

Commands:
- `pnpm dev:backend`
- `pnpm typecheck:backend`

Next step:
- Replace in-memory store with persistence adapters (`support_transactions`, `project_payouts`, `moderation_reports`, `journal_entries`).
