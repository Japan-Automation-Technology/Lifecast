# Event Taxonomy

Canonical funnel events:
- `video_watch_completed`
- `support_button_tapped`
- `plan_selected`
- `checkout_page_reached`
- `payment_succeeded`

Additional watch-quality events:
- `video_play_started` (non-completion play count source)
- `video_watch_progress` (watch-time capture when not completed)

Minimum event payload guidance:
- `user_id` (or anonymous/session identifier where applicable)
- `project_id`
- `video_id` (if applicable)
- `plan_id` (for plan and checkout events)
- `timestamp`
- `client_platform`
- `session_id`

Integrity rules:
- Event names are immutable once released.
- Any schema change requires versioning note in decision log.
- Backend should validate critical event shape for analytics reliability.

Last updated: 2026-02-21
