# Notification Matrix (MVP)

Role-based minimum notification set:

Creator notifications:
- New support succeeded:
  - channel: push + in-app
  - timing: immediate
- Campaign reached goal:
  - channel: push + in-app + email
  - timing: immediate
- Campaign failed at deadline:
  - channel: push + in-app + email
  - timing: immediate
- Project report/escalation created:
  - channel: in-app + email
  - timing: immediate
- Appeal decision posted:
  - channel: in-app + email
  - timing: immediate

Supporter notifications:
- Support payment succeeded:
  - channel: push + in-app + email receipt
  - timing: immediate
- Refund completed:
  - channel: push + in-app + email
  - timing: immediate
- Campaign succeeded:
  - channel: in-app
  - timing: within 15 minutes
- Campaign failed and refund initiated:
  - channel: push + in-app + email
  - timing: immediate
- Major project update posted:
  - channel: in-app
  - timing: within 15 minutes

System/ops notifications:
- Payment webhook failure burst:
  - channel: pager/ops
  - timing: immediate
- Event ingestion schema mismatch:
  - channel: pager/ops
  - timing: immediate
- Upload processing stuck threshold exceeded:
  - channel: pager/ops
  - timing: immediate

Last updated: 2026-02-12
