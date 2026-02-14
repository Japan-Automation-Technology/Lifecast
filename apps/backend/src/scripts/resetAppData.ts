import { dbPool, hasDb } from "../store/db.js";
import { loadEnv } from "../env.js";

loadEnv();

const TABLES = [
  "user_follows",
  "creator_profiles",
  "support_status_history",
  "payment_attempts",
  "support_transactions",
  "project_plans",
  "projects",
  "video_processing_jobs",
  "video_assets",
  "video_upload_sessions",
  "moderation_reports",
  "trust_scores",
  "payout_batches",
  "journal_entries",
  "journal_imbalances",
  "idempotency_keys",
  "payment_webhook_events",
  "event_ingest_staging",
  "event_dlq",
  "outbox_delivery_attempts",
  "outbox_events",
  "notifications",
  "users",
] as const;

async function main() {
  if (!hasDb() || !dbPool) {
    throw new Error("LIFECAST_DATABASE_URL is required");
  }

  const client = await dbPool.connect();
  try {
    await client.query("begin");
    const existing = await client.query<{ tablename: string }>(
      `
      select tablename
      from pg_tables
      where schemaname = 'public'
        and tablename = any($1::text[])
      order by tablename asc
    `,
      [TABLES],
    );
    if (existing.rows.length > 0) {
      const quoted = existing.rows
        .map((row) => `public.${row.tablename.replace(/"/g, "\"\"")}`)
        .join(", ");
      await client.query(`truncate table ${quoted} restart identity cascade`);
    }
    await client.query("commit");
    console.log(`[reset-app-data] done. truncated ${existing.rows.length} tables`);
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("[reset-app-data] failed", error);
    process.exit(1);
  });
