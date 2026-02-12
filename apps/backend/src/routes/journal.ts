import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { ok } from "../response.js";
import { store } from "../store/hybridStore.js";

const entryTypeSchema = z.enum([
  "support_hold",
  "payout_release",
  "refund",
  "dispute_open",
  "dispute_close",
  "loss_booking",
]);

export async function registerJournalRoutes(app: FastifyInstance) {
  app.get("/v1/journal/entries", async (req) => {
    const query = req.query as { project_id?: string; support_id?: string; entry_type?: string; limit?: string };
    const projectId = query.project_id && z.string().uuid().safeParse(query.project_id).success ? query.project_id : undefined;
    const supportId = query.support_id && z.string().uuid().safeParse(query.support_id).success ? query.support_id : undefined;
    const entryType = query.entry_type && entryTypeSchema.safeParse(query.entry_type).success ? query.entry_type : undefined;
    const parsedLimit = query.limit ? Number.parseInt(query.limit, 10) : undefined;
    const entries = await store.listJournalEntries({ projectId, supportId, entryType, limit: parsedLimit });

    return ok({
      entries,
    });
  });
}
