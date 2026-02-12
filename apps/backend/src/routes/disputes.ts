import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";

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

    const recovery = await store.createDisputeRecoveryAttempt({
      disputeId,
      action: body.data.action,
      amountMinor: body.data.amount_minor,
      currency: body.data.currency,
      note: body.data.note,
    });

    if (!recovery) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Dispute not found"));
    }

    return reply.send(ok({ ok: recovery.accepted, dispute_id: recovery.disputeId }));
  });

  app.get("/v1/disputes/:disputeId", async (req, reply) => {
    const disputeId = (req.params as { disputeId: string }).disputeId;
    if (!z.string().uuid().safeParse(disputeId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid dispute id"));
    }

    const dispute = await store.getOrCreateDispute(disputeId);
    if (!dispute) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Dispute not found"));
    }

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
