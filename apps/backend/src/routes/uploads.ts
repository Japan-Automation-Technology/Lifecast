import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { store } from "../store/inMemory.js";

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
    const session = store.createUploadSession();
    return reply.send(
      ok({
        upload_session_id: session.uploadSessionId,
        status: session.status,
        upload_url: session.uploadUrl,
        expires_at: session.expiresAt,
      }),
    );
  });

  app.post("/v1/videos/uploads/:uploadSessionId/complete", async (req, reply) => {
    const uploadSessionId = (req.params as { uploadSessionId: string }).uploadSessionId;
    const body = completeUploadBody.safeParse(req.body);
    if (!z.string().uuid().safeParse(uploadSessionId).success || !body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid upload complete request"));
    }

    const session = store.completeUploadSession(uploadSessionId, body.data.content_hash_sha256);
    if (!session) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Upload session not found"));
    }

    return reply.send(
      ok({
        upload_session_id: session.uploadSessionId,
        status: session.status,
      }),
    );
  });

  app.get("/v1/videos/uploads/:uploadSessionId", async (req, reply) => {
    const uploadSessionId = (req.params as { uploadSessionId: string }).uploadSessionId;
    if (!z.string().uuid().safeParse(uploadSessionId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid upload session id"));
    }

    const session = store.getUploadSession(uploadSessionId);
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
