import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";

const ingestBody = z.object({
  events: z.array(z.unknown()).min(1).max(500),
});

export async function registerEventRoutes(app: FastifyInstance) {
  app.post("/v1/events/ingest", async (req, reply) => {
    const body = ingestBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid events payload"));
    }

    const result = await store.ingestEvents({
      events: body.data.events,
      source: "client",
    });

    return reply.send(
      ok({
        accepted: result.accepted,
        rejected: result.rejected,
        rejected_details: result.rejectedDetails,
      }),
    );
  });
}
