# Non-Functional Requirements

- Event consistency: funnel event definitions must be identical across clients/backend.
- Auditability: moderation and payout/refund decisions need durable logs.
- Reliability: payment success/failure callbacks must be idempotent.
- Transparency: policy-critical terms must be visible before payment completion.
- Performance target: feed interaction should feel immediate under typical mobile network conditions.
- Cost guardrails: monitor delivered minutes and stored minutes and apply policy-based bitrate caps for low-conversion content.
- Upload robustness: resumable upload, timeout fallback to failed state, and duplicate ingest prevention are required.
- Low-conversion bitrate policy defaults:
  - If support conversion < 0.30% after >= 1,000 impressions, cap feed playback at 540p.
  - If support conversion < 0.10% after >= 3,000 impressions, cap feed playback at 360p.
  - Recover original bitrate cap only after conversion rises above 0.30% for 48 continuous hours.

Last updated: 2026-02-12
