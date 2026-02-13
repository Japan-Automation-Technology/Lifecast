# Dispute SLA Breach

Trigger conditions:
- Dispute `acknowledgement_due_at`, `triage_due_at`, or `resolution_due_at` exceeded.

Immediate checks:
- Query affected disputes via `GET /v1/disputes/{disputeId}`.
- Confirm related `dispute_events` exist for recent activity.

Containment:
- Assign owner and set manual priority to oldest overdue disputes first.
- Freeze related payout release for affected projects until triage is complete.

Recovery:
- Submit `recovery-attempts` entries for financial mitigation.
- Ensure final state transition (`won` or `lost`) is recorded and journal entries are balanced.

Post-incident:
- Record SLA misses count and mean overdue duration.
- Tune escalation thresholds and alerting windows.
