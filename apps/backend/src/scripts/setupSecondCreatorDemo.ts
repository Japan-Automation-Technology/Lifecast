import { randomUUID } from "node:crypto";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { config } from "dotenv";
import { dbPool, hasDb } from "../store/db.js";
import {
  DEV_ALT_CREATOR_USER_ID,
  DEV_ALT_PLAN_BASIC_ID,
  DEV_ALT_PLAN_PREMIUM_ID,
  DEV_ALT_PLAN_STANDARD_ID,
  DEV_ALT_PROJECT_ID,
} from "../db/constants.js";

config({ path: resolve(process.cwd(), "apps/backend/.env"), override: false });

interface CloudflareUploadResult {
  uid: string;
  playbackHls: string | null;
  thumbnail: string | null;
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
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error(`cloudflare stream did not become ready in time: ${uid}`);
}

async function main() {
  if (!hasDb() || !dbPool) {
    throw new Error("LIFECAST_DATABASE_URL is required");
  }

  const publicBaseUrl = (process.env.LIFECAST_PUBLIC_BASE_URL || "http://localhost:8080").replace(/\/$/, "");
  const assetsDir = resolve(process.cwd(), "dev-assets");
  const assetFiles = ["video_1.mov", "video_2.mov", "video_3.mov"];

  const client = await dbPool.connect();
  try {
    await client.query("begin");

    await client.query(
      `
      insert into users (id, created_at)
      values ($1, now())
      on conflict (id) do nothing
    `,
      [DEV_ALT_CREATOR_USER_ID],
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
      values ($1, 'tak_game_lab', 'Tak Game Lab', 'Building handheld game hardware publicly.', now(), now())
      on conflict (creator_user_id)
      do update set
        username = excluded.username,
        display_name = excluded.display_name,
        bio = excluded.bio,
        updated_at = now()
    `,
      [DEV_ALT_CREATOR_USER_ID],
    );

    await client.query(
      `
      delete from video_upload_sessions
      where creator_user_id = $1
    `,
      [DEV_ALT_CREATOR_USER_ID],
    );

    await client.query(`delete from projects where creator_user_id = $1`, [DEV_ALT_CREATOR_USER_ID]);

    await client.query(
      `
      insert into projects (
        id, creator_user_id, title, subtitle, cover_image_url, category, location,
        status, goal_amount_minor, currency, duration_days, deadline_at, description, external_urls,
        created_at, updated_at
      )
      values (
        $1, $2, 'Portable game console - Gen2 prototype', 'Thermal redesign + battery optimization', null, 'Hardware', 'Tokyo, Japan',
        'active', 1000000, 'JPY', 21, now() + interval '21 days',
        'Building an improved handheld with community feedback on controls and thermal design.',
        '["https://lifecast.jp","https://x.com/tak_game_lab"]'::jsonb,
        now(), now()
      )
    `,
      [DEV_ALT_PROJECT_ID, DEV_ALT_CREATOR_USER_ID],
    );

    await client.query(
      `
      insert into project_plans (
        id, project_id, name, reward_summary, description, image_url, is_physical_reward, price_minor, currency, created_at, updated_at
      )
      values
        ($1, $4, 'Early Support', 'Prototype update + thank-you card', 'Early supporter tier', null, true, 1000, 'JPY', now(), now()),
        ($2, $4, 'Standard', '1 unit + supporter badge', 'Main reward tier', null, true, 3000, 'JPY', now(), now()),
        ($3, $4, 'Collector', 'Signed limited package', 'Limited signed package', null, true, 7000, 'JPY', now(), now())
    `,
      [DEV_ALT_PLAN_BASIC_ID, DEV_ALT_PLAN_STANDARD_ID, DEV_ALT_PLAN_PREMIUM_ID, DEV_ALT_PROJECT_ID],
    );

    for (let index = 1; index <= 3; index += 1) {
      const uploadSessionId = randomUUID();
      const videoId = randomUUID();
      const now = new Date(Date.now() - index * 60_000).toISOString();
      const fileName = assetFiles[index - 1];
      const filePath = resolve(assetsDir, fileName);
      const bytes = await readFile(filePath);
      const hash = createHash("sha256").update(bytes).digest("hex");
      const uploadResult = hasCloudflareConfig()
        ? await uploadToCloudflare(filePath)
        : {
            uid: uploadSessionId,
            playbackHls: `${publicBaseUrl}/v1/dev/sample-video?index=${index}`,
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
          DEV_ALT_CREATOR_USER_ID,
          DEV_ALT_PROJECT_ID,
          fileName,
          bytes.byteLength,
          hash,
          `seed/${uploadSessionId}/${fileName}`,
          uploadResult.uid,
          now,
        ],
      );

      await client.query(
        `
        insert into video_assets (
          video_id, creator_user_id, upload_session_id, status, origin_object_key, manifest_url, thumbnail_url, created_at, updated_at
        )
        values (
          $1, $2, $3, 'ready', $4, $5, null, $6, $6
        )
      `,
        [
          videoId,
          DEV_ALT_CREATOR_USER_ID,
          uploadSessionId,
          `seed/${uploadSessionId}/${fileName}`,
          uploadResult.playbackHls ?? `${publicBaseUrl}/v1/dev/sample-video?index=${index}`,
          now,
        ],
      );

      if (uploadResult.thumbnail) {
        await client.query(
          `
          update video_assets
          set thumbnail_url = $2,
              updated_at = now()
          where video_id = $1
        `,
          [videoId, uploadResult.thumbnail],
        );
      }
    }

    await client.query("commit");
    console.log("[setupSecondCreatorDemo] done");
    console.log(`creator_user_id=${DEV_ALT_CREATOR_USER_ID}`);
    console.log("username=tak_game_lab");
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
    console.error("[setupSecondCreatorDemo] failed", error);
    process.exit(1);
  });
