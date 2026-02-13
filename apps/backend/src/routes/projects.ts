import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";

const createProjectBody = z.object({
  title: z.string().min(1).max(120),
  goal_amount_minor: z.number().int().positive(),
  currency: z.string().length(3).default("JPY"),
  deadline_at: z.string().datetime(),
  minimum_plan: z.object({
    name: z.string().min(1).max(60),
    price_minor: z.number().int().positive(),
    reward_summary: z.string().min(1).max(500),
    currency: z.string().length(3).default("JPY"),
  }),
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
  }) => ({
    id: project.id,
    creator_user_id: project.creatorUserId,
    title: project.title,
    status: project.status,
    goal_amount_minor: project.goalAmountMinor,
    currency: project.currency,
    deadline_at: project.deadlineAt,
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

    const project = await store.createProjectForCreator({
      creatorUserId,
      title: body.data.title,
      goalAmountMinor: body.data.goal_amount_minor,
      currency: body.data.currency.toUpperCase(),
      deadlineAt: body.data.deadline_at,
      minimumPlan: {
        name: body.data.minimum_plan.name,
        priceMinor: body.data.minimum_plan.price_minor,
        rewardSummary: body.data.minimum_plan.reward_summary,
        currency: body.data.minimum_plan.currency.toUpperCase(),
      },
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
