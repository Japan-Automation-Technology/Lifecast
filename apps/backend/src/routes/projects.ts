import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";

const createProjectBody = z.object({
  title: z.string().min(1).max(120),
  subtitle: z.string().max(160).optional(),
  image_url: z.string().url().max(2048).optional(),
  category: z.string().max(80).optional(),
  location: z.string().max(120).optional(),
  goal_amount_minor: z.number().int().positive().optional(),
  funding_goal_minor: z.number().int().positive().optional(),
  currency: z.string().length(3).default("JPY"),
  project_duration_days: z.number().int().min(1).max(365).optional(),
  deadline_at: z.string().datetime().optional(),
  description: z.string().max(5000).optional(),
  urls: z.array(z.string().url().max(2048)).max(10).optional(),
  minimum_plan: z
    .object({
      name: z.string().min(1).max(60),
      price_minor: z.number().int().positive(),
      reward_summary: z.string().min(1).max(500),
      currency: z.string().length(3).default("JPY"),
    })
    .optional(),
  plans: z
    .array(
      z.object({
        name: z.string().min(1).max(60),
        price_minor: z.number().int().positive(),
        reward_summary: z.string().min(1).max(500),
        currency: z.string().length(3).default("JPY"),
      }),
    )
    .max(10)
    .optional(),
});

const endProjectBody = z
  .object({
    reason: z.string().min(1).max(500).optional(),
  })
  .optional();

export async function registerProjectRoutes(app: FastifyInstance) {
  const mapProject = (project: {
    id: string;
    creatorUserId: string;
    title: string;
    status: string;
    goalAmountMinor: number;
    currency: string;
    deadlineAt: string;
    createdAt: string;
    minimumPlan:
      | {
          id: string;
          name: string;
          priceMinor: number;
          rewardSummary: string;
        currency: string;
        }
      | null;
    plans: {
      id: string;
      name: string;
      priceMinor: number;
      rewardSummary: string;
      currency: string;
    }[];
    subtitle: string | null;
    imageUrl: string | null;
    category: string | null;
    location: string | null;
    description: string | null;
    urls: string[];
    durationDays: number | null;
  }) => ({
    id: project.id,
    creator_user_id: project.creatorUserId,
    title: project.title,
    subtitle: project.subtitle,
    image_url: project.imageUrl,
    category: project.category,
    location: project.location,
    status: project.status,
    goal_amount_minor: project.goalAmountMinor,
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
          currency: project.minimumPlan.currency,
        }
      : null,
    plans: project.plans.map((plan) => ({
      id: plan.id,
      name: plan.name,
      price_minor: plan.priceMinor,
      reward_summary: plan.rewardSummary,
      currency: plan.currency,
    })),
  });

  app.get("/v1/me/project", async (_req, reply) => {
    const creatorUserId = process.env.LIFECAST_DEV_CREATOR_USER_ID;
    if (!creatorUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "LIFECAST_DEV_CREATOR_USER_ID is not configured"));
    }

    const project = await store.getProjectByCreator(creatorUserId);
    if (!project) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Project not found"));
    }

    return reply.send(ok(mapProject(project)));
  });

  app.get("/v1/me/projects", async (_req, reply) => {
    const creatorUserId = process.env.LIFECAST_DEV_CREATOR_USER_ID;
    if (!creatorUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "LIFECAST_DEV_CREATOR_USER_ID is not configured"));
    }

    const projects = await store.listProjectsByCreator(creatorUserId);
    return reply.send(ok({ rows: projects.map(mapProject) }));
  });

  app.post("/v1/projects", async (req, reply) => {
    const body = createProjectBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid project payload"));
    }
    const creatorUserId = process.env.LIFECAST_DEV_CREATOR_USER_ID;
    if (!creatorUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "LIFECAST_DEV_CREATOR_USER_ID is not configured"));
    }
    const goalAmountMinor = body.data.goal_amount_minor ?? body.data.funding_goal_minor;
    if (!goalAmountMinor || goalAmountMinor <= 0) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "goal_amount_minor or funding_goal_minor is required"));
    }

    const project = await store.createProjectForCreator({
      creatorUserId,
      title: body.data.title,
      subtitle: body.data.subtitle?.trim() || null,
      imageUrl: body.data.image_url?.trim() || null,
      category: body.data.category?.trim() || null,
      location: body.data.location?.trim() || null,
      goalAmountMinor,
      currency: body.data.currency.toUpperCase(),
      deadlineAt:
        body.data.deadline_at ??
        new Date(Date.now() + (body.data.project_duration_days ?? 14) * 24 * 60 * 60 * 1000).toISOString(),
      durationDays: body.data.project_duration_days ?? null,
      description: body.data.description?.trim() || null,
      urls: body.data.urls ?? [],
      plans: (body.data.plans && body.data.plans.length > 0
        ? body.data.plans
        : body.data.minimum_plan
          ? [body.data.minimum_plan]
          : [
              {
                name: "Early Support",
                price_minor: 1000,
                reward_summary: "Support this project",
                currency: body.data.currency,
              },
            ]
      ).map((plan) => ({
        name: plan.name,
        priceMinor: plan.price_minor,
        rewardSummary: plan.reward_summary,
        currency: plan.currency.toUpperCase(),
      })),
    });

    if (!project) {
      return reply.code(409).send(fail("STATE_CONFLICT", "Creator already has a project"));
    }

    return reply.send(ok(mapProject(project)));
  });

  app.delete("/v1/projects/:projectId", async (req, reply) => {
    const projectId = (req.params as { projectId: string }).projectId;
    if (!z.string().uuid().safeParse(projectId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid project id"));
    }
    const creatorUserId = process.env.LIFECAST_DEV_CREATOR_USER_ID;
    if (!creatorUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "LIFECAST_DEV_CREATOR_USER_ID is not configured"));
    }

    const deleted = await store.deleteProjectForCreator({ creatorUserId, projectId });
    if (deleted === "not_found") {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Project not found"));
    }
    if (deleted === "forbidden") {
      return reply.code(403).send(fail("FORBIDDEN", "You cannot delete this project"));
    }
    if (deleted === "invalid_state") {
      return reply.code(409).send(fail("STATE_CONFLICT", "Only draft projects can be deleted. End active projects first."));
    }
    if (deleted === "has_supports") {
      return reply.code(409).send(fail("STATE_CONFLICT", "Projects with supports cannot be deleted"));
    }
    if (deleted === "conflict") {
      return reply.code(409).send(fail("STATE_CONFLICT", "Project has dependent records and cannot be deleted"));
    }

    return reply.send(ok({ project_id: projectId, status: "deleted" }));
  });

  app.post("/v1/projects/:projectId/end", async (req, reply) => {
    const projectId = (req.params as { projectId: string }).projectId;
    if (!z.string().uuid().safeParse(projectId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid project id"));
    }
    const body = endProjectBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid end project payload"));
    }
    const creatorUserId = process.env.LIFECAST_DEV_CREATOR_USER_ID;
    if (!creatorUserId) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "LIFECAST_DEV_CREATOR_USER_ID is not configured"));
    }

    const ended = await store.endProjectForCreator({
      creatorUserId,
      projectId,
      reason: body.data?.reason,
    });
    if (ended === "not_found") {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Project not found"));
    }
    if (ended === "forbidden") {
      return reply.code(403).send(fail("FORBIDDEN", "You cannot end this project"));
    }

    return reply.send(
      ok({
        project_id: projectId,
        status: "stopped",
        refund_policy: "full_refund",
      }),
    );
  });
}
