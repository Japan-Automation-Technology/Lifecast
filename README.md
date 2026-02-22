# Lifecast Workspace

Monorepo baseline for M1 contract-freeze implementation.

## Workspaces
- `apps/backend`: API implementation from M1 OpenAPI/DB contracts.
- `apps/ios`: iOS implementation workspace (native Swift project placeholder).
- `apps/android`: Android implementation workspace (native Kotlin project placeholder).
- `apps/web`: Web implementation workspace (campaign/admin surface placeholder).
- `packages/contracts`: shared API/event contracts for all clients.

## Quick start
- Install: `pnpm install`
- Run backend: `pnpm dev:backend`
- Typecheck backend: `pnpm typecheck:backend`

## Source of truth
- API contract: `.agent/60-architecture/openapi-draft.yaml`
- DB contract: `.agent/60-architecture/db-schema-draft.sql`
- Event contract: `.agent/50-data-analytics/event-contract-v1.md`
