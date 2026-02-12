import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { getStoredIdempotentResponse, requestFingerprint, storeIdempotentResponse } from "../idempotency.js";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";

const reportBody = z.object({
  reason_code: z.enum(["fraud", "copyright", "policy_violation", "no_progress", "other"]),
  details: z.string().min(1).max(2048),
});

export async function registerModerationRoutes(app: FastifyInstance) {
  app.post("/v1/projects/:projectId/reports", async (req, reply) => {
    const projectId = (req.params as { projectId: string }).projectId;
    const body = reportBody.safeParse(req.body);
    if (!z.string().uuid().safeParse(projectId).success || !body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid report payload"));
    }
    const routeKey = "POST:/v1/projects/:projectId/reports";
    const idempotencyKeyHeader = req.headers["idempotency-key"];
    const idempotencyKey = typeof idempotencyKeyHeader === "string" ? idempotencyKeyHeader : undefined;
    const fingerprint = requestFingerprint(req.method, `${routeKey}:${projectId}`, body.data);

    if (idempotencyKey) {
      const existing = await getStoredIdempotentResponse(routeKey, idempotencyKey);
      if (existing) {
        if (existing.fingerprint !== fingerprint) {
          return reply.code(409).send(fail("STATE_CONFLICT", "Idempotency-Key reused with different payload"));
        }
        return reply.code(existing.response.statusCode).send(existing.response.payload);
      }
    }

    const result = await store.createProjectReport({
      projectId,
      reasonCode: body.data.reason_code,
      details: body.data.details,
    });
    const response = ok({
      report_id: result.reportId,
      auto_review_triggered: result.autoReviewTriggered,
      trust_score_24h: result.trustScore24h,
      unique_reporters_24h: result.uniqueReporters24h,
      ok: true,
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
}
