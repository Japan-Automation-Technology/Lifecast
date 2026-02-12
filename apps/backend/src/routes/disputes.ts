import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { getStoredIdempotentResponse, requestFingerprint, storeIdempotentResponse } from "../idempotency.js";
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
    const routeKey = "POST:/v1/disputes/:disputeId/recovery-attempts";
    const idempotencyKeyHeader = req.headers["idempotency-key"];
    const idempotencyKey = typeof idempotencyKeyHeader === "string" ? idempotencyKeyHeader : undefined;
    const fingerprint = requestFingerprint(req.method, `${routeKey}:${disputeId}`, body.data);

    if (idempotencyKey) {
      const existing = await getStoredIdempotentResponse(routeKey, idempotencyKey);
      if (existing) {
        if (existing.fingerprint !== fingerprint) {
          return reply.code(409).send(fail("STATE_CONFLICT", "Idempotency-Key reused with different payload"));
        }
        return reply.code(existing.response.statusCode).send(existing.response.payload);
      }
    }

    const recovery = await store.createDisputeRecoveryAttempt({
      disputeId,
      action: body.data.action,
      amountMinor: body.data.amount_minor,
      currency: body.data.currency,
      note: body.data.note,
    });

    if (!recovery) {
      const notFound = fail("RESOURCE_NOT_FOUND", "Dispute not found");
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
    const response = ok({ ok: recovery.accepted, dispute_id: recovery.disputeId });
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
