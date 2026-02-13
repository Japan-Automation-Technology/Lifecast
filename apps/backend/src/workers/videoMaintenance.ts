import { dbPool, hasDb } from "../store/db.js";

const POLL_MS = 5000;
const DELETE_BATCH_SIZE = 20;
const THUMBNAIL_BATCH_SIZE = 20;
const DELETE_MAX_ATTEMPTS = 8;

async function fetchCloudflareVideoDetails(uid: string): Promise<{ thumbnail?: string; playbackUrl?: string } | null> {
  const accountId = process.env.CF_ACCOUNT_ID;
  const token = process.env.CF_STREAM_TOKEN;
  if (!accountId || !token) return null;

  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/${uid}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok || !payload?.success || !payload?.result) return null;

  const result = payload.result;
  return {
    thumbnail: typeof result.thumbnail === "string" ? result.thumbnail : undefined,
    playbackUrl: typeof result.playback?.hls === "string" ? result.playback.hls : undefined,
  };
}

async function deleteCloudflareVideo(uid: string): Promise<boolean> {
  const accountId = process.env.CF_ACCOUNT_ID;
  const token = process.env.CF_STREAM_TOKEN;
  if (!accountId || !token) return false;

  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/${uid}`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });
  const payload = await response.json().catch(() => null);
  return Boolean(response.ok && payload?.success);
}

async function processDeleteJobs() {
  if (!hasDb() || !dbPool) return 0;
  const client = await dbPool.connect();
  try {
    await client.query("begin");
    const jobs = await client.query<{
      id: string;
      attempt: number;
      provider_upload_id: string;
    }>(
      `
      select id, attempt, provider_upload_id
      from video_delete_jobs
      where status = 'pending'
        and next_run_at <= now()
      order by created_at asc
      limit $1
      for update skip locked
    `,
      [DELETE_BATCH_SIZE],
    );

    for (const job of jobs.rows) {
      await client.query(
        `
        update video_delete_jobs
        set status = 'running',
            updated_at = now(),
            error_message = null
        where id = $1
      `,
        [job.id],
      );

      const ok = await deleteCloudflareVideo(job.provider_upload_id);
      if (ok) {
        await client.query(
          `
          update video_delete_jobs
          set status = 'succeeded',
              completed_at = now(),
              updated_at = now()
          where id = $1
        `,
          [job.id],
        );
        continue;
      }

      const nextAttempt = job.attempt + 1;
      const backoffSeconds = Math.min(2 ** nextAttempt, 1800);
      await client.query(
        `
        update video_delete_jobs
        set status = case when $2::int >= $3::int then 'failed' else 'pending' end,
            attempt = $2::int,
            error_message = 'cloudflare delete failed',
            next_run_at = now() + (($4::int)::text || ' seconds')::interval,
            updated_at = now()
        where id = $1
      `,
        [job.id, nextAttempt, DELETE_MAX_ATTEMPTS, `${backoffSeconds}`],
      );
    }

    await client.query("commit");
    return jobs.rowCount ?? 0;
  } catch (error) {
    await client.query("rollback");
    console.error("video-maintenance delete job batch failed", error);
    return 0;
  } finally {
    client.release();
  }
}

async function processThumbnailBackfill() {
  if (!hasDb() || !dbPool) return 0;
  const client = await dbPool.connect();
  try {
    const rows = await client.query<{
      upload_session_id: string;
      provider_upload_id: string;
    }>(
      `
      select va.upload_session_id, vus.provider_upload_id
      from video_assets va
      join video_upload_sessions vus on vus.id = va.upload_session_id
      where va.status = 'ready'
        and va.thumbnail_url is null
        and vus.provider_upload_id is not null
      order by va.created_at desc
      limit $1
    `,
      [THUMBNAIL_BATCH_SIZE],
    );

    let processed = 0;
    for (const row of rows.rows) {
      const details = await fetchCloudflareVideoDetails(row.provider_upload_id);
      if (!details?.thumbnail) continue;
      await client.query(
        `
        update video_assets
        set thumbnail_url = coalesce(thumbnail_url, $2),
            manifest_url = coalesce(manifest_url, $3),
            updated_at = now()
        where upload_session_id = $1
      `,
        [row.upload_session_id, details.thumbnail, details.playbackUrl ?? null],
      );
      processed += 1;
    }
    return processed;
  } catch (error) {
    console.error("video-maintenance thumbnail backfill failed", error);
    return 0;
  } finally {
    client.release();
  }
}

async function loop() {
  while (true) {
    const deleted = await processDeleteJobs();
    const backfilled = await processThumbnailBackfill();
    if (deleted > 0 || backfilled > 0) {
      console.log(`video-maintenance deleteJobs=${deleted} thumbnails=${backfilled}`);
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
}

void loop();
