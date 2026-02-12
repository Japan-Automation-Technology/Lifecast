# Non-Functional Requirements

- Event consistency: funnel event definitions must be identical across clients/backend.
- Auditability: moderation and payout/refund decisions need durable logs.
- Reliability: payment success/failure callbacks must be idempotent.
- Transparency: policy-critical terms must be visible before payment completion.
- Performance target: feed interaction should feel immediate under typical mobile network conditions.

Last updated: 2026-02-12
