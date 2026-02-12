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
    const maybeSupportId = z.string().uuid().safeParse(payload?.support_id);
    if (maybeSupportId.success) {
      await store.markSupportSucceededByWebhook(maybeSupportId.data);
    }

    return reply.send(ok({ ok: true }));
  });
}
