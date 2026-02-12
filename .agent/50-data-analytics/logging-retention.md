# Logging and Retention

Logging classes:
- Product analytics events.
- Payment lifecycle logs.
- Moderation and policy enforcement logs.

Minimum logging principles:
- Keep event IDs for deduplication.
- Keep audit trail of moderation actions and appeals.
- Preserve evidence references for disputes.

Retention policy:
- Product analytics events: 13 months.
- Payment lifecycle and accounting journal logs: 7 years.
- Moderation/dispute evidence logs: 5 years.
- Security and access audit logs: 1 year hot + 2 years cold archive.
- Deletion and retention exceptions must be approved and recorded in decision log.

Last updated: 2026-02-12
