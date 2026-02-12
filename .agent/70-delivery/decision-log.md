# Decision Log

## 2026-02-12
- Product positioned as purchase-style crowdfunding with short-video-first UX.
- Initial category focus fixed to toC creative process-heavy projects (game/hardware priority).
- Funding mode fixed to all-or-nothing for MVP.
- Support conversion canonical definition fixed as payment success only.
- Funnel event sequence fixed with five required steps.
- Platform fee set to 15 percent (temporary fixed assumption).
- Payment processing fee assigned to creator.
- Refund economics and cancellation window baseline documented.
- Pre-publication checks, stop conditions, and 72-hour appeal baseline documented.
- MVP in-scope and out-of-scope boundaries frozen for first build.
- Store policy boundary frozen: MVP support targets physical return/reward outcomes only.
- Cancellation window fixed to 48 hours.
- Accounting approach frozen to append-only journal plus derived views.
- Full event sourcing rejected as MVP accounting source of truth.
- Dispute lifecycle bookkeeping and loss allocation required from MVP start.
- Managed video platform approach chosen for MVP (Cloudflare Stream baseline).
- Upload reliability baseline frozen: resumable sessions, dedupe guard, stuck-processing failure fallback.
- Payment error UX must map processor error categories to user actions.
- Native implementation split documented: independent iOS/Android lanes with shared backend contract governance.
- API contract rules v1 added with structured errors, idempotency, and webhook-authoritative settlement.
- Event contract v1 added with required fields, source-of-truth rules, and ingestion quality SLAs.
- OpenAPI draft added for Supports/Payments/Uploads/Journal/Disputes.
- PostgreSQL schema draft added for Support, UploadSession, Dispute, and double-entry Journal.
- MCP/Skills/secrets setup checklist documented for implementation readiness.
- Payout timing defaults frozen: next-business-day execution, target settlement within 2 business days, no rolling reserve in MVP.
- Store compliance baseline frozen: support flow restricted to physical rewards with explicit pre-checkout disclosures.
- High-trust report threshold and auto-review trigger defaults frozen.
- Event contract governance defaults frozen: backend/data lead ownership and semantic versioning.
- Log retention durations frozen by class (analytics, payments/journal, moderation/disputes, security audits).
- Notification matrix defaults frozen for creator/supporter/ops role-event channels.
- Dispute SLA defaults frozen (ack/triage/resolution/escalation targets).
- Low-conversion bitrate cap thresholds and recovery window frozen.
- M1 OpenAPI draft elevated to include payout read model, moderation report intake, dispute SLA view, and support policy snapshot.
- M1 DB draft elevated with payout schedules, moderation reports, notification events, and cancellation window enforcement.
- M1 execution ticket set created for backend/data/iOS/cross-cutting implementation.

Cross-reference:
- `../00-executive/frozen-decisions.md`
- `../30-business-policy/payment-refund-policy.md`
- `../30-business-policy/dispute-and-liability-policy.md`
- `../30-business-policy/trust-and-safety-policy.md`
- `../50-data-analytics/funnel-definition.md`
- `../60-architecture/system-context.md`
- `../60-architecture/api-contract-rules.md`
- `../60-architecture/openapi-draft.yaml`
- `../60-architecture/db-schema-draft.sql`
- `./implementation-workbreakdown.md`
- `../50-data-analytics/event-contract-v1.md`
- `./mcp-skills-and-secrets-setup.md`
- `../40-mvp-spec/notification-matrix.md`
- `../50-data-analytics/logging-retention.md`
- `./m1-execution-tickets.md`

Last updated: 2026-02-12
