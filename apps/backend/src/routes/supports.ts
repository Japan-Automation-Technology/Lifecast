import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { store } from "../store/inMemory.js";

const prepareBody = z.object({
  plan_id: z.string().uuid(),
  quantity: z.number().int().min(1).max(10),
});

const confirmBody = z.object({
  provider: z.literal("stripe"),
  provider_session_id: z.string(),
  return_status: z.enum(["success", "canceled", "failed"]).optional(),
});

export async function registerSupportRoutes(app: FastifyInstance) {
  app.post("/v1/projects/:projectId/supports/prepare", async (req, reply) => {
    const projectId = z.string().uuid().safeParse((req.params as { projectId: string }).projectId);
    const body = prepareBody.safeParse(req.body);
    if (!projectId.success || !body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid request payload"));
    }

    const support = store.prepareSupport({
      projectId: projectId.data,
      planId: body.data.plan_id,
      quantity: body.data.quantity,
    });

    return reply.send(
      ok({
        support_id: support.supportId,
        support_status: support.status,
        checkout_url: `https://checkout.lifecast.jp/session/${support.checkoutSessionId}`,
        policy_snapshot: {
          reward_type: "physical",
          cancellation_window_hours: 48,
          refund_policy: "all_or_nothing_auto_refund",
          delivery_estimate: "TBD",
        },
      }),
    );
  });

  app.post("/v1/supports/:supportId/confirm", async (req, reply) => {
    const supportId = (req.params as { supportId: string }).supportId;
    const body = confirmBody.safeParse(req.body);
    if (!z.string().uuid().safeParse(supportId).success || !body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid request payload"));
    }

    const support = store.confirmSupport(supportId);
    if (!support) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Support not found"));
    }

    return reply.send(
      ok({
        support_id: support.supportId,
        support_status: support.status,
        amount_minor: support.amountMinor,
        currency: support.currency,
        project_id: support.projectId,
        plan_id: support.planId,
        reward_type: support.rewardType,
        cancellation_window_hours: support.cancellationWindowHours,
      }),
    );
  });

  app.get("/v1/supports/:supportId", async (req, reply) => {
    const supportId = (req.params as { supportId: string }).supportId;
    if (!z.string().uuid().safeParse(supportId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid support id"));
    }

    const support = store.getSupport(supportId);
    if (!support) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Support not found"));
    }

    return reply.send(
      ok({
        support_id: support.supportId,
        support_status: support.status,
        amount_minor: support.amountMinor,
        currency: support.currency,
        project_id: support.projectId,
        plan_id: support.planId,
        reward_type: support.rewardType,
        cancellation_window_hours: support.cancellationWindowHours,
      }),
    );
  });
}
