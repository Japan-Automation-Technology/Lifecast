import type { FastifyInstance } from "fastify";
import { createReadStream, existsSync } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { resolve } from "node:path";
import { z } from "zod";
import { getStoredIdempotentResponse, requestFingerprint, storeIdempotentResponse } from "../idempotency.js";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";

const createUploadBody = z.object({
  file_name: z.string().min(1).max(255),
  content_type: z.enum(["video/mp4", "video/quicktime"]),
  file_size_bytes: z.number().int().positive(),
  content_hash_sha256: z.string().regex(/^[A-Fa-f0-9]{64}$/).optional(),
});

const completeUploadBody = z.object({
  storage_object_key: z.string().min(1),
  content_hash_sha256: z.string().regex(/^[A-Fa-f0-9]{64}$/),
});

export async function registerUploadRoutes(app: FastifyInstance) {
  const publicBaseUrl = (process.env.LIFECAST_PUBLIC_BASE_URL || "http://localhost:8080").replace(/\/$/, "");
  const devSampleVideoNames = ["video_1.mov", "video_2.mov", "video_3.mov"] as const;
  const devAssetsDir = resolve(process.cwd(), "dev-assets");

  app.post("/v1/videos/uploads", async (req, reply) => {
    const body = createUploadBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid upload request"));
    }
    const routeKey = "POST:/v1/videos/uploads";
    const idempotencyKeyHeader = req.headers["idempotency-key"];
    const idempotencyKey = typeof idempotencyKeyHeader === "string" ? idempotencyKeyHeader : undefined;
    const fingerprint = requestFingerprint(req.method, routeKey, body.data);

    if (idempotencyKey) {
      const existing = await getStoredIdempotentResponse(routeKey, idempotencyKey);
      if (existing) {
        if (existing.fingerprint !== fingerprint) {
          return reply.code(409).send(fail("STATE_CONFLICT", "Idempotency-Key reused with different payload"));
        }
        return reply.code(existing.response.statusCode).send(existing.response.payload);
      }
    }

    const session = await store.createUploadSession({
      fileName: body.data.file_name,
      contentType: body.data.content_type,
      fileSizeBytes: body.data.file_size_bytes,
    });
    const response = ok({
      upload_session_id: session.uploadSessionId,
      status: session.status,
      upload_url: session.uploadUrl ?? `${publicBaseUrl}/v1/videos/uploads/${session.uploadSessionId}/binary`,
      expires_at: session.expiresAt,
    });
    if (idempotencyKey) {
      await storeIdempotentResponse({
        routeKey,
        idempotencyKey,
        fingerprint,
        statusCode: 200,
        payload: response,
      });
    }
    return reply.send(response);
  });

  app.post("/v1/videos/uploads/:uploadSessionId/complete", async (req, reply) => {
    const uploadSessionId = (req.params as { uploadSessionId: string }).uploadSessionId;
    const body = completeUploadBody.safeParse(req.body);
    if (!z.string().uuid().safeParse(uploadSessionId).success || !body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid upload complete request"));
    }
    const routeKey = "POST:/v1/videos/uploads/:uploadSessionId/complete";
    const idempotencyKeyHeader = req.headers["idempotency-key"];
    const idempotencyKey = typeof idempotencyKeyHeader === "string" ? idempotencyKeyHeader : undefined;
    const fingerprint = requestFingerprint(req.method, `${routeKey}:${uploadSessionId}`, body.data);

    if (idempotencyKey) {
      const existing = await getStoredIdempotentResponse(routeKey, idempotencyKey);
      if (existing) {
        if (existing.fingerprint !== fingerprint) {
          return reply.code(409).send(fail("STATE_CONFLICT", "Idempotency-Key reused with different payload"));
        }
        return reply.code(existing.response.statusCode).send(existing.response.payload);
      }
    }

    let session;
    try {
      session = await store.completeUploadSession(
        uploadSessionId,
        body.data.content_hash_sha256,
        body.data.storage_object_key,
      );
    } catch (error) {
      const maybeCode = (error as { code?: string }).code;
      if (maybeCode === "UPLOAD_HASH_CONFLICT") {
        const conflict = fail("STATE_CONFLICT", "Upload hash already exists for this creator");
        if (idempotencyKey) {
          await storeIdempotentResponse({
            routeKey,
            idempotencyKey,
            fingerprint,
            statusCode: 409,
            payload: conflict,
          });
        }
        return reply.code(409).send(conflict);
      }
      throw error;
    }
    if (!session) {
      const notFound = fail("RESOURCE_NOT_FOUND", "Upload session not found");
      if (idempotencyKey) {
        await storeIdempotentResponse({
          routeKey,
          idempotencyKey,
          fingerprint,
          statusCode: 404,
          payload: notFound,
        });
      }
      return reply.code(404).send(notFound);
    }

    const response = ok({
      upload_session_id: session.uploadSessionId,
      status: session.status,
      video_id: session.videoId,
    });
    if (idempotencyKey) {
      await storeIdempotentResponse({
        routeKey,
        idempotencyKey,
        fingerprint,
        statusCode: 200,
        payload: response,
      });
    }
    return reply.send(response);
  });

  app.get("/v1/videos/uploads/:uploadSessionId", async (req, reply) => {
    const uploadSessionId = (req.params as { uploadSessionId: string }).uploadSessionId;
    if (!z.string().uuid().safeParse(uploadSessionId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid upload session id"));
    }

    const session = await store.getUploadSession(uploadSessionId);
    if (!session) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Upload session not found"));
    }

    return reply.send(
      ok({
        upload_session_id: session.uploadSessionId,
        status: session.status,
        upload_url: session.uploadUrl,
        expires_at: session.expiresAt,
        video_id: session.videoId,
        storage_object_key: session.storageObjectKey,
      }),
    );
  });

  app.put("/v1/videos/uploads/:uploadSessionId/binary", async (req, reply) => {
    const uploadSessionId = (req.params as { uploadSessionId: string }).uploadSessionId;
    if (!z.string().uuid().safeParse(uploadSessionId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid upload session id"));
    }

    const body = req.body;
    let payload: Buffer;
    if (Buffer.isBuffer(body)) {
      payload = body;
    } else {
      const chunks: Buffer[] = [];
      for await (const chunk of req.raw) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      }
      payload = Buffer.concat(chunks);
    }
    if (payload.byteLength === 0) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Upload payload is empty"));
    }

    const contentTypeHeader = req.headers["content-type"];
    const contentType = typeof contentTypeHeader === "string" ? contentTypeHeader.split(";")[0].trim() : "video/mp4";

    const written = await store.writeUploadBinary(uploadSessionId, {
      contentType,
      payload,
    });
    if (!written) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Upload session not found"));
    }

    return reply.send(
      ok({
        upload_session_id: uploadSessionId,
        storage_object_key: written.storageObjectKey,
        bytes_stored: written.bytesStored,
        content_hash_sha256: written.contentHashSha256,
      }),
    );
  });

  app.get("/v1/videos/mine", async (_req, reply) => {
    const creatorUserId = process.env.LIFECAST_DEV_CREATOR_USER_ID;
    if (!creatorUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "LIFECAST_DEV_CREATOR_USER_ID is not configured"));
    }

    const rows = await store.listCreatorVideos(creatorUserId, 30);
    return reply.send(
      ok({
        rows: rows.map((row) => ({
          video_id: row.videoId,
          status: row.status,
          file_name: row.fileName,
          playback_url: row.playbackUrl,
          created_at: row.createdAt,
        })),
      }),
    );
  });

  app.get("/v1/videos/:videoId/playback", async (req, reply) => {
    const videoId = (req.params as { videoId: string }).videoId;
    if (!z.string().uuid().safeParse(videoId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid video id"));
    }

    const playback = await store.getVideoPlaybackById(videoId);
    if (!playback || playback.status !== "ready") {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Video playback not ready"));
    }

    if (playback.externalPlaybackUrl) {
      return reply.redirect(playback.externalPlaybackUrl);
    }

    if (!playback.absolutePath || !existsSync(playback.absolutePath)) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Video file not found"));
    }

    const range = req.headers.range;
    const absolutePath = playback.absolutePath;
    const { size } = await stat(absolutePath);
    const contentType = playback.contentType || "video/mp4";

    if (typeof range === "string" && range.startsWith("bytes=")) {
      const [rawStart, rawEnd] = range.replace("bytes=", "").split("-");
      const start = Number(rawStart || 0);
      const end = rawEnd ? Number(rawEnd) : size - 1;
      const safeStart = Number.isFinite(start) ? Math.max(0, start) : 0;
      const safeEnd = Number.isFinite(end) ? Math.min(size - 1, end) : size - 1;
      if (safeStart > safeEnd || safeStart >= size) {
        return reply.code(416).send(fail("VALIDATION_ERROR", "Invalid range"));
      }

      reply.code(206);
      reply.header("Content-Range", `bytes ${safeStart}-${safeEnd}/${size}`);
      reply.header("Accept-Ranges", "bytes");
      reply.header("Content-Length", String(safeEnd - safeStart + 1));
      reply.header("Content-Type", contentType);
      return reply.send(createReadStream(absolutePath, { start: safeStart, end: safeEnd }));
    }

    reply.header("Content-Length", String(size));
    reply.header("Accept-Ranges", "bytes");
    reply.header("Content-Type", contentType);
    return reply.send(createReadStream(absolutePath));
  });

  app.get("/v1/dev/sample-video", async (req, reply) => {
    const params = req.query as { index?: string };
    const requestedIndex = Number(params.index);
    const fallbackIndex = Math.floor(Math.random() * devSampleVideoNames.length);
    const safeIndex = Number.isFinite(requestedIndex) && requestedIndex >= 1 && requestedIndex <= devSampleVideoNames.length
      ? requestedIndex - 1
      : fallbackIndex;
    const selectedName = devSampleVideoNames[safeIndex];
    const samplePath = resolve(devAssetsDir, selectedName);

    if (!existsSync(samplePath)) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", `${selectedName} is missing in dev-assets`));
    }

    const payload = await readFile(samplePath);
    reply.header("Content-Type", "video/quicktime");
    reply.header("Content-Length", String(payload.byteLength));
    reply.header("X-LifeCast-File-Name", selectedName);
    return reply.send(payload);
  });
}
