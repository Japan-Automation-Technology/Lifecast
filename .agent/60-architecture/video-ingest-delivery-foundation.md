# Video Ingest & Delivery Foundation (M1.5 Start)

Purpose:
- Start video upload/viewing implementation early, independently from support/payment tracks.
- Keep UX-first behavior: user does not wait for transcoding completion.

## 1) Design principles (from referenced papers)

1. Upload should be asynchronous and publish-first.
- Create post/video record immediately after upload completion event.
- Keep status as provisional (`processing`) and switch to `ready` when packaging completes.

2. Delivery should be manifest + segments.
- Store source object once.
- Generate ABR renditions and package to HLS/CMAF first.
- Player fetches manifest (`.m3u8`) and adaptive segments.

3. Cost must be controlled by policy, not ad-hoc ops.
- Multi-layer cache strategy (edge > regional > origin fallback).
- Prefetch count caps and bitrate ceilings from day 1.
- Prioritize high-probability videos for higher quality and pre-cache.

4. Playback UX is startup + continuity.
- Fetch initial segment fast, then ABR adapt aggressively.
- Synchronize feed scroll state with player lifecycle.

Inference note:
- We apply these principles to Lifecast even though our current scale is much smaller than ByteDance.

## 2) Source-backed guidance used

- ByteDance playback E2E paper (short video, publishing/upload, adaptive priority, pre-caching):
  - https://arxiv.org/html/2410.17073v1
- ByteDance PCDN+ paper (resource management and CDN cost reduction):
  - /Users/takeshi/Downloads/atc24-zhang-rui-xiao.pdf
- Monolith paper (real-time recommendation/training architecture cues):
  - /Users/takeshi/Downloads/2209.07663v2.pdf

## 3) Target architecture for Lifecast

1. Ingest API layer
- `POST /v1/videos/uploads` (already exists): create upload session.
- `POST /v1/videos/uploads/{id}/parts` (new): register uploaded part ETags/checksums.
- `POST /v1/videos/uploads/{id}/complete` (extend): finalize multipart, emit `video_upload_completed`.

2. Origin storage
- Bucket layout:
  - `raw/{creator_id}/{video_id}/source.{ext}`
  - `packaged/{video_id}/hls/master.m3u8`
  - `packaged/{video_id}/hls/{rendition}/index.m3u8`
  - `packaged/{video_id}/hls/{rendition}/seg-*.m4s`

3. Async processing pipeline
- Outbox event: `video_upload_completed`.
- Worker stages:
  - `probe` (duration/resolution/audio check)
  - `transcode` (multiple ladders)
  - `package` (HLS/CMAF)
  - `publish_ready` (set video status `ready`)
- Failure path sets `failed` with reason and retryable flag.

4. Playback API layer
- `GET /v1/feed/videos` returns metadata + `playback_manifest_url` when ready.
- `GET /v1/videos/{id}` returns canonical playback status.
- If not ready, return placeholder payload and polling hints.

5. Client playback strategy (iOS first)
- Prefetch N+2 videos (configurable cap, default 2).
- Preload first segment only for next video (fast start).
- ABR fallback quickly on weak network.
- On vertical swipe, previous player is paused and next starts immediately.

## 4) Minimal DB additions (next migration)

1. `video_assets`
- `video_id` (pk), `creator_user_id`, `upload_session_id`, `status` (`processing|ready|failed`)
- `origin_object_key`, `duration_ms`, `width`, `height`, `has_audio`
- `manifest_url`, `thumbnail_url`, `published_at`, `failed_reason`

2. `video_renditions`
- `id` (pk), `video_id` (fk), `profile` (`360p|540p|720p`), `bitrate_kbps`
- `playlist_url`, `segment_count`, `codec`, `status`

3. `video_processing_jobs`
- `id`, `video_id`, `stage`, `status`, `attempt`, `error_message`, `run_after`

4. `video_delivery_policy`
- `video_id`, `max_bitrate_kbps`, `prefetch_priority`, `cache_tier_hint`

## 5) Guardrails to implement immediately

1. Prefetch cap
- Max preload videos per session: 2 (M1 default).

2. Bitrate cap policy
- Default ceiling: 720p for feed autoplay.
- Under low conversion cohorts, allow policy downgrade to 540p.

3. Processing priority
- Introduce `video_value_score` (initial heuristic):
  - creator follower count
  - early watch-through
  - early support-click rate
- High-score videos enter priority queue for faster transcode and pre-cache.

4. Retry and timeout
- `processing` hard timeout: 30 min (already partially reflected in upload session).
- On timeout, auto-fail + one-click reprocess action in ops.

## 6) Immediate implementation slice (recommended this week)

1. Backend
- Add `video_assets` + `video_renditions` + `video_processing_jobs` migration.
- Emit outbox event on upload complete.
- Add background `video-processing` worker scaffold.
- Extend `GET /v1/videos/uploads/{id}` to include derived `video_id` linkage.

2. iOS
- Add Upload state machine view:
  - `created -> uploading -> processing -> ready|failed`
- Add feed model support for `processing` placeholder cells.

3. Ops/analytics
- Log pipeline stages with latency:
  - ingest_to_complete_ms
  - complete_to_ready_ms
  - first_play_startup_ms

## 7) Non-goals for this slice

- Live streaming
- DASH dual-packaging (HLS first)
- Full recommendation model integration
- P2P/PCDN implementation (only policy hooks for future)

Last updated: 2026-02-13
