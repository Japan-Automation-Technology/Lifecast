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

const feedQuery = z.object({
  limit: z.coerce.number().int().min(1).max(50).optional(),
});

const networkQuery = z.object({
  tab: z.enum(["followers", "following", "support"]).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
});

function resolveViewerUserId(): string | null {
  return (
    process.env.LIFECAST_DEV_CREATOR_USER_ID ??
    process.env.LIFECAST_DEV_VIEWER_USER_ID ??
    process.env.LIFECAST_DEV_SUPPORTER_USER_ID ??
    null
  );
}

function resolveProfileUserIdForMe(): string | null {
  return (
    process.env.LIFECAST_DEV_CREATOR_USER_ID ??
    process.env.LIFECAST_DEV_VIEWER_USER_ID ??
    process.env.LIFECAST_DEV_SUPPORTER_USER_ID ??
    null
  );
}

async function loadProfileStats(client: PoolClient, creatorUserId: string, excludeCreatorUserId?: string) {
  let followersCount = 0;
  let followingCount = 0;
  const followTableResult = await client.query<{ exists: boolean }>(
    `select to_regclass('public.user_follows') is not null as exists`,
  );
  if (followTableResult.rows[0]?.exists) {
    const followStatsResult = await client.query<{
      followers_count: string | number;
      following_count: string | number;
    }>(
      `
      select
        (select count(*)
         from user_follows uf
         inner join creator_profiles cp on cp.creator_user_id = uf.follower_user_id
         where uf.followed_creator_user_id = $1) as followers_count,
        (select count(*)
         from user_follows uf
         inner join creator_profiles cp on cp.creator_user_id = uf.followed_creator_user_id
         where uf.follower_user_id = $1) as following_count
    `,
      [creatorUserId],
    );
    followersCount = Number(followStatsResult.rows[0]?.followers_count ?? 0);
    followingCount = Number(followStatsResult.rows[0]?.following_count ?? 0);
  }

  const supportedResult = excludeCreatorUserId
    ? await client.query<{ supported_project_count: string | number }>(
        `
        select count(distinct st.project_id) as supported_project_count
        from support_transactions st
        inner join projects p on p.id = st.project_id
        where st.supporter_user_id = $1
          and st.status in ('pending_confirmation', 'succeeded')
          and p.status = 'active'
          and p.creator_user_id <> st.supporter_user_id
          and p.creator_user_id <> $2
      `,
        [creatorUserId, excludeCreatorUserId],
      )
    : await client.query<{ supported_project_count: string | number }>(
        `
        select count(distinct st.project_id) as supported_project_count
        from support_transactions st
        inner join projects p on p.id = st.project_id
        where st.supporter_user_id = $1
          and st.status in ('pending_confirmation', 'succeeded')
          and p.status = 'active'
          and p.creator_user_id <> st.supporter_user_id
      `,
        [creatorUserId],
      );

  return {
    following_count: followingCount,
    followers_count: followersCount,
    supported_project_count: Number(supportedResult.rows[0]?.supported_project_count ?? 0),
  };
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
  app.get("/v1/feed/projects", async (req, reply) => {
    const parsed = feedQuery.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid feed query"));
    }

    const limit = parsed.data.limit ?? 20;
    const viewerUserId = resolveViewerUserId();

    if (!hasDb() || !dbPool) {
      return reply.send(
        ok({
          rows: [],
        }),
      );
    }

    const client = await dbPool.connect();
    try {
      const result = await client.query<{
        project_id: string;
        creator_user_id: string;
        username: string;
        caption: string | null;
        min_plan_price_minor: string | number;
        goal_amount_minor: string | number;
        funded_amount_minor: string | number;
        remaining_days: string | number;
        likes: string | number;
        comments: string | number;
        is_supported_by_current_user: boolean;
      }>(
        `
        select
          p.id as project_id,
          p.creator_user_id,
          cp.username,
          nullif(coalesce(p.subtitle, p.description, ''), '') as caption,
          coalesce(min_plan.price_minor, 0) as min_plan_price_minor,
          p.goal_amount_minor,
          coalesce((
            select sum(st.amount_minor)
            from support_transactions st
            where st.project_id = p.id and st.status = 'succeeded'
          ), 0) as funded_amount_minor,
          greatest(
            0,
            ceil(extract(epoch from (p.deadline_at - now())) / 86400.0)
          )::int as remaining_days,
          0::int as likes,
          0::int as comments,
          case
            when $1::uuid is null then false
            else exists(
              select 1
              from support_transactions st
              where st.project_id = p.id
                and st.supporter_user_id = $1::uuid
                and st.status = 'succeeded'
            )
          end as is_supported_by_current_user
        from projects p
        inner join creator_profiles cp on cp.creator_user_id = p.creator_user_id
        left join lateral (
          select price_minor
          from project_plans
          where project_id = p.id
          order by price_minor asc, created_at asc
          limit 1
        ) min_plan on true
        where p.status in ('active', 'draft')
          and exists (
            select 1
            from video_assets va
            where va.creator_user_id = p.creator_user_id
              and va.status = 'ready'
          )
          and ($1::uuid is null or p.creator_user_id <> $1::uuid)
        order by p.created_at desc
        limit $2
      `,
        [viewerUserId, limit],
      );

      return reply.send(
        ok({
          rows: result.rows.map((row) => ({
            project_id: row.project_id,
            creator_user_id: row.creator_user_id,
            username: row.username,
            caption: row.caption ?? "Project update",
            min_plan_price_minor: Number(row.min_plan_price_minor),
            goal_amount_minor: Number(row.goal_amount_minor),
            funded_amount_minor: Number(row.funded_amount_minor),
            remaining_days: Number(row.remaining_days),
            likes: Number(row.likes),
            comments: Number(row.comments),
            is_supported_by_current_user: row.is_supported_by_current_user,
          })),
        }),
      );
    } finally {
      client.release();
    }
  });

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
          profile_stats: {
            following_count: 0,
            followers_count: 0,
            supported_project_count: 0,
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
      const profileStats = await loadProfileStats(client, creatorUserId);

      const project = await store.getProjectByCreator(creatorUserId);
      const videos = await store.listCreatorVideos(creatorUserId, 30);

      return reply.send(
        ok({
          profile: profileResult.rows[0],
          viewer_relationship: relationship,
          profile_stats: profileStats,
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

  app.get("/v1/creators/:creatorUserId/network", async (req, reply) => {
    const creatorUserId = (req.params as { creatorUserId: string }).creatorUserId;
    if (!z.string().uuid().safeParse(creatorUserId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid creator id"));
    }
    const parsed = networkQuery.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid network query"));
    }

    const tab = parsed.data.tab ?? "following";
    const limit = parsed.data.limit ?? 100;

    if (!hasDb() || !dbPool) {
      return reply.send(
        ok({
          profile_stats: {
            following_count: 0,
            followers_count: 0,
            supported_project_count: 0,
          },
          rows: [],
        }),
      );
    }

    const client = await dbPool.connect();
    try {
      const viewerUserId = resolveViewerUserId();
      const profileStats = await loadProfileStats(client, creatorUserId);
      const followTableResult = await client.query<{ exists: boolean }>(
        `select to_regclass('public.user_follows') is not null as exists`,
      );
      const followTableExists = Boolean(followTableResult.rows[0]?.exists);
      const viewerFollowExpr = followTableExists
        ? `case
              when $2::uuid is null then false
              else exists(
                select 1
                from user_follows uf2
                where uf2.follower_user_id = $2::uuid
                  and uf2.followed_creator_user_id = cp.creator_user_id
              )
            end`
        : "false";

      let sql = "";
      if (tab === "followers") {
        if (!followTableExists) {
          return reply.send(
            ok({
              profile_stats: profileStats,
              rows: [],
            }),
          );
        }
        sql = `
          with listed as (
            select distinct uf.follower_user_id as listed_creator_user_id
            from user_follows uf
            where uf.followed_creator_user_id = $1
            limit $3
          )
          select
            cp.creator_user_id,
            cp.username,
            cp.display_name,
            cp.bio,
            cp.avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else cp.creator_user_id = $2::uuid end as is_self
          from listed l
          join creator_profiles cp on cp.creator_user_id = l.listed_creator_user_id
          left join lateral (
            select title
            from projects
            where creator_user_id = cp.creator_user_id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by cp.username asc
        `;
      } else if (tab === "following") {
        if (!followTableExists) {
          return reply.send(
            ok({
              profile_stats: profileStats,
              rows: [],
            }),
          );
        }
        sql = `
          with listed as (
            select distinct uf.followed_creator_user_id as listed_creator_user_id
            from user_follows uf
            where uf.follower_user_id = $1
            limit $3
          )
          select
            cp.creator_user_id,
            cp.username,
            cp.display_name,
            cp.bio,
            cp.avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else cp.creator_user_id = $2::uuid end as is_self
          from listed l
          join creator_profiles cp on cp.creator_user_id = l.listed_creator_user_id
          left join lateral (
            select title
            from projects
            where creator_user_id = cp.creator_user_id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by cp.username asc
        `;
      } else {
        sql = `
          with listed as (
            select distinct p.creator_user_id as listed_creator_user_id
            from support_transactions st
            join projects p on p.id = st.project_id
            where st.supporter_user_id = $1
              and st.status = 'succeeded'
            limit $3
          )
          select
            cp.creator_user_id,
            cp.username,
            cp.display_name,
            cp.bio,
            cp.avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else cp.creator_user_id = $2::uuid end as is_self
          from listed l
          join creator_profiles cp on cp.creator_user_id = l.listed_creator_user_id
          left join lateral (
            select title
            from projects
            where creator_user_id = cp.creator_user_id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by cp.username asc
        `;
      }

      const rows = await client.query<{
        creator_user_id: string;
        username: string;
        display_name: string | null;
        bio: string | null;
        avatar_url: string | null;
        project_title: string | null;
        is_following: boolean;
      }>(sql, [creatorUserId, viewerUserId, limit]);

      return reply.send(
        ok({
          profile_stats: profileStats,
          rows: rows.rows,
        }),
      );
    } finally {
      client.release();
    }
  });

  app.get("/v1/me/network", async (req, reply) => {
    const parsed = networkQuery.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid network query"));
    }
    const tab = parsed.data.tab ?? "following";
    const limit = parsed.data.limit ?? 100;

    const profileUserId = resolveProfileUserIdForMe();
    if (!profileUserId || !z.string().uuid().safeParse(profileUserId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Profile user id is not configured"));
    }

    if (!hasDb() || !dbPool) {
      return reply.send(
        ok({
          profile_stats: {
            following_count: 0,
            followers_count: 0,
            supported_project_count: 0,
          },
          rows: [],
        }),
      );
    }

    const client = await dbPool.connect();
    try {
      const profileStats = await loadProfileStats(client, profileUserId, profileUserId);
      const followTableResult = await client.query<{ exists: boolean }>(
        `select to_regclass('public.user_follows') is not null as exists`,
      );
      const followTableExists = Boolean(followTableResult.rows[0]?.exists);
      const viewerFollowExpr = followTableExists
        ? `case
              when $2::uuid is null then false
              else exists(
                select 1
                from user_follows uf2
                where uf2.follower_user_id = $2::uuid
                  and uf2.followed_creator_user_id = cp.creator_user_id
              )
            end`
        : "false";

      let sql = "";
      if (tab === "followers") {
        if (!followTableExists) {
          return reply.send(ok({ profile_stats: profileStats, rows: [] }));
        }
        sql = `
          with listed as (
            select distinct uf.follower_user_id as listed_creator_user_id
            from user_follows uf
            where uf.followed_creator_user_id = $1
            limit $3
          )
          select
            cp.creator_user_id,
            cp.username,
            cp.display_name,
            cp.bio,
            cp.avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else cp.creator_user_id = $2::uuid end as is_self
          from listed l
          join creator_profiles cp on cp.creator_user_id = l.listed_creator_user_id
          left join lateral (
            select title
            from projects
            where creator_user_id = cp.creator_user_id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by cp.username asc
        `;
      } else if (tab === "following") {
        if (!followTableExists) {
          return reply.send(ok({ profile_stats: profileStats, rows: [] }));
        }
        sql = `
          with listed as (
            select distinct uf.followed_creator_user_id as listed_creator_user_id
            from user_follows uf
            where uf.follower_user_id = $1
            limit $3
          )
          select
            cp.creator_user_id,
            cp.username,
            cp.display_name,
            cp.bio,
            cp.avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else cp.creator_user_id = $2::uuid end as is_self
          from listed l
          join creator_profiles cp on cp.creator_user_id = l.listed_creator_user_id
          left join lateral (
            select title
            from projects
            where creator_user_id = cp.creator_user_id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by cp.username asc
        `;
      } else {
        sql = `
          with listed as (
            select distinct p.creator_user_id as listed_creator_user_id
            from support_transactions st
            join projects p on p.id = st.project_id
            where st.supporter_user_id = $1
              and st.status = 'succeeded'
            limit $3
          )
          select
            cp.creator_user_id,
            cp.username,
            cp.display_name,
            cp.bio,
            cp.avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else cp.creator_user_id = $2::uuid end as is_self
          from listed l
          join creator_profiles cp on cp.creator_user_id = l.listed_creator_user_id
          left join lateral (
            select title
            from projects
            where creator_user_id = cp.creator_user_id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by cp.username asc
        `;
      }

      const rows = await client.query<{
        creator_user_id: string;
        username: string;
        display_name: string | null;
        bio: string | null;
        avatar_url: string | null;
        project_title: string | null;
        is_following: boolean;
      }>(sql, [profileUserId, profileUserId, limit]);

      return reply.send(
        ok({
          profile_stats: profileStats,
          rows: rows.rows,
        }),
      );
    } finally {
      client.release();
    }
  });

  app.get("/v1/me/profile", async (_req, reply) => {
    const profileUserId = resolveProfileUserIdForMe();
    if (!profileUserId || !z.string().uuid().safeParse(profileUserId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Profile user id is not configured"));
    }

    if (!hasDb() || !dbPool) {
      return reply.send(
        ok({
          profile: {
            creator_user_id: profileUserId,
            username: "lifecast_maker",
            display_name: "LifeCast Maker",
            bio: null,
            avatar_url: null,
          },
          profile_stats: {
            following_count: 0,
            followers_count: 0,
            supported_project_count: 0,
          },
        }),
      );
    }

    const client = await dbPool.connect();
    try {
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
        [profileUserId],
      );

      const profileStats = await loadProfileStats(client, profileUserId, profileUserId);
      const fallbackUsername = profileUserId === process.env.LIFECAST_DEV_CREATOR_USER_ID ? "lifecast_maker" : "user";
      const hasProfile = profileResult.rows.length > 0;
      const profile = hasProfile
        ? profileResult.rows[0]
        : {
            creator_user_id: profileUserId,
            username: fallbackUsername,
            display_name: fallbackUsername === "lifecast_maker" ? "LifeCast Maker" : "User",
            bio: null,
            avatar_url: null,
          };
      return reply.send(
        ok({
          profile,
          profile_stats: profileStats,
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
