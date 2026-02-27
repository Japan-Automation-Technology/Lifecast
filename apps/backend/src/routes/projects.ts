import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import { extname } from "node:path";
import { z } from "zod";
import { requireRequestUserId } from "../auth/requestContext.js";
import { fail, ok } from "../response.js";
import { store } from "../store/hybridStore.js";
import { readImageBinary, writeImageBinary } from "../store/services/imageStorageService.js";
import { buildPublicAppUrl, normalizeLegacyLocalAssetUrl, normalizeLegacyLocalAssetUrls } from "../url/publicAssetUrl.js";

const projectDetailBlockSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("heading"),
    text: z.string().min(1).max(160),
  }),
  z.object({
    type: z.literal("text"),
    text: z.string().min(1).max(5000),
  }),
  z.object({
    type: z.literal("quote"),
    text: z.string().min(1).max(500),
  }),
  z.object({
    type: z.literal("image"),
    image_url: z.string().url().max(2048).nullable(),
  }),
  z.object({
    type: z.literal("bullets"),
    items: z.array(z.string().min(1).max(240)).min(1).max(12),
  }),
]);

const createProjectBody = z.object({
  title: z.string().min(1).max(120),
  subtitle: z.string().max(160).optional(),
  image_url: z.string().url().max(2048).optional(),
  image_urls: z.array(z.string().url().max(2048)).min(1).max(5).optional(),
  category: z.string().max(80).optional(),
  location: z.string().max(120).optional(),
  goal_amount_minor: z.number().int().positive().optional(),
  funding_goal_minor: z.number().int().positive().optional(),
  currency: z.string().length(3).default("JPY"),
  project_duration_days: z.number().int().min(1).max(365).optional(),
  deadline_at: z.string().datetime().optional(),
  description: z.string().max(5000).optional(),
  urls: z.array(z.string().url().max(2048)).max(10).optional(),
  detail_blocks: z.array(projectDetailBlockSchema).max(120).optional(),
  minimum_plan: z
    .object({
      name: z.string().min(1).max(60),
      price_minor: z.number().int().positive(),
      reward_summary: z.string().min(1).max(500),
      description: z.string().max(1000).optional(),
      image_url: z.string().url().max(2048).optional(),
      currency: z.string().length(3).default("JPY"),
    })
    .optional(),
  plans: z
    .array(
      z.object({
        name: z.string().min(1).max(60),
        price_minor: z.number().int().positive(),
        reward_summary: z.string().min(1).max(500),
        description: z.string().max(1000).optional(),
        image_url: z.string().url().max(2048).optional(),
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

const updateProjectBody = z.object({
  subtitle: z.string().max(160).nullable().optional(),
  description: z.string().max(5000).nullable().optional(),
  image_url: z.string().url().max(2048).nullable().optional(),
  image_urls: z.array(z.string().url().max(2048)).min(1).max(5).optional(),
  urls: z.array(z.string().url().max(2048)).max(10).optional(),
  detail_blocks: z.array(projectDetailBlockSchema).max(120).optional(),
  plans: z
    .array(
      z.object({
        id: z.string().uuid().optional(),
        name: z.string().min(1).max(60).optional(),
        price_minor: z.number().int().positive().optional(),
        reward_summary: z.string().min(1).max(500).optional(),
        description: z.string().max(1000).nullable().optional(),
        image_url: z.string().url().max(2048).nullable().optional(),
        currency: z.string().length(3).optional(),
      }),
    )
    .max(10)
    .optional(),
});

const projectImageUploadBody = z.object({
  file_name: z.string().max(255).optional(),
  content_type: z.string().max(100),
  data_base64: z.string().min(1),
});

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
          description: string | null;
          imageUrl: string | null;
          currency: string;
        }
      | null;
    plans: {
      id: string;
      name: string;
      priceMinor: number;
      rewardSummary: string;
      description: string | null;
      imageUrl: string | null;
      currency: string;
    }[];
    subtitle: string | null;
    imageUrl: string | null;
    imageUrls: string[];
    category: string | null;
    location: string | null;
    description: string | null;
    urls: string[];
    detailBlocks: Array<
      | { type: "heading"; text: string }
      | { type: "text"; text: string }
      | { type: "quote"; text: string }
      | { type: "image"; image_url: string | null }
      | { type: "bullets"; items: string[] }
    >;
    durationDays: number | null;
    fundedAmountMinor: number;
    supporterCount: number;
    supportCountTotal: number;
  }) => ({
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
    currency: project.currency,
    duration_days: project.durationDays,
    deadline_at: project.deadlineAt,
    description: project.description,
    urls: project.urls,
    detail_blocks: project.detailBlocks,
    funded_amount_minor: project.fundedAmountMinor,
    supporter_count: project.supporterCount,
    support_count_total: project.supportCountTotal,
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
  });

  app.post("/v1/projects/images", async (req, reply) => {
    const body = projectImageUploadBody.safeParse(req.body);
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
      kind: "projects",
      fileName,
      contentType,
      data,
    });

    const imageUrl = buildPublicAppUrl(`/v1/projects/images/${fileName}`);
    return reply.send(ok({ image_url: imageUrl }));
  });

  app.get("/v1/projects/images/:fileName", async (req, reply) => {
    const fileName = (req.params as { fileName: string }).fileName;
    const isValid = /^[0-9a-fA-F-]+\.(jpg|jpeg|png|webp|heic|bin)$/.test(fileName);
    if (!isValid) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid file name"));
    }

    let binary: Buffer;
    try {
      binary = await readImageBinary({ kind: "projects", fileName });
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

  app.get("/v1/me/project", async (req, reply) => {
    const creatorUserId = requireRequestUserId(req, reply);
    if (!creatorUserId) return;

    const project = await store.getProjectByCreator(creatorUserId);
    if (!project) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Project not found"));
    }

    return reply.send(ok(mapProject(project)));
  });

  app.get("/v1/me/projects", async (req, reply) => {
    const creatorUserId = requireRequestUserId(req, reply);
    if (!creatorUserId) return;

    const projects = await store.listProjectsByCreator(creatorUserId);
    return reply.send(ok({ rows: projects.map(mapProject) }));
  });

  app.post("/v1/projects", async (req, reply) => {
    const creatorUserId = requireRequestUserId(req, reply);
    if (!creatorUserId) return;

    const body = createProjectBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid project payload"));
    }
    const goalAmountMinor = body.data.goal_amount_minor ?? body.data.funding_goal_minor;
    if (!goalAmountMinor || goalAmountMinor <= 0) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "goal_amount_minor or funding_goal_minor is required"));
    }
    const primaryImageUrl = body.data.image_urls?.[0]?.trim() || body.data.image_url?.trim() || null;
    if (!primaryImageUrl) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "At least one project image is required"));
    }

    const project = await store.createProjectForCreator({
      creatorUserId,
      title: body.data.title,
      subtitle: body.data.subtitle?.trim() || null,
      imageUrl: primaryImageUrl,
      imageUrls: body.data.image_urls ?? (primaryImageUrl ? [primaryImageUrl] : []),
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
      detailBlocks: body.data.detail_blocks ?? [],
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
        description: plan.description?.trim() || null,
        imageUrl: plan.image_url?.trim() || null,
        currency: plan.currency.toUpperCase(),
      })),
    });

    if (!project) {
      return reply.code(409).send(fail("STATE_CONFLICT", "Creator already has a project"));
    }

    return reply.send(ok(mapProject(project)));
  });

  app.patch("/v1/projects/:projectId", async (req, reply) => {
    const creatorUserId = requireRequestUserId(req, reply);
    if (!creatorUserId) return;

    const projectId = (req.params as { projectId: string }).projectId;
    if (!z.string().uuid().safeParse(projectId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid project id"));
    }

    const body = updateProjectBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid project payload"));
    }

    const mergedImageUrls = body.data.image_urls
      ?? (body.data.image_url ? [body.data.image_url] : undefined);
    const updated = await store.updateProjectForCreator({
      creatorUserId,
      projectId,
      subtitle: body.data.subtitle === undefined ? undefined : body.data.subtitle?.trim() ?? null,
      description: body.data.description === undefined ? undefined : body.data.description?.trim() ?? null,
      imageUrls: mergedImageUrls?.map((v) => v.trim()).filter((v) => v.length > 0),
      urls: body.data.urls,
      detailBlocks: body.data.detail_blocks,
      plans: body.data.plans?.map((plan) => ({
        id: plan.id,
        name: plan.name,
        priceMinor: plan.price_minor,
        rewardSummary: plan.reward_summary,
        description: plan.description === undefined ? undefined : plan.description?.trim() ?? null,
        imageUrl: plan.image_url === undefined ? undefined : plan.image_url?.trim() ?? null,
        currency: plan.currency?.toUpperCase(),
      })),
    });

    if (updated === "not_found" || !updated) {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Project not found"));
    }
    if (updated === "forbidden") {
      return reply.code(403).send(fail("FORBIDDEN", "You cannot edit this project"));
    }
    if (updated === "invalid_state") {
      return reply.code(409).send(fail("STATE_CONFLICT", "Ended or deleted projects cannot be edited"));
    }
    if (updated === "invalid_plan_price") {
      return reply
        .code(409)
        .send(fail("STATE_CONFLICT", "New plans cannot be cheaper than existing plans"));
    }
    if (updated === "validation_error") {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid plan payload"));
    }

    return reply.send(ok(mapProject(updated)));
  });

  app.delete("/v1/projects/:projectId", async (req, reply) => {
    const creatorUserId = requireRequestUserId(req, reply);
    if (!creatorUserId) return;

    const projectId = (req.params as { projectId: string }).projectId;
    if (!z.string().uuid().safeParse(projectId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid project id"));
    }

    const deleted = await store.deleteProjectForCreator({ creatorUserId, projectId });
    if (deleted === "not_found") {
      return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "Project not found"));
    }
    if (deleted === "forbidden") {
      return reply.code(403).send(fail("FORBIDDEN", "You cannot delete this project"));
    }
    if (deleted === "invalid_state") {
      return reply
        .code(409)
        .send(fail("STATE_CONFLICT", "Only active/draft projects with zero supports can be deleted."));
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
    const creatorUserId = requireRequestUserId(req, reply);
    if (!creatorUserId) return;

    const projectId = (req.params as { projectId: string }).projectId;
    if (!z.string().uuid().safeParse(projectId).success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid project id"));
    }
    const body = endProjectBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid end project payload"));
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
