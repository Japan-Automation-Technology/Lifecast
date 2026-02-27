import { randomUUID } from "node:crypto";
import { dbPool, hasDb } from "../db.js";
import type { InMemoryStore } from "../inMemory.js";

function toIso(value: Date | string) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

type ProjectDetailBlock =
  | { type: "heading"; text: string }
  | { type: "text"; text: string }
  | { type: "quote"; text: string }
  | { type: "image"; image_url: string | null }
  | { type: "bullets"; items: string[] };

function normalizeProjectDetailBlocks(value: unknown): ProjectDetailBlock[] {
  if (!Array.isArray(value)) return [];
  const blocks: ProjectDetailBlock[] = [];
  for (const raw of value) {
    if (!raw || typeof raw !== "object") continue;
    const block = raw as Record<string, unknown>;
    const type = typeof block.type === "string" ? block.type : "";
    if (["heading", "text", "quote"].includes(type)) {
      const text = typeof block.text === "string" ? block.text.trim() : "";
      if (text.length > 0) {
        blocks.push({ type: type as "heading" | "text" | "quote", text });
      }
      continue;
    }
    if (type === "image") {
      const imageUrl = typeof block.image_url === "string" ? block.image_url.trim() : "";
      blocks.push({ type: "image", image_url: imageUrl.length > 0 ? imageUrl : null });
      continue;
    }
    if (type === "bullets") {
      const items = Array.isArray(block.items)
        ? block.items.filter((item): item is string => typeof item === "string").map((item) => item.trim()).filter(Boolean)
        : [];
      if (items.length > 0) {
        blocks.push({ type: "bullets", items });
      }
    }
  }
  return blocks;
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
        project_image_urls: unknown;
        project_detail_blocks: unknown;
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
          project_image_urls,
          project_detail_blocks,
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
        imageUrls: Array.isArray(row.project_image_urls) ? (row.project_image_urls as string[]) : [],
        detailBlocks: normalizeProjectDetailBlocks(row.project_detail_blocks),
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
        project_image_urls: unknown;
        project_detail_blocks: unknown;
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
          project_image_urls,
          project_detail_blocks,
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
          imageUrls: Array.isArray(row.project_image_urls) ? (row.project_image_urls as string[]) : [],
          detailBlocks: normalizeProjectDetailBlocks(row.project_detail_blocks),
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
    imageUrls: string[];
    detailBlocks: ProjectDetailBlock[];
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
          id, creator_user_id, title, subtitle, cover_image_url, project_image_urls, project_detail_blocks, category, location, status, goal_amount_minor, currency, duration_days, deadline_at, description, external_urls, created_at, updated_at
        )
        values ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8, $9, 'active', $10, $11, $12, $13, $14, $15::jsonb, now(), now())
      `,
        [
          projectId,
          input.creatorUserId,
          input.title,
          input.subtitle,
          input.imageUrls[0] ?? input.imageUrl,
          JSON.stringify(input.imageUrls),
          JSON.stringify(normalizeProjectDetailBlocks(input.detailBlocks)),
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
        imageUrl: input.imageUrls[0] ?? input.imageUrl,
        imageUrls: input.imageUrls,
        detailBlocks: normalizeProjectDetailBlocks(input.detailBlocks),
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

  async updateProjectForCreator(input: {
    creatorUserId: string;
    projectId: string;
    subtitle?: string | null;
    description?: string | null;
    imageUrls?: string[];
    detailBlocks?: ProjectDetailBlock[];
    urls?: string[];
    plans?: Array<{
      id?: string;
      name?: string;
      priceMinor?: number;
      rewardSummary?: string;
      description?: string | null;
      imageUrl?: string | null;
      currency?: string;
    }>;
  }) {
    if (!hasDb() || !dbPool) {
      return this.memory.updateProjectForCreator(input);
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const existing = await client.query<{
        id: string;
        creator_user_id: string;
        status: string;
        subtitle: string | null;
        description: string | null;
        cover_image_url: string | null;
        project_image_urls: unknown;
        project_detail_blocks: unknown;
        external_urls: unknown;
      }>(
        `select id, creator_user_id, status, subtitle, description, cover_image_url, project_image_urls, project_detail_blocks, external_urls from projects where id = $1 limit 1`,
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
      if (["stopped", "failed", "succeeded"].includes(existing.rows[0].status)) {
        await client.query("rollback");
        return "invalid_state" as const;
      }

      const current = existing.rows[0];
      const mergedSubtitle = input.subtitle === undefined ? current.subtitle : input.subtitle;
      const mergedDescription = input.description === undefined ? current.description : input.description;
      const currentImageUrls = Array.isArray(current.project_image_urls)
        ? (current.project_image_urls as string[]).filter((v) => typeof v === "string")
        : (current.cover_image_url ? [current.cover_image_url] : []);
      const mergedImageUrls = input.imageUrls === undefined ? currentImageUrls : input.imageUrls;
      const mergedCoverImageUrl = mergedImageUrls[0] ?? current.cover_image_url;
      const currentUrls = Array.isArray(current.external_urls)
        ? (current.external_urls as string[]).filter((v) => typeof v === "string")
        : [];
      const mergedUrls = input.urls === undefined ? currentUrls : input.urls;
      const mergedDetailBlocks =
        input.detailBlocks === undefined ? normalizeProjectDetailBlocks(current.project_detail_blocks) : normalizeProjectDetailBlocks(input.detailBlocks);

      await client.query(
        `
        update projects
        set subtitle = $3,
            description = $4,
            cover_image_url = $5,
            project_image_urls = $6::jsonb,
            external_urls = $7::jsonb,
            project_detail_blocks = $8::jsonb,
            updated_at = now()
        where id = $1 and creator_user_id = $2
      `,
        [
          input.projectId,
          input.creatorUserId,
          mergedSubtitle,
          mergedDescription,
          mergedCoverImageUrl,
          JSON.stringify(mergedImageUrls),
          JSON.stringify(mergedUrls),
          JSON.stringify(mergedDetailBlocks),
        ],
      );

      if (input.plans && input.plans.length > 0) {
        const planRows = await client.query<{
          id: string;
          price_minor: number;
          description: string | null;
          image_url: string | null;
        }>(
          `
          select id, price_minor, description, image_url
          from project_plans
          where project_id = $1
        `,
          [input.projectId],
        );

        const existingPlanMap = new Map(planRows.rows.map((row) => [row.id, row]));
        const minExistingPrice = planRows.rows.reduce((acc, row) => Math.min(acc, row.price_minor), Number.POSITIVE_INFINITY);

        for (const plan of input.plans) {
          if (plan.id) {
            const currentPlan = existingPlanMap.get(plan.id);
            if (!currentPlan) {
              await client.query("rollback");
              return "validation_error" as const;
            }
            const mergedPlanDescription = plan.description === undefined ? currentPlan.description : plan.description;
            const mergedPlanImageUrl = plan.imageUrl === undefined ? currentPlan.image_url : plan.imageUrl;
            await client.query(
              `
              update project_plans
              set description = $2,
                  image_url = $3,
                  updated_at = now()
              where id = $1 and project_id = $4
            `,
              [plan.id, mergedPlanDescription, mergedPlanImageUrl, input.projectId],
            );
            continue;
          }

          if (!plan.name || !plan.rewardSummary || !plan.currency || !plan.priceMinor || plan.priceMinor <= 0) {
            await client.query("rollback");
            return "validation_error" as const;
          }

          if (Number.isFinite(minExistingPrice) && plan.priceMinor < minExistingPrice) {
            await client.query("rollback");
            return "invalid_plan_price" as const;
          }

          await client.query(
            `
            insert into project_plans (
              id, project_id, name, reward_summary, description, image_url, is_physical_reward, price_minor, currency, created_at, updated_at
            )
            values ($1, $2, $3, $4, $5, $6, true, $7, $8, now(), now())
          `,
            [
              randomUUID(),
              input.projectId,
              plan.name,
              plan.rewardSummary,
              plan.description ?? null,
              plan.imageUrl ?? null,
              plan.priceMinor,
              plan.currency,
            ],
          );
        }
      }

      await client.query("commit");
      return this.getProjectByCreator(input.creatorUserId);
    } catch (error) {
      await client.query("rollback");
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
