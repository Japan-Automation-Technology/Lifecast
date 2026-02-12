# System Context

Primary surfaces:
- Mobile clients for viewers/supporters and creators.
- Backend APIs for feed, projects, plans, social, support lifecycle, moderation.
- External payment provider integration with Apple Pay support.
- Managed video provider integration (Cloudflare Stream baseline for MVP).

Critical subsystems:
- Video ingestion and playback.
- Project and plan management.
- Payment orchestration and webhook reconciliation.
- Accounting journal and settlement views.
- Event collection and analytics processing.
- Trust and moderation operations.

Video reliability baseline:
- Resumable/chunked upload sessions.
- Upload state machine:
  - created -> uploading -> processing -> ready | failed
- Processing timeout handling that transitions stuck jobs to failed and enables retry.
- Duplicate ingest guard using upload session identity plus content hash.

Last updated: 2026-02-12
