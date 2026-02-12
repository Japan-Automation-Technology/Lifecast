import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { getStoredIdempotentResponse, requestFingerprint, storeIdempotentResponse } from "../idempotency.js";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";

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

    const routeKey = "POST:/v1/projects/:projectId/supports/prepare";
    const idempotencyKeyHeader = req.headers["idempotency-key"];
    const idempotencyKey = typeof idempotencyKeyHeader === "string" ? idempotencyKeyHeader : undefined;
    const fingerprint = requestFingerprint(req.method, `${routeKey}:${projectId.data}`, body.data);

    if (idempotencyKey) {
      const existing = await getStoredIdempotentResponse(routeKey, idempotencyKey);
      if (existing) {
        if (existing.fingerprint !== fingerprint) {
          return reply.code(409).send(fail("STATE_CONFLICT", "Idempotency-Key reused with different payload"));
        }
        return reply.code(existing.response.statusCode).send(existing.response.payload);
      }
    }

    const support = await store.prepareSupport({
      projectId: projectId.data,
      planId: body.data.plan_id,
      quantity: body.data.quantity,
    });
    if (!support) {
      const notFound = fail("RESOURCE_NOT_FOUND", "Project or plan not found");
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

    const response = ok({
      support_id: support.supportId,
      support_status: support.status,
      checkout_url: `https://checkout.lifecast.jp/session/${support.checkoutSessionId}`,
      policy_snapshot: {
        reward_type: "physical",
        cancellation_window_hours: 48,
        refund_policy: "all_or_nothing_auto_refund",
        delivery_estimate: "TBD",
      },
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

  app.post("/v1/supports/:supportId/confirm", async (req, reply) => {
    const supportId = (req.params as { supportId: string }).supportId;
    const body = confirmBody.safeParse(req.body);
    if (!z.string().uuid().safeParse(supportId).success || !body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid request payload"));
    }

    const routeKey = "POST:/v1/supports/:supportId/confirm";
    const idempotencyKeyHeader = req.headers["idempotency-key"];
    const idempotencyKey = typeof idempotencyKeyHeader === "string" ? idempotencyKeyHeader : undefined;
    const fingerprint = requestFingerprint(req.method, `${routeKey}:${supportId}`, body.data);

    if (idempotencyKey) {
      const existing = await getStoredIdempotentResponse(routeKey, idempotencyKey);
      if (existing) {
        if (existing.fingerprint !== fingerprint) {
          return reply.code(409).send(fail("STATE_CONFLICT", "Idempotency-Key reused with different payload"));
        }
        return reply.code(existing.response.statusCode).send(existing.response.payload);
      }
    }

    const support = await store.confirmSupport(supportId);
    if (!support) {
      const notFound = fail("RESOURCE_NOT_FOUND", "Support not found");
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

    const response = ok({
      support_id: support.supportId,
      support_status: support.status,
      amount_minor: support.amountMinor,
      currency: support.currency,
      project_id: support.projectId,
      plan_id: support.planId,
      reward_type: support.rewardType,
      cancellation_window_hours: support.cancellationWindowHours,
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

  app.get("/v1/supports/:supportId", async (req, reply) => {
    const supportId = (req.params as { supportId: string }).supportId;
    if (!z.string().uuid().safeParse(supportId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid support id"));
    }

    const support = await store.getSupport(supportId);
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
