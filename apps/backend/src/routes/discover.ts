import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { dbPool, hasDb } from "../store/db.js";
import { store } from "../store/hybridStore.js";

const discoverQuery = z.object({
  query: z.string().max(80).optional(),
  limit: z.coerce.number().int().min(1).max(50).optional(),
});

function resolveViewerUserId(): string | null {
  return (
    process.env.LIFECAST_DEV_VIEWER_USER_ID ??
    process.env.LIFECAST_DEV_SUPPORTER_USER_ID ??
    process.env.LIFECAST_DEV_CREATOR_USER_ID ??
    null
  );
}

async function loadViewerRelationship(client: PoolClient, viewerUserId: string | null, creatorUserId: string) {
  if (!viewerUserId || viewerUserId === creatorUserId) {
    return { is_following: false, is_supported: false };
  }

  let isFollowing = false;
  const followTableResult = await client.query<{ exists: boolean }>(
    `select to_regclass('public.user_follows') is not null as exists`,
  );
  if (followTableResult.rows[0]?.exists) {
    const followResult = await client.query<{ is_following: boolean }>(
      `
      select exists(
        select 1
        from user_follows
        where follower_user_id = $1
          and followed_creator_user_id = $2
      ) as is_following
    `,
      [viewerUserId, creatorUserId],
    );
    isFollowing = Boolean(followResult.rows[0]?.is_following);
  }

  const supportResult = await client.query<{ is_supported: boolean }>(
    `
    select exists(
      select 1
      from support_transactions st
      inner join projects p on p.id = st.project_id
      where p.creator_user_id = $2
        and st.supporter_user_id = $1
        and st.status = 'succeeded'
    ) as is_supported
  `,
    [viewerUserId, creatorUserId],
  );
  const isSupported = Boolean(supportResult.rows[0]?.is_supported);
  return { is_following: isFollowing, is_supported: isSupported };
}

