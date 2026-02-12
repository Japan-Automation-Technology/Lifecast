import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";

export async function registerPaymentRoutes(app: FastifyInstance) {
  app.post("/v1/payments/webhooks/stripe", async (req, reply) => {
    const signature = req.headers["stripe-signature"];
    if (!signature || typeof signature !== "string") {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Missing Stripe-Signature header"));
    }

    const payload = req.body as Record<string, unknown>;
    const eventId = z.string().min(1).safeParse(payload?.id);
    const eventType = z.string().min(1).safeParse(payload?.type);
    if (!eventId.success || !eventType.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid webhook payload"));
    }

    const metadataSupportId = z.string().uuid().safeParse(
      (payload?.data as { object?: { metadata?: { support_id?: string } } } | undefined)?.object?.metadata?.support_id,
    );
    const topLevelSupportId = z.string().uuid().safeParse(payload?.support_id);
    const supportId = metadataSupportId.success
      ? metadataSupportId.data
      : topLevelSupportId.success
        ? topLevelSupportId.data
        : undefined;

    const result = await store.processStripeWebhook({
      eventId: eventId.data,
      eventType: eventType.data,
      payload,
      supportId,
    });

    return reply.send(ok({ ok: true, deduped: result.deduped, processed: result.processed }));
  });
}
