import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { randomUUID } from "node:crypto";
import { extname } from "node:path";
import { z } from "zod";
import { requireRequestUserId } from "../auth/requestContext.js";
import { fail, ok } from "../response.js";
import { dbPool, hasDb } from "../store/db.js";
import { store } from "../store/hybridStore.js";
import { readImageBinary, writeImageBinary } from "../store/services/imageStorageService.js";
import { buildPublicAppUrl, getPublicBaseUrl, normalizeLegacyLocalAssetUrl, normalizeLegacyLocalAssetUrls } from "../url/publicAssetUrl.js";

const discoverQuery = z.object({
  query: z.string().max(80).optional(),
  limit: z.coerce.number().int().min(1).max(50).optional(),
});

const discoverVideosQuery = z.object({
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

const supportedProjectsQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).optional(),
});

const videoCommentsQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).optional(),
});

const createVideoCommentBody = z.object({
  body: z.string().trim().min(1).max(400),
});

const profileImageUploadBody = z.object({
  file_name: z.string().max(255).optional(),
  content_type: z.string().max(100),
  data_base64: z.string().min(1),
});

const updateMyProfileBody = z
  .object({
    username: z.string().max(40).optional(),
    display_name: z.string().max(30).optional(),
    bio: z.string().max(160).optional(),
    avatar_url: z.string().url().max(2048).optional().nullable(),
  })
  .refine((value) => value.username !== undefined || value.display_name !== undefined || value.bio !== undefined || value.avatar_url !== undefined, {
    message: "At least one field must be provided",
  });

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

async function loadSupportedProjects(client: PoolClient, supporterUserId: string, limit: number) {
  const rows = await client.query<{
    support_id: string;
    project_id: string;
    supported_at: string;
    amount_minor: string | number;
    currency: string;
    project_title: string;
    project_subtitle: string | null;
    project_image_url: string | null;
    project_goal_amount_minor: string | number;
    project_funded_amount_minor: string | number;
    project_currency: string;
    project_supporter_count: string | number;
    creator_user_id: string;
    creator_username: string;
    creator_display_name: string | null;
  }>(
    `
      select
        st.id as support_id,
        st.project_id,
        coalesce(st.succeeded_at, st.confirmed_at, st.created_at) as supported_at,
        st.amount_minor,
        st.currency,
        p.title as project_title,
        p.subtitle as project_subtitle,
        p.cover_image_url as project_image_url,
        p.goal_amount_minor as project_goal_amount_minor,
        coalesce((
          select sum(st_sum.amount_minor)
          from support_transactions st_sum
          where st_sum.project_id = p.id
            and st_sum.status = 'succeeded'
        ), 0) as project_funded_amount_minor,
        p.currency as project_currency,
        (
          select count(*)
          from support_transactions st2
          where st2.project_id = p.id
            and st2.status = 'succeeded'
        ) as project_supporter_count,
        p.creator_user_id,
        coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as creator_username,
        coalesce(cp.display_name, u.display_name) as creator_display_name
      from support_transactions st
      join projects p on p.id = st.project_id
      join users u on u.id = p.creator_user_id
      left join creator_profiles cp on cp.creator_user_id = u.id
      where st.supporter_user_id = $1
        and st.status = 'succeeded'
      order by coalesce(st.succeeded_at, st.confirmed_at, st.created_at) desc
      limit $2
    `,
    [supporterUserId, limit],
  );

  return rows.rows.map((row) => ({
    support_id: row.support_id,
    project_id: row.project_id,
    supported_at: row.supported_at,
    amount_minor: Number(row.amount_minor ?? 0),
    currency: row.currency,
    project_title: row.project_title,
    project_subtitle: row.project_subtitle,
    project_image_url: normalizeLegacyLocalAssetUrl(row.project_image_url),
    project_goal_amount_minor: Number(row.project_goal_amount_minor ?? 0),
    project_funded_amount_minor: Number(row.project_funded_amount_minor ?? 0),
    project_currency: row.project_currency,
    project_supporter_count: Number(row.project_supporter_count ?? 0),
    creator_user_id: row.creator_user_id,
    creator_username: row.creator_username,
    creator_display_name: row.creator_display_name,
  }));
}

