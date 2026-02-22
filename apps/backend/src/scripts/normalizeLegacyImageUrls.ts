import type { PoolClient } from "pg";
import { dbPool, hasDb } from "../store/db.js";
import { getPublicBaseUrl, normalizeLegacyLocalAssetUrl } from "../url/publicAssetUrl.js";

function normalizeString(value: string | null | undefined) {
  if (!value) return null;
  return normalizeLegacyLocalAssetUrl(value);
}

function normalizeStringArray(values: unknown) {
  if (!Array.isArray(values)) return [] as string[];
  return values
    .map((value) => (typeof value === "string" ? normalizeLegacyLocalAssetUrl(value) : null))
    .filter((value): value is string => Boolean(value));
}

async function normalizeProjects(client: PoolClient) {
  const rows = await client.query<{
    id: string;
    cover_image_url: string | null;
    project_image_urls: unknown;
  }>(
    `
      select id, cover_image_url, project_image_urls
      from projects
    `,
  );

  let updated = 0;
  for (const row of rows.rows) {
    const nextCover = normalizeString(row.cover_image_url);
    const nextImages = normalizeStringArray(row.project_image_urls);
    const currentImages = Array.isArray(row.project_image_urls) ? row.project_image_urls.filter((v) => typeof v === "string") : [];
    const currentCover = row.cover_image_url ?? null;
    if (currentCover === nextCover && JSON.stringify(currentImages) === JSON.stringify(nextImages)) continue;

    await client.query(
      `
        update projects
        set cover_image_url = $2,
            project_image_urls = $3::jsonb,
            updated_at = now()
        where id = $1
      `,
      [row.id, nextCover, JSON.stringify(nextImages)],
    );
    updated += 1;
  }
  return updated;
}

async function normalizeProjectPlans(client: PoolClient) {
  const rows = await client.query<{ id: string; image_url: string | null }>(
    `
      select id, image_url
      from project_plans
    `,
  );

  let updated = 0;
  for (const row of rows.rows) {
    const next = normalizeString(row.image_url);
    if ((row.image_url ?? null) === next) continue;
    await client.query(
      `
        update project_plans
        set image_url = $2,
            updated_at = now()
        where id = $1
      `,
      [row.id, next],
    );
    updated += 1;
  }
  return updated;
}

async function normalizeUsers(client: PoolClient) {
  const rows = await client.query<{ id: string; avatar_url: string | null }>(
    `
      select id, avatar_url
      from users
    `,
  );

  let updated = 0;
  for (const row of rows.rows) {
    const next = normalizeString(row.avatar_url);
    if ((row.avatar_url ?? null) === next) continue;
    await client.query(
      `
        update users
        set avatar_url = $2,
            updated_at = now()
        where id = $1
      `,
      [row.id, next],
    );
    updated += 1;
  }
  return updated;
}

async function normalizeCreatorProfiles(client: PoolClient) {
  const rows = await client.query<{ creator_user_id: string; avatar_url: string | null }>(
    `
      select creator_user_id, avatar_url
      from creator_profiles
    `,
  );

  let updated = 0;
  for (const row of rows.rows) {
    const next = normalizeString(row.avatar_url);
    if ((row.avatar_url ?? null) === next) continue;
    await client.query(
      `
        update creator_profiles
        set avatar_url = $2,
            updated_at = now()
        where creator_user_id = $1
      `,
      [row.creator_user_id, next],
    );
    updated += 1;
  }
  return updated;
}

async function main() {
  if (!hasDb() || !dbPool) {
    throw new Error("LIFECAST_DATABASE_URL is not configured");
  }

  const client = await dbPool.connect();
  try {
    await client.query("begin");
    const updatedProjects = await normalizeProjects(client);
    const updatedPlans = await normalizeProjectPlans(client);
    const updatedUsers = await normalizeUsers(client);
    const updatedProfiles = await normalizeCreatorProfiles(client);
    await client.query("commit");

    console.log(`[normalize-legacy-image-urls] public_base_url=${getPublicBaseUrl()}`);
    console.log(`[normalize-legacy-image-urls] projects updated: ${updatedProjects}`);
    console.log(`[normalize-legacy-image-urls] project_plans updated: ${updatedPlans}`);
    console.log(`[normalize-legacy-image-urls] users updated: ${updatedUsers}`);
    console.log(`[normalize-legacy-image-urls] creator_profiles updated: ${updatedProfiles}`);
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
    await dbPool.end();
  }
}

main().catch((error) => {
  console.error("[normalize-legacy-image-urls] failed", error);
  process.exit(1);
});
