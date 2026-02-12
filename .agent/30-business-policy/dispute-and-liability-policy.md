# Dispute and Liability Policy

Purpose:
- Define responsibility boundaries when disputes/chargebacks happen before or after payout.

Baseline operating rules:
- Dispute lifecycle events must be recorded in accounting journal entries.
- Platform operations must preserve evidence references for each dispute.
- Loss allocation must be deterministic and policy-driven.

Responsibility boundary (MVP baseline):
- Payment disputes can initially hit platform-side balance depending on provider flow.
- Platform attempts creator-side recovery where policy allows (for example, transfer reversal).
- If recovery fails after payout, unresolved amount is recognized as platform loss per policy.

Required journaled states:
- `dispute_opened`
- `dispute_resolved_won`
- `dispute_resolved_lost`
- `recovery_attempted`
- `recovery_failed_loss_booked`

Operational controls:
- Keep dispute SLA targets documented in runbooks.
- Expose dispute status to support tooling for transparent case handling.

Last updated: 2026-02-12
