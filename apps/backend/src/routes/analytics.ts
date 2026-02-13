import type { FastifyInstance } from "fastify";
import { ok } from "../response.js";
import { store } from "../store/hybridStore.js";

export async function registerAnalyticsRoutes(app: FastifyInstance) {
  app.get("/v1/analytics/funnel-daily", async (req) => {
    const query = req.query as { date_from?: string; date_to?: string; limit?: string };
    const rows = await store.listFunnelDaily({
      dateFrom: query.date_from,
      dateTo: query.date_to,
      limit: query.limit ? Number.parseInt(query.limit, 10) : undefined,
    });

    return ok({ rows });
  });

  app.get("/v1/analytics/kpi-daily", async (req) => {
    const query = req.query as { date_from?: string; date_to?: string; limit?: string };
    const rows = await store.listKpiDaily({
      dateFrom: query.date_from,
      dateTo: query.date_to,
      limit: query.limit ? Number.parseInt(query.limit, 10) : undefined,
    });
    return ok({ rows });
  });
}
