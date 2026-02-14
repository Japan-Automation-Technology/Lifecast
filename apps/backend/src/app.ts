import Fastify from "fastify";
import cors from "@fastify/cors";
import { registerAnalyticsRoutes } from "./routes/analytics.js";
import { registerDisputeRoutes } from "./routes/disputes.js";
import { registerDiscoverRoutes } from "./routes/discover.js";
import { registerEventRoutes } from "./routes/events.js";
import { registerJournalRoutes } from "./routes/journal.js";
import { registerModerationRoutes } from "./routes/moderation.js";
import { registerOpsRoutes } from "./routes/ops.js";
import { registerPaymentRoutes } from "./routes/payments.js";
import { registerPayoutRoutes } from "./routes/payouts.js";
import { registerProjectRoutes } from "./routes/projects.js";
import { registerSupportRoutes } from "./routes/supports.js";
import { registerUploadRoutes } from "./routes/uploads.js";

export async function buildApp() {
  const app = Fastify({
    logger: true,
    bodyLimit: 50 * 1024 * 1024,
  });
  app.addContentTypeParser(/^video\/.*/, { parseAs: "buffer" }, (_req, body, done) => {
    done(null, body);
  });
  app.addContentTypeParser("application/octet-stream", { parseAs: "buffer" }, (_req, body, done) => {
    done(null, body);
  });
  await app.register(cors, { origin: true });

  app.get("/health", async () => ({ ok: true, service: "lifecast-backend" }));

  await registerSupportRoutes(app);
  await registerEventRoutes(app);
  await registerAnalyticsRoutes(app);
  await registerPaymentRoutes(app);
  await registerProjectRoutes(app);
  await registerDiscoverRoutes(app);
  await registerUploadRoutes(app);
  await registerJournalRoutes(app);
  await registerDisputeRoutes(app);
  await registerPayoutRoutes(app);
  await registerModerationRoutes(app);
  await registerOpsRoutes(app);

  app.setNotFoundHandler((req, reply) => {
    reply.code(404).send({
      request_id: crypto.randomUUID(),
      server_time: new Date().toISOString(),
      error: {
        code: "RESOURCE_NOT_FOUND",
        message: `Route not found: ${req.method} ${req.url}`,
      },
    });
  });

  return app;
}