async function loadVideoEngagement(client: PoolClient, videoId: string, viewerUserId: string | null) {
  const result = await client.query<{
    likes: string | number;
    comments: string | number;
    is_liked_by_current_user: boolean;
  }>(
    `
      select
        coalesce((
          select count(*)
          from video_likes vl
          where vl.video_id = $1
        ), 0) as likes,
        coalesce((
          select count(*)
          from video_comments vc
          where vc.video_id = $1
        ), 0) as comments,
        case
          when $2::uuid is null then false
          else exists(
            select 1
            from video_likes vl
            where vl.video_id = $1
              and vl.user_id = $2::uuid
          )
        end as is_liked_by_current_user
    `,
    [videoId, viewerUserId],
  );

  return {
    likes: Number(result.rows[0]?.likes ?? 0),
    comments: Number(result.rows[0]?.comments ?? 0),
    is_liked_by_current_user: Boolean(result.rows[0]?.is_liked_by_current_user),
  };
}

async function loadCommentEngagement(client: PoolClient, commentId: string, viewerUserId: string | null) {
  const result = await client.query<{
    likes: string | number;
    is_liked_by_current_user: boolean;
  }>(
    `
      select
        coalesce((
          select count(*)
          from video_comment_likes vcl
          where vcl.comment_id = $1
        ), 0) as likes,
        case
          when $2::uuid is null then false
          else exists(
            select 1
            from video_comment_likes vcl
            where vcl.comment_id = $1
              and vcl.user_id = $2::uuid
          )
        end as is_liked_by_current_user
    `,
    [commentId, viewerUserId],
  );

  return {
    likes: Number(result.rows[0]?.likes ?? 0),
    is_liked_by_current_user: Boolean(result.rows[0]?.is_liked_by_current_user),
  };
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
      const publicBaseUrl = getPublicBaseUrl();
      const result = await client.query<{
        project_id: string;
        creator_user_id: string;
        username: string;
        creator_avatar_url: string | null;
        caption: string | null;
        video_id: string | null;
        min_plan_price_minor: string | number;
        goal_amount_minor: string | number;
        funded_amount_minor: string | number;
        remaining_days: string | number;
        likes: string | number;
        comments: string | number;
        is_liked_by_current_user: boolean;
        is_supported_by_current_user: boolean;
      }>(
        `
        select
          p.id as project_id,
          p.creator_user_id,
          coalesce(cp.username, u.username, 'user_' || left(p.creator_user_id::text, 8)) as username,
          coalesce(cp.avatar_url, u.avatar_url) as creator_avatar_url,
          coalesce(
            nullif(concat_ws(' · ', p.title, nullif(p.subtitle, '')), ''),
            nullif(p.description, ''),
            'Project update'
          ) as caption,
          latest_video.video_id,
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
          coalesce((
            select count(*)
            from video_likes vl
            where vl.video_id = latest_video.video_id
          ), 0) as likes,
          coalesce((
            select count(*)
            from video_comments vc
            where vc.video_id = latest_video.video_id
          ), 0) as comments,
          case
            when $1::uuid is null then false
            else exists(
              select 1
              from video_likes vl
              where vl.video_id = latest_video.video_id
                and vl.user_id = $1::uuid
            )
          end as is_liked_by_current_user,
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
          select
            va.video_id
          from video_assets va
          where va.creator_user_id = p.creator_user_id
            and va.status = 'ready'
          order by va.created_at desc
          limit 1
        ) latest_video on true
        left join lateral (
          select price_minor
          from project_plans
          where project_id = p.id
          order by price_minor asc, created_at asc
          limit 1
        ) min_plan on true
        where p.status in ('active', 'draft')
          and latest_video.video_id is not null
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
            creator_avatar_url: normalizeLegacyLocalAssetUrl(row.creator_avatar_url),
            caption: row.caption ?? "Project update",
            video_id: row.video_id,
            playback_url: row.video_id ? `${publicBaseUrl}/v1/videos/${row.video_id}/playback` : null,
            thumbnail_url: row.video_id ? `${publicBaseUrl}/v1/videos/${row.video_id}/thumbnail` : null,
            min_plan_price_minor: Number(row.min_plan_price_minor),
            goal_amount_minor: Number(row.goal_amount_minor),
            funded_amount_minor: Number(row.funded_amount_minor),
            remaining_days: Number(row.remaining_days),
            likes: Number(row.likes),
            comments: Number(row.comments),
            is_liked_by_current_user: row.is_liked_by_current_user,
            is_supported_by_current_user: row.is_supported_by_current_user,
          })),
        }),
      );
    } finally {
      client.release();
    }
  });

  app.get("/v1/videos/:videoId/engagement", async (req, reply) => {
    const videoId = (req.params as { videoId: string }).videoId;
    if (!z.string().uuid().safeParse(videoId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid video id"));
    }
    if (!hasDb() || !dbPool) {
      return reply.send(ok({ likes: 0, comments: 0, is_liked_by_current_user: false }));
    }

    const viewerUserId = req.lifecastAuth.userId;
    const client = await dbPool.connect();
    try {
      const exists = await client.query<{ video_id: string }>(
        `
        select video_id
        from video_assets
        where video_id = $1
        limit 1
      `,
        [videoId],
      );
      if (exists.rows.length === 0) {
        return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Video not found"));
      }
      const metrics = await loadVideoEngagement(client, videoId, viewerUserId);
      return reply.send(ok(metrics));
    } finally {
      client.release();
    }
  });

  app.put("/v1/videos/:videoId/like", async (req, reply) => {
    const viewerUserId = requireRequestUserId(req, reply);
    if (!viewerUserId) return;
    const videoId = (req.params as { videoId: string }).videoId;
    if (!z.string().uuid().safeParse(videoId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid video id"));
    }
    if (!hasDb() || !dbPool) {
      return reply.send(ok({ likes: 0, comments: 0, is_liked_by_current_user: true }));
    }

    const client = await dbPool.connect();
    try {
      const exists = await client.query<{ video_id: string }>(
        `
        select video_id
        from video_assets
        where video_id = $1
        limit 1
      `,
        [videoId],
      );
      if (exists.rows.length === 0) {
        return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Video not found"));
      }
      await client.query(
        `
        insert into video_likes (video_id, user_id, created_at)
        values ($1, $2, now())
        on conflict do nothing
      `,
        [videoId, viewerUserId],
      );
      const metrics = await loadVideoEngagement(client, videoId, viewerUserId);
      return reply.send(ok(metrics));
    } finally {
      client.release();
    }
  });

  app.delete("/v1/videos/:videoId/like", async (req, reply) => {
    const viewerUserId = requireRequestUserId(req, reply);
    if (!viewerUserId) return;
    const videoId = (req.params as { videoId: string }).videoId;
    if (!z.string().uuid().safeParse(videoId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid video id"));
    }
    if (!hasDb() || !dbPool) {
      return reply.send(ok({ likes: 0, comments: 0, is_liked_by_current_user: false }));
    }

    const client = await dbPool.connect();
    try {
      await client.query(
        `
        delete from video_likes
        where video_id = $1
          and user_id = $2
      `,
        [videoId, viewerUserId],
      );
      const metrics = await loadVideoEngagement(client, videoId, viewerUserId);
      return reply.send(ok(metrics));
    } finally {
      client.release();
    }
  });

  app.get("/v1/videos/:videoId/comments", async (req, reply) => {
    const videoId = (req.params as { videoId: string }).videoId;
    if (!z.string().uuid().safeParse(videoId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid video id"));
    }
    const parsed = videoCommentsQuery.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid comments query"));
    }
    const limit = parsed.data.limit ?? 50;
    if (!hasDb() || !dbPool) {
      return reply.send(ok({ rows: [] }));
    }

    const viewerUserId = req.lifecastAuth.userId;
    const client = await dbPool.connect();
    try {
      const rows = await client.query<{
        comment_id: string;
        user_id: string;
        username: string;
        display_name: string | null;
        body: string;
        created_at: string;
        likes: string | number;
        is_liked_by_current_user: boolean;
        is_supporter: boolean;
      }>(
        `
        select
          vc.id as comment_id,
          vc.user_id,
          coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
          coalesce(cp.display_name, u.display_name) as display_name,
          vc.body,
          vc.created_at,
          coalesce((
            select count(*)
            from video_comment_likes vcl
            where vcl.comment_id = vc.id
          ), 0) as likes,
          case
            when $3::uuid is null then false
            else exists(
              select 1
              from video_comment_likes vcl
              where vcl.comment_id = vc.id
                and vcl.user_id = $3::uuid
            )
          end as is_liked_by_current_user,
          exists(
            select 1
            from video_assets va
            join support_transactions st on st.supporter_user_id = vc.user_id
            join projects p on p.id = st.project_id
            where va.video_id = vc.video_id
              and p.creator_user_id = va.creator_user_id
              and st.status = 'succeeded'
          ) as is_supporter
        from video_comments vc
        join users u on u.id = vc.user_id
        left join creator_profiles cp on cp.creator_user_id = vc.user_id
        where vc.video_id = $1
        order by vc.created_at desc
        limit $2
      `,
        [videoId, limit, viewerUserId],
      );
      return reply.send(
        ok({
          rows: rows.rows.map((row) => ({
            comment_id: row.comment_id,
            user_id: row.user_id,
            username: row.username,
            display_name: row.display_name,
            body: row.body,
            created_at: row.created_at,
            likes: Number(row.likes),
            is_liked_by_current_user: row.is_liked_by_current_user,
            is_supporter: row.is_supporter,
          })),
        }),
      );
    } finally {
      client.release();
    }
  });

  app.post("/v1/videos/:videoId/comments", async (req, reply) => {
    const viewerUserId = requireRequestUserId(req, reply);
    if (!viewerUserId) return;
    const videoId = (req.params as { videoId: string }).videoId;
    if (!z.string().uuid().safeParse(videoId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid video id"));
    }
    const body = createVideoCommentBody.safeParse(req.body ?? {});
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid comment payload"));
    }
    if (!hasDb() || !dbPool) {
      return reply.send(
        ok({
          comment: {
            comment_id: randomUUID(),
            user_id: viewerUserId,
            username: "you",
            display_name: null,
            body: body.data.body,
            created_at: new Date().toISOString(),
            likes: 0,
            is_liked_by_current_user: false,
            is_supporter: false,
          },
        }),
      );
    }

    const client = await dbPool.connect();
    try {
      const inserted = await client.query<{
        comment_id: string;
        user_id: string;
        username: string;
        display_name: string | null;
        body: string;
        created_at: string;
        is_supporter: boolean;
      }>(
        `
        with inserted as (
          insert into video_comments (video_id, user_id, body, created_at)
          values ($1, $2, $3, now())
          returning id, video_id, user_id, body, created_at
        )
        select
          i.id as comment_id,
          i.user_id,
          coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
          coalesce(cp.display_name, u.display_name) as display_name,
          i.body,
          i.created_at,
          exists(
            select 1
            from video_assets va
            join support_transactions st on st.supporter_user_id = i.user_id
            join projects p on p.id = st.project_id
            where va.video_id = i.video_id
              and p.creator_user_id = va.creator_user_id
              and st.status = 'succeeded'
          ) as is_supporter
        from inserted i
        join users u on u.id = i.user_id
        left join creator_profiles cp on cp.creator_user_id = i.user_id
      `,
        [videoId, viewerUserId, body.data.body],
      );
      if (inserted.rows.length === 0) {
        return reply.code(500).send(fail("INTERNAL_ERROR", "Failed to create comment"));
      }
      return reply.send(
        ok({
          comment: {
            comment_id: inserted.rows[0].comment_id,
            user_id: inserted.rows[0].user_id,
            username: inserted.rows[0].username,
            display_name: inserted.rows[0].display_name,
            body: inserted.rows[0].body,
            created_at: inserted.rows[0].created_at,
            likes: 0,
            is_liked_by_current_user: false,
            is_supporter: inserted.rows[0].is_supporter,
          },
        }),
      );
    } catch (error) {
      const pgError = error as { code?: string };
      if (pgError.code === "23503") {
        return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Video not found"));
      }
      throw error;
    } finally {
      client.release();
    }
  });

  app.put("/v1/videos/:videoId/comments/:commentId/like", async (req, reply) => {
    const viewerUserId = requireRequestUserId(req, reply);
    if (!viewerUserId) return;
    const { videoId, commentId } = req.params as { videoId: string; commentId: string };
    if (!z.string().uuid().safeParse(videoId).success || !z.string().uuid().safeParse(commentId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid video id or comment id"));
    }
    if (!hasDb() || !dbPool) {
      return reply.send(ok({ likes: 0, is_liked_by_current_user: true }));
    }

    const client = await dbPool.connect();
    try {
      const comment = await client.query<{ id: string }>(
        `
        select id
        from video_comments
        where id = $1
          and video_id = $2
        limit 1
      `,
        [commentId, videoId],
      );
      if (comment.rows.length === 0) {
        return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Comment not found"));
      }
      await client.query(
        `
        insert into video_comment_likes (comment_id, user_id, created_at)
        values ($1, $2, now())
        on conflict do nothing
      `,
        [commentId, viewerUserId],
      );
      const engagement = await loadCommentEngagement(client, commentId, viewerUserId);
      return reply.send(ok(engagement));
    } finally {
      client.release();
    }
  });

  app.delete("/v1/videos/:videoId/comments/:commentId/like", async (req, reply) => {
    const viewerUserId = requireRequestUserId(req, reply);
    if (!viewerUserId) return;
    const { videoId, commentId } = req.params as { videoId: string; commentId: string };
    if (!z.string().uuid().safeParse(videoId).success || !z.string().uuid().safeParse(commentId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid video id or comment id"));
    }
    if (!hasDb() || !dbPool) {
      return reply.send(ok({ likes: 0, is_liked_by_current_user: false }));
    }

    const client = await dbPool.connect();
    try {
      const comment = await client.query<{ id: string }>(
        `
        select id
        from video_comments
        where id = $1
          and video_id = $2
        limit 1
      `,
        [commentId, videoId],
      );
      if (comment.rows.length === 0) {
        return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Comment not found"));
      }
      await client.query(
        `
        delete from video_comment_likes
        where comment_id = $1
          and user_id = $2
      `,
        [commentId, viewerUserId],
      );
      const engagement = await loadCommentEngagement(client, commentId, viewerUserId);
      return reply.send(ok(engagement));
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
              display_name: "Lifecast Maker",
              project_title: "Lifecast Dev Project",
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
          u.id as creator_user_id,
          coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
          coalesce(cp.display_name, u.display_name) as display_name,
          p.title as project_title
        from users u
        left join creator_profiles cp on cp.creator_user_id = u.id
        left join lateral (
          select
            pr.title,
            pr.created_at
          from projects pr
          where pr.creator_user_id = u.id
            and pr.status in ('active', 'draft')
          order by
            case when pr.status = 'active' then 0 else 1 end,
            pr.created_at desc
          limit 1
        ) p on true
        where
          ($1 = ''
           or coalesce(cp.username, u.username, '') ilike '%' || $1 || '%'
           or coalesce(cp.display_name, u.display_name, '') ilike '%' || $1 || '%')
        order by
          case when p.title is null then 1 else 0 end,
          p.created_at desc nulls last,
          username asc
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

  app.get("/v1/discover/videos", async (req, reply) => {
    const parsed = discoverVideosQuery.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid discover videos query"));
    }

    const query = (parsed.data.query ?? "").trim();
    const limit = parsed.data.limit ?? 20;

    if (!hasDb() || !dbPool) {
      return reply.send(
        ok({
          rows: [],
        }),
      );
    }

    const client = await dbPool.connect();
    try {
      const publicBaseUrl = getPublicBaseUrl();
      const result = await client.query<{
        video_id: string;
        creator_user_id: string;
        username: string;
        display_name: string | null;
        file_name: string;
        project_title: string | null;
        created_at: string;
      }>(
        `
        select
          va.video_id,
          va.creator_user_id,
          coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
          coalesce(cp.display_name, u.display_name) as display_name,
          vus.file_name,
          p.title as project_title,
          va.created_at
        from video_assets va
        inner join users u on u.id = va.creator_user_id
        inner join video_upload_sessions vus on vus.id = va.upload_session_id
        left join creator_profiles cp on cp.creator_user_id = u.id
        left join lateral (
          select
            pr.title
          from projects pr
          where pr.creator_user_id = u.id
            and pr.status in ('active', 'draft')
          order by
            case when pr.status = 'active' then 0 else 1 end,
            pr.created_at desc
          limit 1
        ) p on true
        where
          va.status = 'ready'
          and
          ($1 = ''
            or coalesce(cp.username, u.username, '') ilike '%' || $1 || '%'
            or coalesce(cp.display_name, u.display_name, '') ilike '%' || $1 || '%'
            or vus.file_name ilike '%' || $1 || '%'
            or coalesce(p.title, '') ilike '%' || $1 || '%')
        order by
          case
            when lower(vus.file_name) = lower($1) then 0
            when coalesce(cp.username, u.username, '') ilike $1 || '%' then 1
            when vus.file_name ilike $1 || '%' then 2
            else 3
          end,
          va.created_at desc
        limit $2
      `,
        [query, limit],
      );

      return reply.send(
        ok({
          rows: result.rows.map((row) => ({
            video_id: row.video_id,
            creator_user_id: row.creator_user_id,
            username: row.username,
            display_name: row.display_name,
            file_name: row.file_name,
            project_title: row.project_title,
            playback_url: `${publicBaseUrl}/v1/videos/${row.video_id}/playback`,
            thumbnail_url: `${publicBaseUrl}/v1/videos/${row.video_id}/thumbnail`,
            created_at: row.created_at,
          })),
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
                image_url: normalizeLegacyLocalAssetUrl(project.imageUrl),
                image_urls: normalizeLegacyLocalAssetUrls(project.imageUrls),
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
                detail_blocks: project.detailBlocks,
                created_at: project.createdAt,
                minimum_plan: project.minimumPlan
                  ? {
                      id: project.minimumPlan.id,
                      name: project.minimumPlan.name,
                      price_minor: project.minimumPlan.priceMinor,
                      reward_summary: project.minimumPlan.rewardSummary,
                      description: project.minimumPlan.description,
                      image_url: normalizeLegacyLocalAssetUrl(project.minimumPlan.imageUrl),
                      currency: project.minimumPlan.currency,
                    }
                  : null,
                plans: project.plans.map((plan) => ({
                  id: plan.id,
                  name: plan.name,
                  price_minor: plan.priceMinor,
                  reward_summary: plan.rewardSummary,
                  description: plan.description,
                  image_url: normalizeLegacyLocalAssetUrl(plan.imageUrl),
                  currency: plan.currency,
                })),
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
          profile: {
            ...profileResult.rows[0],
            avatar_url: normalizeLegacyLocalAssetUrl(profileResult.rows[0].avatar_url),
          },
          viewer_relationship: relationship,
          profile_stats: profileStats,
          project: project
            ? {
                id: project.id,
                creator_user_id: project.creatorUserId,
                title: project.title,
                subtitle: project.subtitle,
                image_url: normalizeLegacyLocalAssetUrl(project.imageUrl),
                image_urls: normalizeLegacyLocalAssetUrls(project.imageUrls),
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
                detail_blocks: project.detailBlocks,
                created_at: project.createdAt,
                minimum_plan: project.minimumPlan
                  ? {
                      id: project.minimumPlan.id,
                      name: project.minimumPlan.name,
                      price_minor: project.minimumPlan.priceMinor,
                      reward_summary: project.minimumPlan.rewardSummary,
                      description: project.minimumPlan.description,
                      image_url: normalizeLegacyLocalAssetUrl(project.minimumPlan.imageUrl),
                      currency: project.minimumPlan.currency,
                    }
                  : null,
                plans: project.plans.map((plan) => ({
                  id: plan.id,
                  name: plan.name,
                  price_minor: plan.priceMinor,
                  reward_summary: plan.rewardSummary,
                  description: plan.description,
                    image_url: normalizeLegacyLocalAssetUrl(plan.imageUrl),
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
          rows: rows.rows.map((row) => ({
            ...row,
            avatar_url: normalizeLegacyLocalAssetUrl(row.avatar_url),
          })),
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
          rows: rows.rows.map((row) => ({
            ...row,
            avatar_url: normalizeLegacyLocalAssetUrl(row.avatar_url),
          })),
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
            display_name: "Lifecast Maker",
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
      const normalizedProfile = {
        ...profile,
        avatar_url: normalizeLegacyLocalAssetUrl(profile.avatar_url),
      };
      return reply.send(
        ok({
          profile: normalizedProfile,
          profile_stats: profileStats,
        }),
      );
    } finally {
      client.release();
    }
  });

  app.get("/v1/creators/:creatorUserId/supported-projects", async (req, reply) => {
    const parsed = supportedProjectsQuery.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid supported-projects query"));
    }
    const limit = parsed.data.limit ?? 30;
    const creatorUserIdResult = z.string().uuid().safeParse((req.params as { creatorUserId?: string }).creatorUserId);
    if (!creatorUserIdResult.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "creatorUserId must be UUID"));
    }
    const creatorUserId = creatorUserIdResult.data;

    if (!hasDb() || !dbPool) {
      return reply.send(ok({ rows: [] }));
    }

    const client = await dbPool.connect();
    try {
      const rows = await loadSupportedProjects(client, creatorUserId, limit);
      return reply.send(ok({ rows }));
    } finally {
      client.release();
    }
  });

  app.get("/v1/me/supported-projects", async (req, reply) => {
    const profileUserId = requireRequestUserId(req, reply);
    if (!profileUserId) return;

    const parsed = supportedProjectsQuery.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid supported-projects query"));
    }
    const limit = parsed.data.limit ?? 30;

    if (!hasDb() || !dbPool) {
      return reply.send(ok({ rows: [] }));
    }

    const client = await dbPool.connect();
    try {
      const rows = await loadSupportedProjects(client, profileUserId, limit);
      return reply.send(ok({ rows }));
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
    await writeImageBinary({
      kind: "profiles",
      fileName,
      contentType,
      data,
    });

    const imageUrl = buildPublicAppUrl(`/v1/profiles/images/${fileName}`);
    return reply.send(ok({ image_url: imageUrl }));
  });

  app.get("/v1/profiles/images/:fileName", async (req, reply) => {
    const fileName = (req.params as { fileName: string }).fileName;
    const isValid = /^[0-9a-fA-F-]+\.(jpg|jpeg|png|webp|heic|bin)$/.test(fileName);
    if (!isValid) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid file name"));
    }

    let binary: Buffer;
    try {
      binary = await readImageBinary({ kind: "profiles", fileName });
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

    const username = body.data.username === undefined ? undefined : body.data.username.trim();
    if (username !== undefined) {
      if (username.length < 3 || username.length > 40) {
        return reply.code(400).send(fail("VALIDATION_ERROR", "username must be 3-40 chars"));
      }
      if (!/^[A-Za-z0-9_]+$/.test(username)) {
        return reply.code(400).send(fail("VALIDATION_ERROR", "username must contain only letters, numbers, and underscore"));
      }
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
        username: string;
        display_name: string | null;
        bio: string | null;
        avatar_url: string | null;
      }>(
        `
        select
          coalesce(username, 'user_' || left(id::text, 8)) as username,
          display_name,
          bio,
          avatar_url
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

      const nextUsername = username === undefined ? current.rows[0].username : username;
      const nextDisplayName = displayName === undefined ? current.rows[0].display_name : displayName;
      const nextBio = bio === undefined ? current.rows[0].bio : bio;
      const nextAvatarUrl = avatarUrl === undefined ? current.rows[0].avatar_url : avatarUrl;

      await client.query(
        `
        update users
        set
          username = $2,
          display_name = $3,
          bio = $4,
          avatar_url = $5,
          updated_at = now()
        where id = $1
      `,
        [profileUserId, nextUsername, nextDisplayName, nextBio, nextAvatarUrl],
      );

      await client.query(
        `
        insert into creator_profiles (creator_user_id, username, display_name, bio, avatar_url, created_at, updated_at)
        values (
          $1,
          $2,
          $3,
          $4,
          $5,
          now(),
          now()
        )
        on conflict (creator_user_id)
        do update set
          username = excluded.username,
          display_name = excluded.display_name,
          bio = excluded.bio,
          avatar_url = excluded.avatar_url,
          updated_at = now()
      `,
        [profileUserId, nextUsername, nextDisplayName, nextBio, nextAvatarUrl],
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
          profile: {
            ...profileResult.rows[0],
            avatar_url: normalizeLegacyLocalAssetUrl(profileResult.rows[0].avatar_url),
          },
          profile_stats: profileStats,
        }),
      );
    } catch (error) {
      await client.query("rollback");
      const pgError = error as { code?: string };
      if (pgError.code === "23505") {
        return reply.code(409).send(fail("STATE_CONFLICT", "username is already taken"));
      }
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
