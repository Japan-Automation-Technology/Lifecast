import { randomUUID } from "node:crypto";
import { dbPool, hasDb } from "../store/db.js";

const BATCH_SIZE = 20;
const POLL_MS = 3000;
const MAX_ATTEMPTS = 6;

const DEFAULT_RENDITIONS: Array<{ profile: "360p" | "540p" | "720p"; bitrateKbps: number }> = [
  { profile: "360p", bitrateKbps: 650 },
  { profile: "540p", bitrateKbps: 1200 },
  { profile: "720p", bitrateKbps: 2400 },
];

async function markJobFailed(client: any, row: { id: string; attempt: number }, message: string) {
  const nextAttempt = row.attempt + 1;
  const backoffSeconds = Math.min(2 ** nextAttempt, 900);
  await client.query(
    `
    update video_processing_jobs
    set status = case when $2 >= $3 then 'failed' else 'pending' end,
        attempt = $2,
        error_message = $4,
        run_after = now() + ($5 || ' seconds')::interval,
        updated_at = now()
    where id = $1
  `,
    [row.id, nextAttempt, MAX_ATTEMPTS, message, `${backoffSeconds}`],
  );
}

async function enqueueStage(client: any, videoId: string, stage: "probe" | "transcode" | "package") {
  await client.query(
    `
    insert into video_processing_jobs (id, video_id, stage, status, run_after, created_at, updated_at)
    values ($1, $2, $3, 'pending', now(), now(), now())
    on conflict do nothing
  `,
    [randomUUID(), videoId, stage],
  );
}

async function processProbe(client: any, job: { id: string; video_id: string }) {
  await client.query(
    `
    update video_assets
    set duration_ms = coalesce(duration_ms, 18000),
        width = coalesce(width, 1080),
        height = coalesce(height, 1920),
        has_audio = coalesce(has_audio, true),
        updated_at = now()
    where video_id = $1
  `,
    [job.video_id],
  );

  await enqueueStage(client, job.video_id, "transcode");
}

async function processTranscode(client: any, job: { id: string; video_id: string }) {
  for (const rendition of DEFAULT_RENDITIONS) {
    await client.query(
      `
      insert into video_renditions (video_id, profile, bitrate_kbps, codec, status, playlist_url, segment_count, created_at, updated_at)
      values ($1, $2, $3, 'h264/aac', 'ready', $4, 12, now(), now())
      on conflict (video_id, profile)
      do update set
        bitrate_kbps = excluded.bitrate_kbps,
        codec = excluded.codec,
        status = 'ready',
        playlist_url = excluded.playlist_url,
        segment_count = excluded.segment_count,
        updated_at = now()
    `,
      [job.video_id, rendition.profile, rendition.bitrateKbps, `https://cdn.lifecast.jp/v/${job.video_id}/hls/${rendition.profile}/index.m3u8`],
    );
  }

  await enqueueStage(client, job.video_id, "package");
}

async function processPackage(client: any, job: { id: string; video_id: string }) {
  const manifestUrl = `https://cdn.lifecast.jp/v/${job.video_id}/hls/master.m3u8`;
  const thumbnailUrl = `https://cdn.lifecast.jp/v/${job.video_id}/thumb.jpg`;

  await client.query(
    `
    update video_assets
    set status = 'ready',
        manifest_url = $2,
        thumbnail_url = $3,
        published_at = coalesce(published_at, now()),
        failed_reason = null,
        updated_at = now()
    where video_id = $1
  `,
    [job.video_id, manifestUrl, thumbnailUrl],
  );

  await client.query(
    `
    update video_upload_sessions
    set status = 'ready',
        completed_at = coalesce(completed_at, now()),
        updated_at = now()
    where provider_asset_id = $1
  `,
    [job.video_id],
  );

  await client.query(
    `
    insert into outbox_events (event_id, topic, payload, status, next_attempt_at)
    values ($1, 'video.ready', $2::jsonb, 'pending', now())
    on conflict (event_id) do nothing
  `,
    [
      randomUUID(),
      JSON.stringify({
        event_name: "video_ready",
        video_id: job.video_id,
        manifest_url: manifestUrl,
        occurred_at: new Date().toISOString(),
      }),
    ],
  );
}

async function processBatch() {
  if (!hasDb() || !dbPool) return 0;

  const client = await dbPool.connect();
  try {
    await client.query("begin");

    const pending = await client.query<{
      id: string;
      video_id: string;
      stage: "probe" | "transcode" | "package";
      attempt: number;
    }>(
      `
      select id, video_id, stage, attempt
      from video_processing_jobs
      where status in ('pending', 'failed') and run_after <= now()
      order by created_at asc
      limit $1
      for update skip locked
    `,
      [BATCH_SIZE],
    );

    for (const job of pending.rows) {
      try {
        await client.query(
          `
          update video_processing_jobs
          set status = 'running', started_at = now(), updated_at = now(), error_message = null
          where id = $1
        `,
          [job.id],
        );

        if (job.stage === "probe") {
          await processProbe(client, job);
        } else if (job.stage === "transcode") {
          await processTranscode(client, job);
        } else if (job.stage === "package") {
          await processPackage(client, job);
        }

        await client.query(
          `
          update video_processing_jobs
          set status = 'succeeded', completed_at = now(), updated_at = now()
          where id = $1
        `,
          [job.id],
        );
      } catch (error) {
        await markJobFailed(client, job, error instanceof Error ? error.message : "unknown video processing error");
      }
    }

    await client.query("commit");
    return pending.rowCount ?? 0;
  } catch (error) {
    await client.query("rollback");
    console.error("video-processing worker batch failed", error);
    return 0;
  } finally {
    client.release();
  }
}

async function loop() {
  while (true) {
    const processed = await processBatch();
    if (processed > 0) {
      console.log(`video-processing-worker processed=${processed}`);
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
}

void loop();
