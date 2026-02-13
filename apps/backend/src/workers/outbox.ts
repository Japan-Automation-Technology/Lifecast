import { dbPool, hasDb } from "../store/db.js";

const BATCH_SIZE = 50;
const POLL_MS = 5000;
const MAX_ATTEMPTS = 8;
const OUTBOX_WEBHOOK_URL = process.env.LIFECAST_OUTBOX_WEBHOOK_URL;
const OUTBOX_WEBHOOK_BEARER = process.env.LIFECAST_OUTBOX_WEBHOOK_BEARER;

async function deliverOutboxRow(row: {
  event_id: string;
  topic: string;
  payload: Record<string, unknown>;
}) {
  if (!OUTBOX_WEBHOOK_URL) {
    return { sent: true as const, transport: "noop" as const, httpStatus: null };
  }

  const response = await fetch(OUTBOX_WEBHOOK_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(OUTBOX_WEBHOOK_BEARER ? { authorization: `Bearer ${OUTBOX_WEBHOOK_BEARER}` } : {}),
    },
    body: JSON.stringify({
      event_id: row.event_id,
      topic: row.topic,
      payload: row.payload,
      sent_at: new Date().toISOString(),
    }),
  });

  if (!response.ok) {
    return {
      sent: false as const,
      transport: "webhook" as const,
      httpStatus: response.status,
      errorMessage: `webhook status ${response.status}`,
    };
  }

  return {
    sent: true as const,
    transport: "webhook" as const,
    httpStatus: response.status,
  };
}

async function processBatch() {
  if (!hasDb() || !dbPool) return 0;

  const client = await dbPool.connect();
  try {
    await client.query("begin");
    const pending = await client.query<{
      id: string;
      event_id: string;
      topic: string;
      payload: Record<string, unknown>;
      attempts: number;
    }>(
      `
      select id, event_id, topic, payload, attempts
      from outbox_events
      where status in ('pending', 'failed') and next_attempt_at <= now()
      order by created_at asc
      limit $1
      for update skip locked
    `,
      [BATCH_SIZE],
    );

    for (const row of pending.rows) {
      try {
        const delivery = await deliverOutboxRow(row);
        if (delivery.sent) {
          await client.query(
            `
            update outbox_events
            set status = 'sent', attempts = $2, sent_at = now(), last_error = null, updated_at = now()
            where id = $1
          `,
            [row.id, row.attempts + 1],
          );

          await client.query(
            `
            insert into outbox_delivery_attempts (outbox_event_id, attempt_no, transport, status, http_status, attempted_at)
            values ($1, $2, $3, 'sent', $4, now())
            on conflict (outbox_event_id, attempt_no) do nothing
          `,
            [row.id, row.attempts + 1, delivery.transport, delivery.httpStatus],
          );
          continue;
        }

        const nextAttempts = row.attempts + 1;
        const backoffSeconds = Math.min(2 ** nextAttempts, 3600);
        await client.query(
          `
          update outbox_events
          set status = case when $2 >= $3 then 'failed' else 'pending' end,
              attempts = $2,
              last_error = $4,
              next_attempt_at = now() + ($5 || ' seconds')::interval,
              updated_at = now()
          where id = $1
        `,
          [row.id, nextAttempts, MAX_ATTEMPTS, delivery.errorMessage ?? "delivery failed", `${backoffSeconds}`],
        );

        await client.query(
          `
          insert into outbox_delivery_attempts (outbox_event_id, attempt_no, transport, status, http_status, error_message, attempted_at)
          values ($1, $2, $3, 'failed', $4, $5, now())
          on conflict (outbox_event_id, attempt_no) do nothing
        `,
          [row.id, nextAttempts, delivery.transport, delivery.httpStatus ?? null, delivery.errorMessage ?? "delivery failed"],
        );
      } catch (error) {
        const nextAttempts = row.attempts + 1;
        const backoffSeconds = Math.min(2 ** nextAttempts, 3600);
        await client.query(
          `
          update outbox_events
          set status = case when $2 >= $3 then 'failed' else 'pending' end,
              attempts = $2,
              last_error = $4,
              next_attempt_at = now() + ($5 || ' seconds')::interval,
              updated_at = now()
          where id = $1
        `,
          [
            row.id,
            nextAttempts,
            MAX_ATTEMPTS,
            error instanceof Error ? error.message : "unknown outbox error",
            `${backoffSeconds}`,
          ],
        );

        await client.query(
          `
          insert into outbox_delivery_attempts (outbox_event_id, attempt_no, transport, status, error_message, attempted_at)
          values ($1, $2, 'webhook', 'failed', $3, now())
          on conflict (outbox_event_id, attempt_no) do nothing
        `,
          [row.id, nextAttempts, error instanceof Error ? error.message : "unknown outbox error"],
        );
      }
    }

    await client.query("commit");
    return pending.rowCount ?? 0;
  } catch (error) {
    await client.query("rollback");
    console.error("outbox worker batch failed", error);
    return 0;
  } finally {
    client.release();
  }
}

async function loop() {
  while (true) {
    const processed = await processBatch();
    if (processed > 0) {
      console.log(`outbox-worker processed=${processed}`);
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
}

void loop();
