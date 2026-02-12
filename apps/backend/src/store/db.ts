import { Pool } from "pg";

const connectionString = process.env.LIFECAST_DATABASE_URL;

export const dbPool = connectionString
  ? new Pool({
      connectionString,
      max: 10,
      ssl: connectionString.includes("sslmode=require") ? { rejectUnauthorized: false } : undefined,
    })
  : null;

export function hasDb() {
  return Boolean(dbPool);
}
