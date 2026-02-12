import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";

const releaseBody = z.object({
  amount_minor: z.number().int().positive(),
  currency: z.string().length(3),
});

export async function registerPayoutRoutes(app: FastifyInstance) {
  app.get("/v1/projects/:projectId/payouts", async (req, reply) => {
    const projectId = (req.params as { projectId: string }).projectId;
    if (!z.string().uuid().safeParse(projectId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid project id"));
    }

    const payout = await store.getOrCreatePayout(projectId);
    if (!payout) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Project not found"));
    }

    return reply.send(
      ok({
        project_id: payout.projectId,
        payout_status: payout.payoutStatus,
        execution_start_at: payout.executionStartAt,
        settlement_due_at: payout.settlementDueAt,
        settled_at: payout.settledAt,
        rolling_reserve_enabled: payout.rollingReserveEnabled,
      }),
    );
  });

  app.post("/v1/projects/:projectId/payouts/release", async (req, reply) => {
    const projectId = (req.params as { projectId: string }).projectId;
    const body = releaseBody.safeParse(req.body);
    if (!z.string().uuid().safeParse(projectId).success || !body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid payout release payload"));
    }

    const result = await store.recordPayoutRelease({
      projectId,
      amountMinor: body.data.amount_minor,
      currency: body.data.currency,
    });

    if (!result) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Project not found"));
    }

    return reply.send(ok({ ok: true, project_id: projectId }));
  });
}
