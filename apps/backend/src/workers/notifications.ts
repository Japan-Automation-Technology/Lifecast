import { dbPool, hasDb } from "../store/db.js";

const BATCH_SIZE = 50;
const POLL_MS = 5000;

async function processBatch() {
  if (!hasDb() || !dbPool) {
    return 0;
  }

  const client = await dbPool.connect();
  try {
    await client.query("begin");
    const pending = await client.query<{
      id: string;
      user_id: string | null;
      channel: "push" | "in_app" | "email" | "ops_pager";
      event_key: string;
      payload: Record<string, unknown>;
    }>(
      `
      select id, user_id, channel, event_key, payload
      from notification_events
      where sent_at is null and failed_at is null and send_after <= now()
      order by created_at asc
      limit $1
      for update skip locked
    `,
      [BATCH_SIZE],
    );

    for (const row of pending.rows) {
      // Placeholder delivery behavior for M1:
      // mark as sent after successful dequeue. Provider integrations come later.
      await client.query(
        `
        update notification_events
        set sent_at = now()
        where id = $1
      `,
        [row.id],
      );
    }

    await client.query("commit");
    return pending.rowCount ?? 0;
  } catch (error) {
    await client.query("rollback");
    console.error("notification worker batch failed", error);
    return 0;
  } finally {
    client.release();
  }
}

async function loop() {
  while (true) {
    const processed = await processBatch();
    if (processed > 0) {
      console.log(`notification-worker processed=${processed}`);
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
}

void loop();
