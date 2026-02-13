import { rm } from "node:fs/promises";
import { resolve } from "node:path";
import { dbPool, hasDb } from "../store/db.js";

async function main() {
  if (!hasDb() || !dbPool) {
    throw new Error("LIFECAST_DATABASE_URL is required");
  }

  const client = await dbPool.connect();
  try {
    await client.query("begin");

    const tables = [
      "video_renditions",
      "video_processing_jobs",
      "video_assets",
      "video_upload_sessions",
    ];

    for (const table of tables) {
      await client.query(`delete from ${table}`);
    }
    await client.query(
      `delete from outbox_events where topic in ('video.upload.completed', 'video.ready')`,
    );

    await client.query("commit");
    console.log("[reset-dev-videos] database rows deleted");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }

  const objectsRoot = resolve(process.cwd(), ".data/video-objects");
  await rm(objectsRoot, { recursive: true, force: true });
  console.log(`[reset-dev-videos] removed ${objectsRoot}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("[reset-dev-videos] failed", error);
    process.exit(1);
  });

