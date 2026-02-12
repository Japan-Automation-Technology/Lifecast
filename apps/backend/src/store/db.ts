import { Pool } from "pg";
import { loadEnv } from "../env.js";

loadEnv();

const rawConnectionString = process.env.LIFECAST_DATABASE_URL;
const connectionString = rawConnectionString?.includes("sslmode=require") &&
  !rawConnectionString.includes("uselibpqcompat=")
  ? `${rawConnectionString}&uselibpqcompat=true`
  : rawConnectionString;

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
