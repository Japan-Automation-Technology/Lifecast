import { dbPool, hasDb } from "../store/db.js";

const BATCH_SIZE = 50;
const POLL_MS = 5000;
const MAX_ATTEMPTS = 8;

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
        // M1 baseline: simulate external transport by marking as sent.
        // In M2 this is replaced with real publish (queue / webhook / stream).
        await client.query(
          `
          update outbox_events
          set status = 'sent', sent_at = now(), last_error = null, updated_at = now()
          where id = $1
        `,
          [row.id],
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
