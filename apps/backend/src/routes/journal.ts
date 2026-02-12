import type { FastifyInstance } from "fastify";
import { ok } from "../response.js";

export async function registerJournalRoutes(app: FastifyInstance) {
  app.get("/v1/journal/entries", async () => {
    return ok({
      entries: [],
    });
  });
}
