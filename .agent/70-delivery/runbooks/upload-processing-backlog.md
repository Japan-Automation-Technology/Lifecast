# Upload Processing Backlog

Trigger conditions:
- Large increase in `video_upload_sessions` with status `processing`.
- Processing deadline breaches without transitions to `ready` or `failed`.

Immediate checks:
- Count pending sessions by age bucket.
- Verify provider-side processing status (video platform dashboard/API).

Containment:
- Stop accepting large uploads temporarily if backlog is critical.
- Prioritize oldest sessions for retry/fail transition.

Recovery:
- Mark stale sessions to `failed` and expose retry path in client.
- Re-run ingestion/processing jobs after provider health restoration.

Post-incident:
- Record backlog peak and time to recover.
- Adjust upload caps and processing watchdog thresholds.
