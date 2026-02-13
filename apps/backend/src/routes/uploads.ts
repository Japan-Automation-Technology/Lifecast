import type { FastifyInstance } from "fastify";
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
      upload_url: session.uploadUrl,
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
      }),
    );
  });
}
