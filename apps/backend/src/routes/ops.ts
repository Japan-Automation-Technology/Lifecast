import type { FastifyInstance } from "fastify";
import { ok } from "../response.js";
import { store } from "../store/hybridStore.js";

export async function registerOpsRoutes(app: FastifyInstance) {
  app.get("/v1/ops/queues", async () => {
    const status = await store.getOpsQueueStatus();
    return ok(status);
  });
}
