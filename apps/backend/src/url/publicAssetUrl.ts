const DEFAULT_PUBLIC_BASE_URL = "http://localhost:8080";

const LOCAL_ASSET_HOSTS = new Set(["localhost", "127.0.0.1", "0.0.0.0"]);
const LOCAL_ASSET_PATH_PREFIXES = ["/v1/projects/images/", "/v1/profiles/images/"];

function isLegacyRunAppHost(hostname: string) {
  return hostname.startsWith("lifecast-backend-") && hostname.endsWith(".run.app");
}

export function getPublicBaseUrl() {
  return (process.env.LIFECAST_PUBLIC_BASE_URL || DEFAULT_PUBLIC_BASE_URL).replace(/\/$/, "");
}

export function buildPublicAppUrl(pathname: string) {
  const normalizedPath = pathname.startsWith("/") ? pathname : `/${pathname}`;
  return `${getPublicBaseUrl()}${normalizedPath}`;
}

export function normalizeLegacyLocalAssetUrl(value: string | null | undefined): string | null {
  if (!value) return null;
  try {
    const parsed = new URL(value);
    if (!LOCAL_ASSET_PATH_PREFIXES.some((prefix) => parsed.pathname.startsWith(prefix))) return value;
    if (!LOCAL_ASSET_HOSTS.has(parsed.hostname) && !isLegacyRunAppHost(parsed.hostname)) return value;
    return buildPublicAppUrl(`${parsed.pathname}${parsed.search}`);
  } catch {
    return value;
  }
}

export function normalizeLegacyLocalAssetUrls(values: string[] | null | undefined): string[] {
  if (!values || values.length === 0) return [];
  return values
    .map((value) => normalizeLegacyLocalAssetUrl(value))
    .filter((value): value is string => Boolean(value));
}
