import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";

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

    return reply.send(ok({ ok: true }));
  });
}