export async function registerDiscoverRoutes(app: FastifyInstance) {
  app.get("/v1/discover/creators", async (req, reply) => {
    const parsed = discoverQuery.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid discover query"));
    }

    const query = (parsed.data.query ?? "").trim();
    const limit = parsed.data.limit ?? 20;

    if (!hasDb() || !dbPool) {
      return reply.send(
        ok({
          rows: [
            {
              creator_user_id: "00000000-0000-0000-0000-000000000002",
              username: "lifecast_maker",
              display_name: "LifeCast Maker",
              project_title: "LifeCast Dev Project",
            },
          ],
        }),
      );
    }

    const client = await dbPool.connect();
    try {
      const result = await client.query<{
        creator_user_id: string;
        username: string;
        display_name: string | null;
        project_title: string | null;
      }>(
        `
        select
          cp.creator_user_id,
          cp.username,
          cp.display_name,
          p.title as project_title
        from creator_profiles cp
        left join lateral (
          select title
          from projects
          where creator_user_id = cp.creator_user_id
            and status in ('active', 'draft')
          order by created_at desc
          limit 1
        ) p on true
        where
          ($1 = ''
           or cp.username ilike '%' || $1 || '%'
           or coalesce(cp.display_name, '') ilike '%' || $1 || '%')
        order by cp.username asc
        limit $2
      `,
        [query, limit],
      );

      return reply.send(
        ok({
          rows: result.rows,
        }),
      );
    } finally {
      client.release();
    }
  });

  app.get("/v1/creators/:creatorUserId", async (req, reply) => {
    const creatorUserId = (req.params as { creatorUserId: string }).creatorUserId;
    if (!z.string().uuid().safeParse(creatorUserId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid creator id"));
    }

    if (!hasDb() || !dbPool) {
      const project = await store.getProjectByCreator(creatorUserId);
      const videos = await store.listCreatorVideos(creatorUserId, 30);
      return reply.send(
        ok({
          profile: {
            creator_user_id: creatorUserId,
            username: "creator",
            display_name: "Creator",
            bio: null,
            avatar_url: null,
          },
          viewer_relationship: {
            is_following: false,
            is_supported: false,
          },
          project: project
            ? {
                id: project.id,
                creator_user_id: project.creatorUserId,
                title: project.title,
                subtitle: project.subtitle,
                image_url: project.imageUrl,
                category: project.category,
                location: project.location,
                status: project.status,
                goal_amount_minor: project.goalAmountMinor,
                funded_amount_minor: project.fundedAmountMinor,
                supporter_count: project.supporterCount,
                support_count_total: project.supportCountTotal,
                currency: project.currency,
                duration_days: project.durationDays,
                deadline_at: project.deadlineAt,
                description: project.description,
                urls: project.urls,
                created_at: project.createdAt,
                minimum_plan: project.minimumPlan,
                plans: project.plans,
              }
            : null,
          videos: videos,
        }),
      );
    }

    const client = await dbPool.connect();
    try {
      const viewerUserId = resolveViewerUserId();
      const profileResult = await client.query<{
        creator_user_id: string;
        username: string;
        display_name: string | null;
        bio: string | null;
        avatar_url: string | null;
      }>(
        `
        select creator_user_id, username, display_name, bio, avatar_url
        from creator_profiles
        where creator_user_id = $1
        limit 1
      `,
        [creatorUserId],
      );

      if (profileResult.rowCount === 0) {
        return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Creator not found"));
      }

      const relationship = await loadViewerRelationship(client, viewerUserId, creatorUserId);

      const project = await store.getProjectByCreator(creatorUserId);
      const videos = await store.listCreatorVideos(creatorUserId, 30);

      return reply.send(
        ok({
          profile: profileResult.rows[0],
          viewer_relationship: relationship,
          project: project
            ? {
                id: project.id,
                creator_user_id: project.creatorUserId,
                title: project.title,
                subtitle: project.subtitle,
                image_url: project.imageUrl,
                category: project.category,
                location: project.location,
                status: project.status,
                goal_amount_minor: project.goalAmountMinor,
                funded_amount_minor: project.fundedAmountMinor,
                supporter_count: project.supporterCount,
                support_count_total: project.supportCountTotal,
                currency: project.currency,
                duration_days: project.durationDays,
                deadline_at: project.deadlineAt,
                description: project.description,
                urls: project.urls,
                created_at: project.createdAt,
                minimum_plan: project.minimumPlan
                  ? {
                      id: project.minimumPlan.id,
                      name: project.minimumPlan.name,
                      price_minor: project.minimumPlan.priceMinor,
                      reward_summary: project.minimumPlan.rewardSummary,
                      description: project.minimumPlan.description,
                      image_url: project.minimumPlan.imageUrl,
                      currency: project.minimumPlan.currency,
                    }
                  : null,
                plans: project.plans.map((plan) => ({
                  id: plan.id,
                  name: plan.name,
                  price_minor: plan.priceMinor,
                  reward_summary: plan.rewardSummary,
                  description: plan.description,
                  image_url: plan.imageUrl,
                  currency: plan.currency,
                })),
              }
            : null,
          videos: videos.map((video) => ({
            video_id: video.videoId,
            status: video.status,
            file_name: video.fileName,
            playback_url: video.playbackUrl,
            thumbnail_url: video.thumbnailUrl,
            created_at: video.createdAt,
          })),
        }),
      );
    } finally {
      client.release();
    }
  });

  app.post("/v1/creators/:creatorUserId/follow", async (req, reply) => {
    const creatorUserId = (req.params as { creatorUserId: string }).creatorUserId;
    if (!z.string().uuid().safeParse(creatorUserId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid creator id"));
    }
    const viewerUserId = resolveViewerUserId();
    if (!viewerUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Viewer user id is not configured"));
    }
    if (viewerUserId === creatorUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Cannot follow yourself"));
    }
    if (!hasDb() || !dbPool) {
      return reply.send(ok({ viewer_relationship: { is_following: true, is_supported: false } }));
    }

    const client = await dbPool.connect();
    try {
      await client.query(
        `
        insert into user_follows (follower_user_id, followed_creator_user_id, created_at)
        values ($1, $2, now())
        on conflict do nothing
      `,
        [viewerUserId, creatorUserId],
      );
      const relationship = await loadViewerRelationship(client, viewerUserId, creatorUserId);
      return reply.send(ok({ viewer_relationship: relationship }));
    } finally {
      client.release();
    }
  });

  app.delete("/v1/creators/:creatorUserId/follow", async (req, reply) => {
    const creatorUserId = (req.params as { creatorUserId: string }).creatorUserId;
    if (!z.string().uuid().safeParse(creatorUserId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid creator id"));
    }
    const viewerUserId = resolveViewerUserId();
    if (!viewerUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Viewer user id is not configured"));
    }
    if (viewerUserId === creatorUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Cannot unfollow yourself"));
    }
    if (!hasDb() || !dbPool) {
      return reply.send(ok({ viewer_relationship: { is_following: false, is_supported: false } }));
    }

    const client = await dbPool.connect();
    try {
      await client.query(
        `
        delete from user_follows
        where follower_user_id = $1
          and followed_creator_user_id = $2
      `,
        [viewerUserId, creatorUserId],
      );
      const relationship = await loadViewerRelationship(client, viewerUserId, creatorUserId);
      return reply.send(ok({ viewer_relationship: relationship }));
    } finally {
      client.release();
    }
  });
}
