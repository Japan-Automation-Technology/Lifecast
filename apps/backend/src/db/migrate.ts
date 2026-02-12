import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { dbPool, hasDb } from "../store/db.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const migrationsDir = join(__dirname, "migrations");

async function runMigrations() {
  if (!hasDb() || !dbPool) {
    throw new Error("LIFECAST_DATABASE_URL is required for migrations");
  }

  const client = await dbPool.connect();
  try {
    await client.query(`
      create table if not exists schema_migrations (
        version text primary key,
        applied_at timestamptz not null default now()
      )
    `);

    const files = (await readdir(migrationsDir)).filter((f) => f.endsWith(".sql")).sort();

    for (const file of files) {
      const already = await client.query(`select 1 from schema_migrations where version = $1`, [file]);
      if (already.rowCount && already.rowCount > 0) {
        console.log(`[migrate] skip ${file}`);
        continue;
      }

      const sql = await readFile(join(migrationsDir, file), "utf8");
      console.log(`[migrate] applying ${file}`);

      await client.query("begin");
      await client.query(sql);
      await client.query(`insert into schema_migrations (version) values ($1)`, [file]);
      await client.query("commit");
      console.log(`[migrate] applied ${file}`);
    }
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

runMigrations()
  .then(() => {
    console.log("[migrate] done");
    process.exit(0);
  })
  .catch((error) => {
    console.error("[migrate] failed", error);
    process.exit(1);
  });
