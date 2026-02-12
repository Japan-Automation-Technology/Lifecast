import type { FastifyInstance } from "fastify";
import { z } from "zod";
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

    const result = await store.createProjectReport({
      projectId,
      reasonCode: body.data.reason_code,
      details: body.data.details,
    });

    return reply.send(
      ok({
        report_id: result.reportId,
        auto_review_triggered: result.autoReviewTriggered,
        trust_score_24h: result.trustScore24h,
        unique_reporters_24h: result.uniqueReporters24h,
      }),
    );
  });
}
