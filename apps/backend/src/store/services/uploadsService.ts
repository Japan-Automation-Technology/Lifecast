import { randomUUID, createHash } from "node:crypto";
import { mkdir, stat, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { dbPool, hasDb } from "../db.js";
import type { InMemoryStore } from "../inMemory.js";
import type { CreatorVideoRecord, UploadSession } from "../../types.js";

interface CloudflareDirectUploadResult {
  uid: string;
  uploadURL: string;
}

interface CloudflareVideoDetails {
  uid: string;
  readyToStream: boolean;
  playbackUrl?: string;
  preview?: string;
  thumbnail?: string;
  duration?: number;
  width?: number;
  height?: number;
}

const LOCAL_VIDEO_ROOT = resolve(process.cwd(), ".data/video-objects");

function hasCloudflareStreamConfig() {
  return Boolean(process.env.CF_ACCOUNT_ID && process.env.CF_STREAM_TOKEN);
}

async function createCloudflareDirectUpload(): Promise<CloudflareDirectUploadResult | null> {
  const accountId = process.env.CF_ACCOUNT_ID;
  const token = process.env.CF_STREAM_TOKEN;
  if (!accountId || !token) return null;

  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/direct_upload`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      maxDurationSeconds: 180,
      requireSignedURLs: false,
    }),
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok || !payload?.success || !payload?.result?.uploadURL || !payload?.result?.uid) {
    return null;
  }

  return {
    uid: String(payload.result.uid),
    uploadURL: String(payload.result.uploadURL),
  };
}

async function getCloudflareVideoDetails(uid: string): Promise<CloudflareVideoDetails | null> {
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
  if (!response.ok || !payload?.success || !payload?.result) {
    return null;
  }

  const result = payload.result;
  return {
    uid: String(result.uid ?? uid),
    readyToStream: Boolean(result.readyToStream),
    playbackUrl: typeof result.playback?.hls === "string" ? result.playback.hls : undefined,
    preview: typeof result.preview === "string" ? result.preview : undefined,
    thumbnail: typeof result.thumbnail === "string" ? result.thumbnail : undefined,
    duration: typeof result.duration === "number" ? result.duration : undefined,
    width: typeof result.input?.width === "number" ? result.input.width : undefined,
    height: typeof result.input?.height === "number" ? result.input.height : undefined,
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

  if (!response.ok) {
    return false;
  }
  const payload = await response.json().catch(() => null);
  return Boolean(payload?.success);
}

async function scheduleCloudflareDeleteJob(client: import("pg").PoolClient, input: {
  creatorUserId: string;
  videoId: string;
  providerUploadId: string;
}) {
  await client.query(
    `
    insert into video_delete_jobs (
      creator_user_id, video_id, provider_upload_id, status, attempt, next_run_at, created_at, updated_at
    )
    values ($1, $2, $3, 'pending', 0, now(), now(), now())
  `,
    [input.creatorUserId, input.videoId, input.providerUploadId],
  );
}

function toIso(value: Date | string) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

export class UploadsService {
  constructor(private readonly memory: InMemoryStore) {}
  async createUploadSession(input?: {
    fileName?: string;
    contentType?: string;
    fileSizeBytes?: number;
    projectId?: string;
    creatorUserId?: string;
  }) {
    if (!hasDb() || !dbPool) {
      return this.memory.createUploadSession({
        fileName: input?.fileName,
        projectId: input?.projectId,
        creatorUserId: input?.creatorUserId,
      });
    }

    const client = await dbPool.connect();
    try {
      const uploadSessionId = randomUUID();
      const creatorUserId = input?.creatorUserId;
      if (!creatorUserId) {
        return this.memory.createUploadSession({
          fileName: input?.fileName,
          projectId: input?.projectId,
          creatorUserId: input?.creatorUserId,
        });
      }

      const safeFileName = input?.fileName?.trim().slice(0, 255) || `upload-${uploadSessionId}.mp4`;
      const contentType = input?.contentType || "video/mp4";
      const fileSizeBytes = Math.max(1, Number(input?.fileSizeBytes ?? 1));
      const projectId = input?.projectId;
      if (!projectId) {
        return null;
      }

      const project = await client.query<{ id: string }>(
        `
        select id
        from projects
        where id = $1 and creator_user_id = $2 and status in ('active', 'draft')
        limit 1
      `,
        [projectId, creatorUserId],
      );
      if (project.rowCount === 0) {
        return null;
      }
      const publicBaseUrl = (process.env.LIFECAST_PUBLIC_BASE_URL || "http://localhost:8080").replace(/\/$/, "");
      const cloudflareUpload = hasCloudflareStreamConfig() ? await createCloudflareDirectUpload() : null;
      const uploadUrl = cloudflareUpload?.uploadURL ?? `${publicBaseUrl}/v1/videos/uploads/${uploadSessionId}/binary`;
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();

      await client.query(
        `
        insert into video_upload_sessions (
          id, creator_user_id, status, file_name, content_type, file_size_bytes,
          project_id, provider_upload_id, created_at, updated_at
        )
        values ($1, $2, 'created', $3, $4, $5, $6, $7, now(), now())
      `,
        [
          uploadSessionId,
          creatorUserId,
          safeFileName,
          contentType,
          fileSizeBytes,
          projectId,
          cloudflareUpload?.uid ?? uploadSessionId,
        ],
      );

      return {
        uploadSessionId,
        status: "created",
        uploadUrl,
        expiresAt,
      } satisfies UploadSession;
    } catch {
      return this.memory.createUploadSession({
        fileName: input?.fileName,
        projectId: input?.projectId,
        creatorUserId: input?.creatorUserId,
      });
    } finally {
      client.release();
    }
  }

  async completeUploadSession(uploadSessionId: string, contentHashSha256: string, storageObjectKey?: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.completeUploadSession(uploadSessionId, contentHashSha256, storageObjectKey);
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const generatedVideoId = randomUUID();
      const uploadObjectKey = storageObjectKey || `raw/${uploadSessionId}/source.mp4`;
      const result = await client.query<{
        id: string;
        status: UploadSession["status"];
        provider_upload_id: string | null;
        provider_asset_id: string | null;
        creator_user_id: string;
        storage_object_key: string | null;
      }>(
        `
        update video_upload_sessions
        set status = 'processing',
            content_hash_sha256 = $2,
            storage_object_key = coalesce($3, storage_object_key),
            provider_asset_id = coalesce(provider_asset_id, $4),
            processing_started_at = now(),
            processing_deadline_at = now() + interval '30 minutes',
            completed_at = coalesce(completed_at, now()),
            updated_at = now()
        where id = $1
        returning id, status, provider_upload_id, provider_asset_id, creator_user_id, storage_object_key
      `,
        [uploadSessionId, contentHashSha256, uploadObjectKey, generatedVideoId],
      );

      if (result.rowCount === 0) {
        await client.query("rollback");
        // If createUploadSession fell back to in-memory, allow complete via same fallback path.
        return this.memory.completeUploadSession(uploadSessionId, contentHashSha256, storageObjectKey);
      }

      const row = result.rows[0];
      const cloudflareMode = hasCloudflareStreamConfig();
      const videoId = row.provider_asset_id ?? row.provider_upload_id ?? generatedVideoId;

      await client.query(
        `
        insert into video_assets (
          video_id, creator_user_id, upload_session_id, status, origin_object_key, created_at, updated_at
        )
        values ($1, $2, $3, 'processing', $4, now(), now())
        on conflict (video_id)
        do update set
          status = 'processing',
          origin_object_key = coalesce(excluded.origin_object_key, video_assets.origin_object_key),
          updated_at = now()
      `,
        [videoId, row.creator_user_id, row.id, row.storage_object_key ?? uploadObjectKey],
      );
      if (!cloudflareMode) {
        await client.query(
          `
          insert into video_processing_jobs (id, video_id, stage, status, attempt, run_after, created_at, updated_at)
          values ($1, $2, 'probe', 'pending', 0, now(), now(), now())
          on conflict do nothing
        `,
          [randomUUID(), videoId],
        );
      }

      await client.query(
        `
        insert into outbox_events (event_id, topic, payload, status, next_attempt_at)
        values ($1, 'video.upload.completed', $2::jsonb, 'pending', now())
        on conflict (event_id) do nothing
      `,
        [
          randomUUID(),
          JSON.stringify({
            event_name: "video_upload_completed",
            upload_session_id: row.id,
            video_id: videoId,
            creator_user_id: row.creator_user_id,
            content_hash_sha256: contentHashSha256,
            occurred_at: new Date().toISOString(),
          }),
        ],
      );

      await client.query("commit");
      return {
        uploadSessionId: row.id,
        status: row.status,
        videoId,
        contentHashSha256,
        storageObjectKey: row.storage_object_key ?? uploadObjectKey,
      } satisfies UploadSession;
    } catch (error) {
      await client.query("rollback");
      const pgError = error as { code?: string; constraint?: string; message?: string };
      if (pgError.code === "23505" && pgError.constraint === "uq_upload_hash_per_creator") {
        const conflict = new Error("Upload content hash already exists for this creator");
        (conflict as Error & { code: string }).code = "UPLOAD_HASH_CONFLICT";
        throw conflict;
      }
      throw error;
    } finally {
      client.release();
    }
  }

  async getUploadSession(uploadSessionId: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.getUploadSession(uploadSessionId);
    }

    const client = await dbPool.connect();
    try {
      const result = await client.query<{
        id: string;
        status: UploadSession["status"];
        provider_upload_id: string | null;
        provider_asset_id: string | null;
        content_hash_sha256: string | null;
        storage_object_key: string | null;
        created_at: string | Date;
      }>(
        `
        select id, status, provider_upload_id, provider_asset_id, content_hash_sha256, storage_object_key, created_at
        from video_upload_sessions
        where id = $1
      `,
        [uploadSessionId],
      );

      if (result.rowCount === 0) {
        // If session only exists in memory fallback, keep behavior consistent.
        return this.memory.getUploadSession(uploadSessionId);
      }

      const row = result.rows[0];
      const uploadUrl = `https://upload.lifecast.jp/${row.id}`;
      const expiresAt = new Date(new Date(row.created_at).getTime() + 60 * 60 * 1000).toISOString();
      let latestStatus = row.status;
      let latestVideoId = row.provider_asset_id ?? row.provider_upload_id ?? undefined;

      if (hasCloudflareStreamConfig() && row.provider_upload_id) {
        const details = await getCloudflareVideoDetails(row.provider_upload_id);
        if (details?.readyToStream) {
          latestStatus = "ready";
          await client.query(
            `
            update video_upload_sessions
            set status = 'ready',
                updated_at = now()
            where id = $1
          `,
            [uploadSessionId],
          );
          await client.query(
            `
            update video_assets
            set status = 'ready',
                manifest_url = coalesce($2, manifest_url),
                thumbnail_url = coalesce($3, thumbnail_url),
                updated_at = now()
            where upload_session_id = $1
          `,
            [uploadSessionId, details.playbackUrl ?? details.preview ?? null, details.thumbnail ?? null],
          );
        }
      }

      return {
        uploadSessionId: row.id,
        status: latestStatus,
        videoId: latestVideoId,
        contentHashSha256: row.content_hash_sha256 ?? undefined,
        storageObjectKey: row.storage_object_key ?? undefined,
        uploadUrl,
        expiresAt,
      } satisfies UploadSession;
    } catch {
      return this.memory.getUploadSession(uploadSessionId);
    } finally {
      client.release();
    }
  }

  async writeUploadBinary(
    uploadSessionId: string,
    input: { contentType: string; payload: Buffer; fileName?: string },
  ) {
    if (!hasDb() || !dbPool) {
      const fallbackKey = `local/${uploadSessionId}/source.mp4`;
      const hash = createHash("sha256").update(input.payload).digest("hex");
      return this.memory.writeUploadBinary(uploadSessionId, {
        storageObjectKey: fallbackKey,
        contentHashSha256: hash,
      });
    }

    const client = await dbPool.connect();
    try {
      const sessionResult = await client.query<{
        id: string;
        file_name: string;
      }>(
        `
        select id, file_name
        from video_upload_sessions
        where id = $1
      `,
        [uploadSessionId],
      );

      if (sessionResult.rowCount === 0) {
        return null;
      }

      const safeName = (input.fileName?.trim() || sessionResult.rows[0].file_name || "source.mp4").replace(/[^A-Za-z0-9._-]/g, "_");
      const objectKey = `local/${uploadSessionId}/${safeName}`;
      const absolutePath = resolve(LOCAL_VIDEO_ROOT, objectKey);
      const hash = createHash("sha256").update(input.payload).digest("hex");

      await mkdir(dirname(absolutePath), { recursive: true });
      await writeFile(absolutePath, input.payload);
      await stat(absolutePath);

      await client.query(
        `
        update video_upload_sessions
        set status = 'uploading',
            storage_object_key = $2,
            content_type = $3,
            file_size_bytes = $4,
            updated_at = now()
        where id = $1
      `,
        [uploadSessionId, objectKey, input.contentType, input.payload.byteLength],
      );

      return {
        uploadSessionId,
        storageObjectKey: objectKey,
        contentHashSha256: hash,
        bytesStored: input.payload.byteLength,
      };
    } finally {
      client.release();
    }
  }

  async listCreatorVideos(creatorUserId: string, limit = 30) {
    if (!hasDb() || !dbPool) {
      return this.memory.listCreatorVideos(creatorUserId);
    }

    const client = await dbPool.connect();
    try {
      const publicBaseUrl = (process.env.LIFECAST_PUBLIC_BASE_URL || "http://localhost:8080").replace(/\/$/, "");
      const result = await client.query<{
        video_id: string;
        status: UploadSession["status"];
        file_name: string;
        thumbnail_url: string | null;
        upload_session_id: string;
        provider_upload_id: string | null;
        play_count: string | number;
        watch_completed_count: string | number;
        watch_time_total_ms: string | number;
        created_at: string | Date;
      }>(
        `
        select
          va.video_id,
          va.status,
          vus.file_name,
          va.thumbnail_url,
          va.upload_session_id,
          vus.provider_upload_id,
          coalesce(vm.play_count, 0)::bigint as play_count,
          coalesce(vm.watch_completed_count, 0)::bigint as watch_completed_count,
          coalesce(vm.watch_time_total_ms, 0)::bigint as watch_time_total_ms,
          va.created_at
        from video_assets va
        join video_upload_sessions vus on vus.id = va.upload_session_id
        left join lateral (
          select
            count(*) filter (where ae.event_name = 'video_play_started') as play_count,
            count(*) filter (where ae.event_name = 'video_watch_completed') as watch_completed_count,
            sum(
              case
                when ae.event_name in ('video_watch_progress', 'video_watch_completed')
                  and (ae.attributes->>'watch_duration_ms') ~ '^[0-9]+$'
                then (ae.attributes->>'watch_duration_ms')::bigint
                else 0
              end
            ) as watch_time_total_ms
          from analytics_events ae
          where ae.attributes->>'video_id' = va.video_id::text
        ) vm on true
        where va.creator_user_id = $1
          and va.status = 'ready'
        order by va.created_at desc
        limit $2
      `,
        [creatorUserId, Math.min(Math.max(limit, 1), 100)],
      );

      if (hasCloudflareStreamConfig()) {
        for (const row of result.rows) {
          if (row.thumbnail_url || !row.provider_upload_id) continue;
          const details = await getCloudflareVideoDetails(row.provider_upload_id);
          if (!details?.thumbnail) continue;
          await client.query(
            `
            update video_assets
            set thumbnail_url = coalesce(thumbnail_url, $2),
                manifest_url = coalesce(manifest_url, $3),
                updated_at = now()
            where upload_session_id = $1
          `,
            [row.upload_session_id, details.thumbnail, details.playbackUrl ?? details.preview ?? null],
          );
          row.thumbnail_url = details.thumbnail;
        }
      }

      return result.rows.map((row) => ({
        videoId: row.video_id,
        status: row.status,
        fileName: row.file_name,
        playbackUrl: `${publicBaseUrl}/v1/videos/${row.video_id}/playback`,
        thumbnailUrl: `${publicBaseUrl}/v1/videos/${row.video_id}/thumbnail`,
        playCount: Number(row.play_count ?? 0),
        watchCompletedCount: Number(row.watch_completed_count ?? 0),
        watchTimeTotalMs: Number(row.watch_time_total_ms ?? 0),
        createdAt: toIso(row.created_at),
      })) satisfies CreatorVideoRecord[];
    } finally {
      client.release();
    }
  }

  async getVideoPlaybackById(videoId: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.getPlaybackByVideoId(videoId);
    }

    const client = await dbPool.connect();
    try {
      const result = await client.query<{
        video_id: string;
        status: UploadSession["status"];
        origin_object_key: string | null;
        manifest_url: string | null;
        thumbnail_url: string | null;
        content_type: string;
      }>(
        `
        select
          va.video_id,
          va.status,
          va.origin_object_key,
          va.manifest_url,
          va.thumbnail_url,
          vus.content_type
        from video_assets va
        join video_upload_sessions vus on vus.id = va.upload_session_id
        where va.video_id = $1
      `,
        [videoId],
      );

      if (result.rowCount === 0) return null;
      const row = result.rows[0];
      if (row.manifest_url && /^https?:\/\//.test(row.manifest_url)) {
        let shouldUseExternal = true;
        try {
          const parsed = new URL(row.manifest_url);
          // Guard against bad data that points manifest_url back to this API playback endpoint.
          if (parsed.pathname === `/v1/videos/${row.video_id}/playback`) {
            shouldUseExternal = false;
          }
        } catch {
          shouldUseExternal = false;
        }

        if (shouldUseExternal) {
          return {
            videoId: row.video_id,
            status: row.status,
            contentType: "application/vnd.apple.mpegurl",
            externalPlaybackUrl: row.manifest_url,
          };
        }
      }
      if (!row.origin_object_key) return null;

      return {
        videoId: row.video_id,
        status: row.status,
        contentType: row.content_type || "video/mp4",
        absolutePath: resolve(LOCAL_VIDEO_ROOT, row.origin_object_key),
      };
    } finally {
      client.release();
    }
  }

  async getVideoThumbnailById(videoId: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.getThumbnailByVideoId(videoId);
    }

    const client = await dbPool.connect();
    try {
      const result = await client.query<{
        video_id: string;
        status: UploadSession["status"];
        thumbnail_url: string | null;
        provider_upload_id: string | null;
      }>(
        `
        select
          va.video_id,
          va.status,
          va.thumbnail_url,
          vus.provider_upload_id
        from video_assets va
        join video_upload_sessions vus on vus.id = va.upload_session_id
        where va.video_id = $1
      `,
        [videoId],
      );
      if (result.rowCount === 0) return null;
      const row = result.rows[0];
      if (row.status !== "ready") return null;

      if (row.thumbnail_url && /^https?:\/\//.test(row.thumbnail_url)) {
        return {
          videoId: row.video_id,
          status: row.status,
          externalThumbnailUrl: row.thumbnail_url,
        };
      }

      if (hasCloudflareStreamConfig() && row.provider_upload_id) {
        const details = await getCloudflareVideoDetails(row.provider_upload_id);
        if (details?.thumbnail) {
          await client.query(
            `
            update video_assets
            set thumbnail_url = $2,
                manifest_url = coalesce(manifest_url, $3),
                updated_at = now()
            where video_id = $1
          `,
            [row.video_id, details.thumbnail, details.playbackUrl ?? details.preview ?? null],
          );
          return {
            videoId: row.video_id,
            status: row.status,
            externalThumbnailUrl: details.thumbnail,
          };
        }
      }
      return null;
    } finally {
      client.release();
    }
  }

  async deleteCreatorVideo(creatorUserId: string, videoId: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.deleteCreatorVideo(creatorUserId, videoId);
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const existing = await client.query<{
        video_id: string;
        creator_user_id: string;
        upload_session_id: string;
        provider_upload_id: string | null;
      }>(
        `
        select
          va.video_id,
          va.creator_user_id,
          va.upload_session_id,
          vus.provider_upload_id
        from video_assets va
        join video_upload_sessions vus on vus.id = va.upload_session_id
        where va.video_id = $1
        limit 1
      `,
        [videoId],
      );

      if (existing.rowCount === 0) {
        await client.query("rollback");
        return "not_found" as const;
      }

      const row = existing.rows[0];
      if (row.creator_user_id.toLowerCase() !== creatorUserId.toLowerCase()) {
        await client.query("rollback");
        return "forbidden" as const;
      }

      if (row.provider_upload_id && hasCloudflareStreamConfig()) {
        await scheduleCloudflareDeleteJob(client, {
          creatorUserId,
          videoId,
          providerUploadId: row.provider_upload_id,
        });
      }

      await client.query(`delete from video_assets where video_id = $1 and creator_user_id = $2`, [videoId, creatorUserId]);
      await client.query(`delete from video_upload_sessions where id = $1 and creator_user_id = $2`, [row.upload_session_id, creatorUserId]);
      await client.query("commit");

      if (row.provider_upload_id && hasCloudflareStreamConfig()) {
        const deleted = await deleteCloudflareVideo(row.provider_upload_id);
        if (deleted) {
          const finalizeClient = await dbPool.connect();
          try {
            await finalizeClient.query(
              `
              update video_delete_jobs
              set status = 'succeeded',
                  completed_at = now(),
                  updated_at = now()
              where creator_user_id = $1 and video_id = $2 and provider_upload_id = $3 and status = 'pending'
            `,
              [creatorUserId, videoId, row.provider_upload_id],
            );
          } finally {
            finalizeClient.release();
          }
        }
      }

      return "deleted" as const;
    } catch {
      await client.query("rollback");
      return "not_found" as const;
    } finally {
      client.release();
    }
  }
}
