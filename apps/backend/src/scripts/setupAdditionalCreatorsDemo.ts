import { randomUUID, createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { config } from "dotenv";
import { dbPool, hasDb } from "../store/db.js";

config({ path: resolve(process.cwd(), "apps/backend/.env"), override: false });

interface CloudflareUploadResult {
  uid: string;
  playbackHls: string | null;
  thumbnail: string | null;
}

interface CreatorSeed {
  creatorUserId: string;
  username: string;
  displayName: string;
  bio: string;
  projectId: string;
  title: string;
  subtitle: string;
  category: string;
  location: string;
  goalAmountMinor: number;
  durationDays: number;
  description: string;
  urls: string[];
  plan: {
    id: string;
    name: string;
    rewardSummary: string;
    description: string;
    priceMinor: number;
    currency: string;
  };
  assetFile: string;
}

function hasCloudflareConfig() {
  return Boolean(process.env.CF_ACCOUNT_ID && process.env.CF_STREAM_TOKEN);
}

async function uploadToCloudflare(filePath: string): Promise<CloudflareUploadResult> {
  const accountId = process.env.CF_ACCOUNT_ID;
  const token = process.env.CF_STREAM_TOKEN;
  if (!accountId || !token) {
    throw new Error("CF_ACCOUNT_ID and CF_STREAM_TOKEN are required for Cloudflare upload");
  }

  const bytes = await readFile(filePath);
  const form = new FormData();
  form.append("file", new Blob([bytes]), filePath.split("/").pop() || "video.mov");

  const uploadResponse = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
    },
    body: form,
  });

  const uploadPayload = await uploadResponse.json().catch(() => null);
  if (!uploadResponse.ok || !uploadPayload?.success || !uploadPayload?.result?.uid) {
    throw new Error(`cloudflare upload failed: ${JSON.stringify(uploadPayload)}`);
  }

  const uid = String(uploadPayload.result.uid);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const detailResponse = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/${uid}`, {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });
    const detailPayload = await detailResponse.json().catch(() => null);
    if (detailResponse.ok && detailPayload?.success && detailPayload?.result) {
      const result = detailPayload.result;
      if (result.readyToStream) {
        return {
          uid,
          playbackHls: typeof result.playback?.hls === "string" ? result.playback.hls : null,
          thumbnail: typeof result.thumbnail === "string" ? result.thumbnail : null,
        };
      }
    }
    await new Promise((r) => setTimeout(r, 2000));
  }

  throw new Error(`cloudflare stream did not become ready in time: ${uid}`);
}

const creators: CreatorSeed[] = [
  {
    creatorUserId: "00000000-0000-0000-0000-000000000005",
    username: "maker_arcade",
    displayName: "Maker Arcade",
    bio: "Building accessories and mini game hardware in public.",
    projectId: "11111111-1111-1111-1111-111111111115",
    title: "Pocket Button Kit v2",
    subtitle: "Lower latency + modular shell",
    category: "Hardware",
    location: "Osaka, Japan",
    goalAmountMinor: 850000,
    durationDays: 20,
    description: "Iterating a portable button kit with community testing.",
    urls: ["https://lifecast.jp"],
    plan: {
      id: "22222222-2222-2222-2222-222222222227",
      name: "Early Support",
      rewardSummary: "1 kit reservation + progress updates",
      description: "First batch support tier",
      priceMinor: 1200,
      currency: "JPY",
    },
    assetFile: "video_4.MOV",
  },
  {
    creatorUserId: "00000000-0000-0000-0000-000000000006",
    username: "craft_loop_lab",
    displayName: "Craft Loop Lab",
    bio: "Prototyping creative gadgets with supporters.",
    projectId: "11111111-1111-1111-1111-111111111116",
    title: "LoopCam Grip",
    subtitle: "Creator-first phone grip prototype",
    category: "Hardware",
    location: "Tokyo, Japan",
    goalAmountMinor: 920000,
    durationDays: 18,
    description: "Designing a modular grip informed by supporter feedback.",
    urls: ["https://lifecast.jp"],
    plan: {
      id: "22222222-2222-2222-2222-222222222228",
      name: "Supporter Plan",
      rewardSummary: "1 unit pre-order + name in credits",
      description: "Main supporter tier",
      priceMinor: 1500,
      currency: "JPY",
    },
    assetFile: "video_5.MOV",
  },
];

async function upsertCreatorBase(client: import("pg").PoolClient, c: CreatorSeed) {
  await client.query(
    `
    insert into users (id, created_at)
    values ($1, now())
    on conflict (id) do nothing
  `,
    [c.creatorUserId],
  );

  await client.query(
    `
    create table if not exists creator_profiles (
      creator_user_id uuid primary key references users(id) on delete cascade,
      username text not null unique,
      display_name text,
      bio text,
      avatar_url text,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `,
  );

  await client.query(
    `
    insert into creator_profiles (creator_user_id, username, display_name, bio, created_at, updated_at)
    values ($1, $2, $3, $4, now(), now())
    on conflict (creator_user_id)
    do update set
      username = excluded.username,
      display_name = excluded.display_name,
      bio = excluded.bio,
      updated_at = now()
  `,
    [c.creatorUserId, c.username, c.displayName, c.bio],
  );
}

async function reseedCreatorProjectAndVideo(client: import("pg").PoolClient, c: CreatorSeed, publicBaseUrl: string) {
  await client.query(`delete from video_upload_sessions where creator_user_id = $1`, [c.creatorUserId]);
  await client.query(`delete from projects where creator_user_id = $1`, [c.creatorUserId]);

  const deadlineAt = new Date(Date.now() + c.durationDays * 24 * 60 * 60 * 1000).toISOString();
  await client.query(
    `
    insert into projects (
      id, creator_user_id, title, subtitle, cover_image_url, category, location,
      status, goal_amount_minor, currency, duration_days, deadline_at, description, external_urls,
      created_at, updated_at
    )
    values (
      $1, $2, $3, $4, null, $5, $6,
      'active', $7, 'JPY', $8, $9, $10, $11::jsonb,
      now(), now()
    )
  `,
    [
      c.projectId,
      c.creatorUserId,
      c.title,
      c.subtitle,
      c.category,
      c.location,
      c.goalAmountMinor,
      c.durationDays,
      deadlineAt,
      c.description,
      JSON.stringify(c.urls),
    ],
  );

  await client.query(
    `
    insert into project_plans (
      id, project_id, name, reward_summary, description, image_url, is_physical_reward, price_minor, currency, created_at, updated_at
    )
    values ($1, $2, $3, $4, $5, null, true, $6, $7, now(), now())
  `,
    [c.plan.id, c.projectId, c.plan.name, c.plan.rewardSummary, c.plan.description, c.plan.priceMinor, c.plan.currency],
  );

  const assetsDir = resolve(process.cwd(), "dev-assets");
  const filePath = resolve(assetsDir, c.assetFile);
  const bytes = await readFile(filePath);
  const hash = createHash("sha256").update(bytes).digest("hex");

  const uploadSessionId = randomUUID();
  const videoId = randomUUID();
  const nowIso = new Date().toISOString();

  const uploadResult = hasCloudflareConfig()
    ? await uploadToCloudflare(filePath)
    : {
        uid: uploadSessionId,
        playbackHls: `${publicBaseUrl}/v1/dev/sample-video`,
        thumbnail: null,
      };

  await client.query(
    `
    insert into video_upload_sessions (
      id, creator_user_id, project_id, status, file_name, content_type, file_size_bytes,
      content_hash_sha256, storage_object_key, provider_upload_id, provider_asset_id, created_at, updated_at, completed_at
    )
    values (
      $1, $2, $3, 'ready', $4, 'video/quicktime', $5,
      $6, $7, $8, $8, $9, $9, $9
    )
  `,
    [
      uploadSessionId,
      c.creatorUserId,
      c.projectId,
      c.assetFile,
      bytes.byteLength,
      hash,
      `seed/${uploadSessionId}/${c.assetFile}`,
      uploadResult.uid,
      nowIso,
    ],
  );

  await client.query(
    `
    insert into video_assets (
      video_id, creator_user_id, upload_session_id, status, origin_object_key, manifest_url, thumbnail_url, created_at, updated_at
    )
    values (
      $1, $2, $3, 'ready', $4, $5, $6, $7, $7
    )
  `,
    [
      videoId,
      c.creatorUserId,
      uploadSessionId,
      `seed/${uploadSessionId}/${c.assetFile}`,
      uploadResult.playbackHls ?? `${publicBaseUrl}/v1/dev/sample-video`,
      uploadResult.thumbnail,
      nowIso,
    ],
  );
}

async function main() {
  if (!hasDb() || !dbPool) {
    throw new Error("LIFECAST_DATABASE_URL is required");
  }

  const publicBaseUrl = (process.env.LIFECAST_PUBLIC_BASE_URL || "http://localhost:8080").replace(/\/$/, "");

  const client = await dbPool.connect();
  try {
    await client.query("begin");

    for (const creator of creators) {
      await upsertCreatorBase(client, creator);
      await reseedCreatorProjectAndVideo(client, creator, publicBaseUrl);
    }

    await client.query("commit");

    console.log("[setupAdditionalCreatorsDemo] done");
    for (const creator of creators) {
      console.log(`creator_user_id=${creator.creatorUserId} username=${creator.username} asset=${creator.assetFile}`);
    }
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
    console.error("[setupAdditionalCreatorsDemo] failed", error);
    process.exit(1);
  });
