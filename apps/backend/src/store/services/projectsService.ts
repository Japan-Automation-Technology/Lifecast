import { randomUUID } from "node:crypto";
import { dbPool, hasDb } from "../db.js";
import type { InMemoryStore } from "../inMemory.js";

function toIso(value: Date | string) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

export class ProjectsService {
  constructor(private readonly memory: InMemoryStore) {}
  async getProjectByCreator(creatorUserId: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.getProjectByCreator(creatorUserId);
    }

    const client = await dbPool.connect();
    try {
      const project = await client.query<{
        id: string;
        title: string;
        subtitle: string | null;
        cover_image_url: string | null;
        category: string | null;
        location: string | null;
        status: string;
        goal_amount_minor: string | number;
        currency: string;
        duration_days: number | null;
        deadline_at: string | Date;
        description: string | null;
        external_urls: unknown;
        funded_amount_minor: string | number;
        supporter_count: string | number;
        support_count_total: string | number;
        created_at: string | Date;
      }>(
        `
        select
          id,
          title,
          subtitle,
          cover_image_url,
          category,
          location,
          status,
          goal_amount_minor,
          currency,
          duration_days,
          deadline_at,
          description,
          external_urls,
          coalesce((
            select sum(st.amount_minor)
            from support_transactions st
            where st.project_id = projects.id and st.status = 'succeeded'
          ), 0) as funded_amount_minor,
          coalesce((
            select count(*)
            from support_transactions st
            where st.project_id = projects.id and st.status = 'succeeded'
          ), 0) as supporter_count,
          coalesce((
            select count(*)
            from support_transactions st
            where st.project_id = projects.id
          ), 0) as support_count_total,
          created_at
        from projects
        where creator_user_id = $1
          and status in ('active', 'draft')
        order by created_at desc
        limit 1
      `,
        [creatorUserId],
      );
      if (project.rowCount === 0) return null;
      const row = project.rows[0];

      const plans = await client.query<{
        id: string;
        name: string;
        price_minor: string | number;
        reward_summary: string;
        description: string | null;
        image_url: string | null;
        currency: string;
      }>(
        `
        select id, name, price_minor, reward_summary, description, image_url, currency
        from project_plans
        where project_id = $1
        order by price_minor asc, created_at asc
      `,
        [row.id],
      );
      const mappedPlans = plans.rows.map((plan) => ({
        id: plan.id,
        name: plan.name,
        priceMinor: Number(plan.price_minor),
        rewardSummary: plan.reward_summary,
        description: plan.description,
        imageUrl: plan.image_url,
        currency: plan.currency,
      }));

      return {
        id: row.id,
        creatorUserId,
        title: row.title,
        subtitle: row.subtitle,
        imageUrl: row.cover_image_url,
        category: row.category,
        location: row.location,
        status: row.status,
        goalAmountMinor: Number(row.goal_amount_minor),
        currency: row.currency,
        durationDays: row.duration_days,
        deadlineAt: toIso(row.deadline_at),
        description: row.description,
        urls: Array.isArray(row.external_urls) ? (row.external_urls as string[]) : [],
        fundedAmountMinor: Number(row.funded_amount_minor),
        supporterCount: Number(row.supporter_count),
        supportCountTotal: Number(row.support_count_total),
        createdAt: toIso(row.created_at),
        minimumPlan: mappedPlans[0] ?? null,
        plans: mappedPlans,
      };
    } finally {
      client.release();
    }
  }

  async listProjectsByCreator(creatorUserId: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.listProjectsByCreator(creatorUserId);
    }

    const client = await dbPool.connect();
    try {
      const projects = await client.query<{
        id: string;
        title: string;
        subtitle: string | null;
        cover_image_url: string | null;
        category: string | null;
        location: string | null;
        status: string;
        goal_amount_minor: string | number;
        currency: string;
        duration_days: number | null;
        deadline_at: string | Date;
        description: string | null;
        external_urls: unknown;
        funded_amount_minor: string | number;
        supporter_count: string | number;
        support_count_total: string | number;
        created_at: string | Date;
      }>(
        `
        select
          id,
          title,
          subtitle,
          cover_image_url,
          category,
          location,
          status,
          goal_amount_minor,
          currency,
          duration_days,
          deadline_at,
          description,
          external_urls,
          coalesce((
            select sum(st.amount_minor)
            from support_transactions st
            where st.project_id = projects.id and st.status = 'succeeded'
          ), 0) as funded_amount_minor,
          coalesce((
            select count(*)
            from support_transactions st
            where st.project_id = projects.id and st.status = 'succeeded'
          ), 0) as supporter_count,
          coalesce((
            select count(*)
            from support_transactions st
            where st.project_id = projects.id
          ), 0) as support_count_total,
          created_at
        from projects
        where creator_user_id = $1
        order by
          case when status in ('active', 'draft') then 0 else 1 end,
          created_at desc
      `,
        [creatorUserId],
      );

      const rows = [];
      for (const row of projects.rows) {
        const plans = await client.query<{
          id: string;
          name: string;
          price_minor: string | number;
          reward_summary: string;
          description: string | null;
          image_url: string | null;
          currency: string;
        }>(
          `
          select id, name, price_minor, reward_summary, description, image_url, currency
          from project_plans
          where project_id = $1
          order by price_minor asc, created_at asc
        `,
          [row.id],
        );
        const mappedPlans = plans.rows.map((plan) => ({
          id: plan.id,
          name: plan.name,
          priceMinor: Number(plan.price_minor),
          rewardSummary: plan.reward_summary,
          description: plan.description,
          imageUrl: plan.image_url,
          currency: plan.currency,
        }));

        rows.push({
          id: row.id,
          creatorUserId,
          title: row.title,
          subtitle: row.subtitle,
          imageUrl: row.cover_image_url,
          category: row.category,
          location: row.location,
          status: row.status,
          goalAmountMinor: Number(row.goal_amount_minor),
          currency: row.currency,
          durationDays: row.duration_days,
          deadlineAt: toIso(row.deadline_at),
          description: row.description,
          urls: Array.isArray(row.external_urls) ? (row.external_urls as string[]) : [],
          fundedAmountMinor: Number(row.funded_amount_minor),
          supporterCount: Number(row.supporter_count),
          supportCountTotal: Number(row.support_count_total),
          createdAt: toIso(row.created_at),
          minimumPlan: mappedPlans[0] ?? null,
          plans: mappedPlans,
        });
      }
      return rows;
    } finally {
      client.release();
    }
  }

  async createProjectForCreator(input: {
    creatorUserId: string;
    title: string;
    subtitle: string | null;
    imageUrl: string | null;
    category: string | null;
    location: string | null;
    goalAmountMinor: number;
    currency: string;
    durationDays: number | null;
    deadlineAt: string;
    description: string | null;
    urls: string[];
    plans: {
      name: string;
      priceMinor: number;
      rewardSummary: string;
      description: string | null;
      imageUrl: string | null;
      currency: string;
    }[];
  }) {
    if (!hasDb() || !dbPool) {
      return this.memory.createProjectForCreator(input);
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const exists = await client.query<{ id: string }>(
        `select id from projects where creator_user_id = $1 and status in ('draft', 'active') limit 1`,
        [input.creatorUserId],
      );
      if ((exists.rowCount ?? 0) > 0) {
        await client.query("rollback");
        return null;
      }

      const projectId = randomUUID();
      await client.query(
        `
        insert into projects (
          id, creator_user_id, title, subtitle, cover_image_url, category, location, status, goal_amount_minor, currency, duration_days, deadline_at, description, external_urls, created_at, updated_at
        )
        values ($1, $2, $3, $4, $5, $6, $7, 'active', $8, $9, $10, $11, $12, $13::jsonb, now(), now())
      `,
        [
          projectId,
          input.creatorUserId,
          input.title,
          input.subtitle,
          input.imageUrl,
          input.category,
          input.location,
          input.goalAmountMinor,
          input.currency,
          input.durationDays,
          input.deadlineAt,
          input.description,
          JSON.stringify(input.urls),
        ],
      );

      const createdPlans: {
        id: string;
        name: string;
        priceMinor: number;
        rewardSummary: string;
        description: string | null;
        imageUrl: string | null;
        currency: string;
      }[] = [];
      for (const plan of input.plans) {
        const planId = randomUUID();
        await client.query(
          `
          insert into project_plans (
            id, project_id, name, reward_summary, description, image_url, is_physical_reward, price_minor, currency, created_at, updated_at
          )
          values ($1, $2, $3, $4, $5, $6, true, $7, $8, now(), now())
        `,
          [planId, projectId, plan.name, plan.rewardSummary, plan.description, plan.imageUrl, plan.priceMinor, plan.currency],
        );
        createdPlans.push({
          id: planId,
          name: plan.name,
          priceMinor: plan.priceMinor,
          rewardSummary: plan.rewardSummary,
          description: plan.description,
          imageUrl: plan.imageUrl,
          currency: plan.currency,
        });
      }

      await client.query("commit");
      return {
        id: projectId,
        creatorUserId: input.creatorUserId,
        title: input.title,
        subtitle: input.subtitle,
        imageUrl: input.imageUrl,
        category: input.category,
        location: input.location,
        status: "active",
        goalAmountMinor: input.goalAmountMinor,
        currency: input.currency,
        durationDays: input.durationDays,
        deadlineAt: input.deadlineAt,
        description: input.description,
        urls: input.urls,
        fundedAmountMinor: 0,
        supporterCount: 0,
        supportCountTotal: 0,
        createdAt: new Date().toISOString(),
        minimumPlan: createdPlans[0] ?? null,
        plans: createdPlans,
      };
    } catch (error) {
      await client.query("rollback");
      const pgError = error as { code?: string };
      if (pgError.code === "23505") {
        return null;
      }
      throw error;
    } finally {
      client.release();
    }
  }

  async deleteProjectForCreator(input: { creatorUserId: string; projectId: string }) {
    if (!hasDb() || !dbPool) {
      return this.memory.deleteProjectForCreator(input);
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const existing = await client.query<{ id: string; creator_user_id: string; status: string }>(
        `select id, creator_user_id, status from projects where id = $1 limit 1`,
        [input.projectId],
      );
      if ((existing.rowCount ?? 0) === 0) {
        await client.query("rollback");
        return "not_found" as const;
      }
      if (existing.rows[0].creator_user_id !== input.creatorUserId) {
        await client.query("rollback");
        return "forbidden" as const;
      }
      if (existing.rows[0].status !== "draft" && existing.rows[0].status !== "active") {
        await client.query("rollback");
        return "invalid_state" as const;
      }

      const supportCount = await client.query<{ count: string }>(
        `select count(*)::text as count from support_transactions where project_id = $1`,
        [input.projectId],
      );
      if (Number(supportCount.rows[0]?.count ?? "0") > 0) {
        await client.query("rollback");
        return "has_supports" as const;
      }

      // Clear upload sessions under this project first; video_assets are cascade-deleted by FK.
      await client.query(
        `
        delete from video_upload_sessions
        where project_id = $1 and creator_user_id = $2
      `,
        [input.projectId, input.creatorUserId],
      );

      await client.query(
        `
        delete from projects
        where id = $1 and creator_user_id = $2
      `,
        [input.projectId, input.creatorUserId],
      );

      await client.query("commit");
      return "deleted" as const;
    } catch (error) {
      await client.query("rollback");
      const pgError = error as { code?: string };
      if (pgError.code === "23503") {
        return "conflict" as const;
      }
      throw error;
    } finally {
      client.release();
    }
  }

  async endProjectForCreator(input: { creatorUserId: string; projectId: string; reason?: string }) {
    if (!hasDb() || !dbPool) {
      return this.memory.endProjectForCreator(input);
    }

    const client = await dbPool.connect();
    try {
      const existing = await client.query<{ id: string; creator_user_id: string; status: string }>(
        `select id, creator_user_id, status from projects where id = $1 limit 1`,
        [input.projectId],
      );
      if ((existing.rowCount ?? 0) === 0) {
        return "not_found" as const;
      }
      if (existing.rows[0].creator_user_id !== input.creatorUserId) {
        return "forbidden" as const;
      }
      if (existing.rows[0].status === "stopped") {
        return "ended" as const;
      }

      await client.query(
        `
        update projects
        set status = 'stopped', updated_at = now()
        where id = $1 and creator_user_id = $2
      `,
        [input.projectId, input.creatorUserId],
      );

      return "ended" as const;
    } finally {
      client.release();
    }
  }

}
