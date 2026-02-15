import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { extname, resolve } from "node:path";
import { z } from "zod";
import { requireRequestUserId } from "../auth/requestContext.js";
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

const profileImageUploadBody = z.object({
  file_name: z.string().max(255).optional(),
  content_type: z.string().max(100),
  data_base64: z.string().min(1),
});

const updateMyProfileBody = z
  .object({
    display_name: z.string().max(30).optional(),
    bio: z.string().max(160).optional(),
    avatar_url: z.string().url().max(2048).optional().nullable(),
  })
  .refine((value) => value.display_name !== undefined || value.bio !== undefined || value.avatar_url !== undefined, {
    message: "At least one field must be provided",
  });

const PROFILE_IMAGE_ROOT = resolve(process.cwd(), ".data/profile-images");

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
         where uf.followed_creator_user_id = $1) as followers_count,
        (select count(*)
         from user_follows uf
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
    const viewerUserId = req.lifecastAuth.userId;

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
          coalesce(cp.username, u.username, 'user_' || left(p.creator_user_id::text, 8)) as username,
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
        inner join users u on u.id = p.creator_user_id
        left join creator_profiles cp on cp.creator_user_id = p.creator_user_id
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
          p.creator_user_id,
          coalesce(cp.username, u.username, 'user_' || left(p.creator_user_id::text, 8)) as username,
          coalesce(cp.display_name, u.display_name) as display_name,
          p.title as project_title
        from projects p
        inner join users u on u.id = p.creator_user_id
        left join creator_profiles cp on cp.creator_user_id = p.creator_user_id
        where
          p.status in ('active', 'draft')
          and
          ($1 = ''
           or coalesce(cp.username, u.username, '') ilike '%' || $1 || '%'
           or coalesce(cp.display_name, u.display_name, '') ilike '%' || $1 || '%')
        order by p.created_at desc, username asc
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
      const viewerUserId = req.lifecastAuth.userId;
      const profileResult = await client.query<{
        creator_user_id: string;
        username: string;
        display_name: string | null;
        bio: string | null;
        avatar_url: string | null;
      }>(
        `
        select
          u.id as creator_user_id,
          coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
          coalesce(cp.display_name, u.display_name) as display_name,
          coalesce(cp.bio, u.bio) as bio,
          coalesce(cp.avatar_url, u.avatar_url) as avatar_url
        from users u
        left join creator_profiles cp on cp.creator_user_id = u.id
        where u.id = $1
        limit 1
      `,
        [creatorUserId],
      );

      if (profileResult.rowCount === 0) {
        return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "User not found"));
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
      const viewerUserId = req.lifecastAuth.userId;
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
                  and uf2.followed_creator_user_id = u.id
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
            u.id as creator_user_id,
            coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
            coalesce(cp.display_name, u.display_name) as display_name,
            coalesce(cp.bio, u.bio) as bio,
            coalesce(cp.avatar_url, u.avatar_url) as avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else u.id = $2::uuid end as is_self
          from listed l
          join users u on u.id = l.listed_creator_user_id
          left join creator_profiles cp on cp.creator_user_id = u.id
          left join lateral (
            select title
            from projects
            where creator_user_id = u.id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by username asc
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
            u.id as creator_user_id,
            coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
            coalesce(cp.display_name, u.display_name) as display_name,
            coalesce(cp.bio, u.bio) as bio,
            coalesce(cp.avatar_url, u.avatar_url) as avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else u.id = $2::uuid end as is_self
          from listed l
          join users u on u.id = l.listed_creator_user_id
          left join creator_profiles cp on cp.creator_user_id = u.id
          left join lateral (
            select title
            from projects
            where creator_user_id = u.id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by username asc
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
            u.id as creator_user_id,
            coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
            coalesce(cp.display_name, u.display_name) as display_name,
            coalesce(cp.bio, u.bio) as bio,
            coalesce(cp.avatar_url, u.avatar_url) as avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else u.id = $2::uuid end as is_self
          from listed l
          join users u on u.id = l.listed_creator_user_id
          left join creator_profiles cp on cp.creator_user_id = u.id
          left join lateral (
            select title
            from projects
            where creator_user_id = u.id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by username asc
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
    const profileUserId = requireRequestUserId(req, reply);
    if (!profileUserId) return;

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
                  and uf2.followed_creator_user_id = u.id
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
            u.id as creator_user_id,
            coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
            coalesce(cp.display_name, u.display_name) as display_name,
            coalesce(cp.bio, u.bio) as bio,
            coalesce(cp.avatar_url, u.avatar_url) as avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else u.id = $2::uuid end as is_self
          from listed l
          join users u on u.id = l.listed_creator_user_id
          left join creator_profiles cp on cp.creator_user_id = u.id
          left join lateral (
            select title
            from projects
            where creator_user_id = u.id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by username asc
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
            u.id as creator_user_id,
            coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
            coalesce(cp.display_name, u.display_name) as display_name,
            coalesce(cp.bio, u.bio) as bio,
            coalesce(cp.avatar_url, u.avatar_url) as avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else u.id = $2::uuid end as is_self
          from listed l
          join users u on u.id = l.listed_creator_user_id
          left join creator_profiles cp on cp.creator_user_id = u.id
          left join lateral (
            select title
            from projects
            where creator_user_id = u.id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by username asc
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
            u.id as creator_user_id,
            coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
            coalesce(cp.display_name, u.display_name) as display_name,
            coalesce(cp.bio, u.bio) as bio,
            coalesce(cp.avatar_url, u.avatar_url) as avatar_url,
            p.title as project_title,
            ${viewerFollowExpr} as is_following,
            case when $2::uuid is null then false else u.id = $2::uuid end as is_self
          from listed l
          join users u on u.id = l.listed_creator_user_id
          left join creator_profiles cp on cp.creator_user_id = u.id
          left join lateral (
            select title
            from projects
            where creator_user_id = u.id
              and status in ('active', 'draft')
            order by created_at desc
            limit 1
          ) p on true
          order by username asc
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

  app.get("/v1/me/profile", async (req, reply) => {
    const profileUserId = requireRequestUserId(req, reply);
    if (!profileUserId) return;

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
        select
          u.id as creator_user_id,
          coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
          coalesce(cp.display_name, u.display_name) as display_name,
          coalesce(cp.bio, u.bio) as bio,
          coalesce(cp.avatar_url, u.avatar_url) as avatar_url
        from users u
        left join creator_profiles cp on cp.creator_user_id = u.id
        where u.id = $1
        limit 1
      `,
        [profileUserId],
      );

      const profileStats = await loadProfileStats(client, profileUserId, profileUserId);
      const hasProfile = profileResult.rows.length > 0;
      const profile = hasProfile
        ? profileResult.rows[0]
        : {
            creator_user_id: profileUserId,
            username: `user_${profileUserId.slice(0, 8)}`,
            display_name: null,
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

  app.post("/v1/profiles/images", async (req, reply) => {
    const profileUserId = requireRequestUserId(req, reply);
    if (!profileUserId) return;

    const body = profileImageUploadBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid image payload"));
    }

    const contentType = body.data.content_type.toLowerCase().trim();
    if (!contentType.startsWith("image/")) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "content_type must be image/*"));
    }

    let data: Buffer;
    try {
      data = Buffer.from(body.data.data_base64, "base64");
    } catch {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid base64 image data"));
    }

    if (data.length === 0 || data.length > 8 * 1024 * 1024) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Image size must be between 1 byte and 8MB"));
    }

    const ext = (() => {
      if (contentType === "image/jpeg" || contentType === "image/jpg") return "jpg";
      if (contentType === "image/png") return "png";
      if (contentType === "image/webp") return "webp";
      if (contentType === "image/heic") return "heic";
      return "bin";
    })();

    const imageId = randomUUID();
    const fileName = `${imageId}.${ext}`;
    const filePath = resolve(PROFILE_IMAGE_ROOT, fileName);
    await mkdir(PROFILE_IMAGE_ROOT, { recursive: true });
    await writeFile(filePath, data);

    const imageUrl = `${req.protocol}://${req.headers.host}/v1/profiles/images/${fileName}`;
    return reply.send(ok({ image_url: imageUrl }));
  });

  app.get("/v1/profiles/images/:fileName", async (req, reply) => {
    const fileName = (req.params as { fileName: string }).fileName;
    const isValid = /^[0-9a-fA-F-]+\.(jpg|jpeg|png|webp|heic|bin)$/.test(fileName);
    if (!isValid) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid file name"));
    }

    const filePath = resolve(PROFILE_IMAGE_ROOT, fileName);
    let binary: Buffer;
    try {
      binary = await readFile(filePath);
    } catch {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Image not found"));
    }

    const ext = extname(fileName).toLowerCase();
    const responseType =
      ext === ".jpg" || ext === ".jpeg"
        ? "image/jpeg"
        : ext === ".png"
          ? "image/png"
          : ext === ".webp"
            ? "image/webp"
            : ext === ".heic"
              ? "image/heic"
              : "application/octet-stream";
    reply.type(responseType);
    return reply.send(binary);
  });

  app.patch("/v1/me/profile", async (req, reply) => {
    const profileUserId = requireRequestUserId(req, reply);
    if (!profileUserId) return;

    const body = updateMyProfileBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid profile payload"));
    }
    if (!hasDb() || !dbPool) {
      return reply.code(503).send(fail("SERVICE_UNAVAILABLE", "Database is not configured"));
    }

    const displayName =
      body.data.display_name === undefined ? undefined : body.data.display_name.trim() === "" ? null : body.data.display_name.trim();
    const bio = body.data.bio === undefined ? undefined : body.data.bio.trim() === "" ? null : body.data.bio.trim();
    if (displayName !== undefined && displayName !== null && displayName.length > 30) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "display_name must be <= 30 chars"));
    }
    if (bio !== undefined && bio !== null && bio.length > 160) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "bio must be <= 160 chars"));
    }

    const avatarUrl = body.data.avatar_url === undefined ? undefined : body.data.avatar_url;

    const client = await dbPool.connect();
    try {
      await client.query("begin");

      const current = await client.query<{
        display_name: string | null;
        bio: string | null;
        avatar_url: string | null;
      }>(
        `
        select display_name, bio, avatar_url
        from users
        where id = $1
        limit 1
      `,
        [profileUserId],
      );
      if (current.rows.length === 0) {
        await client.query("rollback");
        return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "User not found"));
      }

      const nextDisplayName = displayName === undefined ? current.rows[0].display_name : displayName;
      const nextBio = bio === undefined ? current.rows[0].bio : bio;
      const nextAvatarUrl = avatarUrl === undefined ? current.rows[0].avatar_url : avatarUrl;

      await client.query(
        `
        update users
        set
          display_name = $2,
          bio = $3,
          avatar_url = $4,
          updated_at = now()
        where id = $1
      `,
        [profileUserId, nextDisplayName, nextBio, nextAvatarUrl],
      );

      await client.query(
        `
        insert into creator_profiles (creator_user_id, username, display_name, bio, avatar_url, created_at, updated_at)
        select
          u.id,
          coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)),
          $2,
          $3,
          $4,
          now(),
          now()
        from users u
        left join creator_profiles cp on cp.creator_user_id = u.id
        where u.id = $1
        on conflict (creator_user_id)
        do update set
          display_name = excluded.display_name,
          bio = excluded.bio,
          avatar_url = excluded.avatar_url,
          updated_at = now()
      `,
        [profileUserId, nextDisplayName, nextBio, nextAvatarUrl],
      );

      const profileResult = await client.query<{
        creator_user_id: string;
        username: string;
        display_name: string | null;
        bio: string | null;
        avatar_url: string | null;
      }>(
        `
        select
          u.id as creator_user_id,
          coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
          coalesce(cp.display_name, u.display_name) as display_name,
          coalesce(cp.bio, u.bio) as bio,
          coalesce(cp.avatar_url, u.avatar_url) as avatar_url
        from users u
        left join creator_profiles cp on cp.creator_user_id = u.id
        where u.id = $1
        limit 1
      `,
        [profileUserId],
      );
      const profileStats = await loadProfileStats(client, profileUserId, profileUserId);
      await client.query("commit");

      return reply.send(
        ok({
          profile: profileResult.rows[0],
          profile_stats: profileStats,
        }),
      );
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  });

  app.post("/v1/creators/:creatorUserId/follow", async (req, reply) => {
    const viewerUserId = requireRequestUserId(req, reply);
    if (!viewerUserId) return;

    const creatorUserId = (req.params as { creatorUserId: string }).creatorUserId;
    if (!z.string().uuid().safeParse(creatorUserId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid creator id"));
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
    const viewerUserId = requireRequestUserId(req, reply);
    if (!viewerUserId) return;

    const creatorUserId = (req.params as { creatorUserId: string }).creatorUserId;
    if (!z.string().uuid().safeParse(creatorUserId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid creator id"));
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
