# Event Contract v1

Purpose:
- Define implementation-level event contract for iOS, Android, and backend ingestion parity.

General rules:
- Required fields for every event:
  - `event_name`
  - `event_id` (UUID)
  - `event_time` (UTC)
  - `user_id` or `anonymous_id`
  - `session_id`
  - `client_platform` (`ios` or `android` or `server`)
  - `app_version`
- `event_id` is used for deduplication.
- Missing required fields cause ingestion rejection to dead-letter queue.

Governance defaults:
- Contract owner: Backend/Data lead (single owner model for MVP).
- Change control: semantic versioning (`major.minor.patch`).
- Backward-compatible additions require minor bump and decision-log entry.
- Breaking changes require major bump, migration plan, and dual-write period.

Canonical funnel events:
1. `video_watch_completed`
2. `support_button_tapped`
3. `plan_selected`
4. `checkout_page_reached`
5. `payment_succeeded`

Event-specific required attributes:
- `video_play_started`
  - `video_id`
- `video_watch_progress`
  - `video_id`
  - `watch_duration_ms`
  - `video_duration_ms`
- `video_watch_completed`
  - `video_id`
  - `project_id`
  - `watch_duration_ms`
  - `video_duration_ms`
- `support_button_tapped`
  - `video_id`
  - `project_id`
- `plan_selected`
  - `project_id`
  - `plan_id`
  - `plan_price_minor`
  - `currency`
- `checkout_page_reached`
  - `project_id`
  - `plan_id`
  - `checkout_session_id`
- `payment_succeeded`
  - `project_id`
  - `plan_id`
  - `support_id`
  - `payment_provider`
  - `amount_minor`
  - `currency`

Authority and source rules:
- `payment_succeeded` is server-emitted after webhook verification.
- Client is allowed to emit intent/progress events only.
- Backend may enrich client events with trusted metadata in warehouse.

Quality SLAs:
- Event delivery success rate target: >= 99.5 percent daily.
- Late-arrival threshold for funnel reporting: <= 15 minutes p95.
- Schema mismatch alert should fire within 5 minutes of first invalid event burst.

Last updated: 2026-02-21
