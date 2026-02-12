import { config } from "dotenv";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

let loaded = false;

export function loadEnv() {
  if (loaded) return;
  loaded = true;

  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  const packageEnvPath = resolve(__dirname, "../.env");

  config({ path: packageEnvPath, quiet: true });
}
