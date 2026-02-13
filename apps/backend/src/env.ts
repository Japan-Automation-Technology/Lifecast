import { config } from "dotenv";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

let loaded = false;

export function loadEnv() {
  if (loaded) return;
  loaded = true;
  if (process.env.LIFECAST_DISABLE_DOTENV === "1") return;

  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  const packageEnvPath = resolve(__dirname, "../.env");

  const result = config({ path: packageEnvPath, quiet: true });
  const parsed = result.parsed ?? {};

  // Prefer `.env` for LIFECAST_* values to avoid launchctl/session drift.
  for (const [key, value] of Object.entries(parsed)) {
    if (key.startsWith("LIFECAST_")) {
      process.env[key] = value;
    }
  }
}
