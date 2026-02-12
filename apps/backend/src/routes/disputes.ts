import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { store } from "../store/inMemory.js";

const recoveryBody = z.object({
  action: z.enum(["transfer_reversal_attempt", "account_debit_attempt"]),
  amount_minor: z.number().int().positive(),
  currency: z.string().length(3),
  note: z.string().max(1024).optional(),
});

export async function registerDisputeRoutes(app: FastifyInstance) {
  app.post("/v1/disputes/:disputeId/recovery-attempts", async (req, reply) => {
    const disputeId = (req.params as { disputeId: string }).disputeId;
    const body = recoveryBody.safeParse(req.body);
    if (!z.string().uuid().safeParse(disputeId).success || !body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid dispute recovery request"));
    }

    return reply.send(ok({ ok: true }));
  });

  app.get("/v1/disputes/:disputeId", async (req, reply) => {
    const disputeId = (req.params as { disputeId: string }).disputeId;
    if (!z.string().uuid().safeParse(disputeId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid dispute id"));
    }

    const dispute = store.getOrCreateDispute(disputeId);
    return reply.send(
      ok({
        dispute_id: dispute.disputeId,
        status: dispute.status,
        opened_at: dispute.openedAt,
        acknowledgement_due_at: dispute.acknowledgementDueAt,
        triage_due_at: dispute.triageDueAt,
        resolution_due_at: dispute.resolutionDueAt,
      }),
    );
  });
}
