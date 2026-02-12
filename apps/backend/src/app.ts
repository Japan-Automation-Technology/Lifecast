import Fastify from "fastify";
import cors from "@fastify/cors";
import { registerDisputeRoutes } from "./routes/disputes.js";
import { registerJournalRoutes } from "./routes/journal.js";
import { registerModerationRoutes } from "./routes/moderation.js";
import { registerPaymentRoutes } from "./routes/payments.js";
import { registerPayoutRoutes } from "./routes/payouts.js";
import { registerSupportRoutes } from "./routes/supports.js";
import { registerUploadRoutes } from "./routes/uploads.js";

export async function buildApp() {
  const app = Fastify({ logger: true });
  await app.register(cors, { origin: true });

  app.get("/health", async () => ({ ok: true, service: "lifecast-backend" }));

  await registerSupportRoutes(app);
  await registerPaymentRoutes(app);
  await registerUploadRoutes(app);
  await registerJournalRoutes(app);
  await registerDisputeRoutes(app);
  await registerPayoutRoutes(app);
  await registerModerationRoutes(app);

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
