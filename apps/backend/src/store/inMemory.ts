import { randomUUID } from "node:crypto";
import type { CreatorVideoRecord, DisputeRecord, PayoutRecord, SupportRecord, UploadSession } from "../types.js";

const nowIso = () => new Date().toISOString();
const plusHoursIso = (hours: number) => new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
const plusDaysIso = (days: number) => new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();

export class InMemoryStore {
  private readonly supports = new Map<string, SupportRecord>();
  private readonly uploads = new Map<string, UploadSession>();
  private readonly payouts = new Map<string, PayoutRecord>();
  private readonly disputes = new Map<string, DisputeRecord>();
  private readonly projectsById = new Map<string, {
    id: string;
    creatorUserId: string;
    title: string;
    subtitle: string | null;
    imageUrl: string | null;
    category: string | null;
    location: string | null;
    status: string;
    goalAmountMinor: number;
    currency: string;
    durationDays: number | null;
    deadlineAt: string;
    description: string | null;
    urls: string[];
    fundedAmountMinor: number;
    supporterCount: number;
    supportCountTotal: number;
    createdAt: string;
    minimumPlan: {
      id: string;
      name: string;
      priceMinor: number;
      rewardSummary: string;
      description: string | null;
      imageUrl: string | null;
      currency: string;
    } | null;
    plans: {
      id: string;
      name: string;
      priceMinor: number;
      rewardSummary: string;
      description: string | null;
      imageUrl: string | null;
      currency: string;
    }[];
  }>();

  prepareSupport(input: { projectId: string; planId: string; quantity: number; supporterUserId?: string }) {
    const supportId = randomUUID();
    const record: SupportRecord = {
      supportId,
      projectId: input.projectId,
      planId: input.planId,
      amountMinor: 1000 * input.quantity,
      currency: "JPY",
      status: "prepared",
      rewardType: "physical",
      cancellationWindowHours: 48,
      checkoutSessionId: randomUUID(),
    };
    this.supports.set(supportId, record);
    return record;
  }

  confirmSupport(supportId: string) {
    const record = this.supports.get(supportId);
    if (!record) return null;
    record.status = "pending_confirmation";
    this.supports.set(supportId, record);
    return record;
  }

  getSupport(supportId: string) {
    return this.supports.get(supportId) ?? null;
  }

  markSupportSucceededByWebhook(supportId: string) {
    const record = this.supports.get(supportId);
    if (!record) return null;
    record.status = "succeeded";
    this.supports.set(supportId, record);
    return record;
  }

  createUploadSession(input?: { fileName?: string; projectId?: string; creatorUserId?: string }) {
    if (!input?.projectId) return null;
    const project = this.projectsById.get(input.projectId);
    if (!project) return null;
    if (!(project.status === "active" || project.status === "draft")) return null;
    if (input.creatorUserId && project.creatorUserId !== input.creatorUserId) return null;

    const uploadSessionId = randomUUID();
    const session: UploadSession = {
      uploadSessionId,
      status: "created",
      uploadUrl: `https://upload.lifecast.jp/${uploadSessionId}/${input?.fileName ?? "source.mp4"}`,
      expiresAt: plusHoursIso(1),
    };
    this.uploads.set(uploadSessionId, session);
    return session;
  }

  getProjectByCreator(creatorUserId: string) {
    const rows = Array.from(this.projectsById.values()).filter(
      (p) => p.creatorUserId === creatorUserId && (p.status === "active" || p.status === "draft"),
    );
    if (rows.length === 0) return null;
    rows.sort((a, b) => (a.createdAt > b.createdAt ? -1 : 1));
    return rows[0];
  }

  listProjectsByCreator(creatorUserId: string) {
    const rows = Array.from(this.projectsById.values()).filter((p) => p.creatorUserId === creatorUserId);
    rows.sort((a, b) => {
      const aRank = a.status === "active" || a.status === "draft" ? 0 : 1;
      const bRank = b.status === "active" || b.status === "draft" ? 0 : 1;
      if (aRank !== bRank) return aRank - bRank;
      return a.createdAt > b.createdAt ? -1 : 1;
    });
    return rows;
  }

  createProjectForCreator(input: {
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
    const existing = Array.from(this.projectsById.values()).find(
      (p) => p.creatorUserId === input.creatorUserId && (p.status === "active" || p.status === "draft"),
    );
    if (existing) return null;
    const plans = input.plans.map((plan) => ({
      id: randomUUID(),
      name: plan.name,
      priceMinor: plan.priceMinor,
      rewardSummary: plan.rewardSummary,
      description: plan.description,
      imageUrl: plan.imageUrl,
      currency: plan.currency,
    }));
    const project = {
      id: randomUUID(),
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
      createdAt: nowIso(),
      minimumPlan: plans[0] ?? null,
      plans,
    };
    this.projectsById.set(project.id, project);
    return project;
  }

  deleteProjectForCreator(input: { creatorUserId: string; projectId: string }) {
    const existing = this.projectsById.get(input.projectId);
    if (!existing) return "not_found" as const;
    if (existing.creatorUserId !== input.creatorUserId) return "forbidden" as const;
    if (existing.status !== "draft" && existing.status !== "active") return "invalid_state" as const;
    this.projectsById.delete(input.projectId);
    return "deleted" as const;
  }

  endProjectForCreator(input: { creatorUserId: string; projectId: string; reason?: string }) {
    const existing = this.projectsById.get(input.projectId);
    if (!existing) return "not_found" as const;
    if (existing.creatorUserId !== input.creatorUserId) return "forbidden" as const;
    if (existing.status === "stopped") return "ended" as const;
    this.projectsById.set(input.projectId, { ...existing, status: "stopped" });
    return "ended" as const;
  }

  completeUploadSession(uploadSessionId: string, contentHashSha256: string, _storageObjectKey?: string) {
    const session = this.uploads.get(uploadSessionId);
    if (!session) return null;
    session.status = "processing";
    session.contentHashSha256 = contentHashSha256;
    this.uploads.set(uploadSessionId, session);
    return session;
  }

  getUploadSession(uploadSessionId: string) {
    return this.uploads.get(uploadSessionId) ?? null;
  }

  writeUploadBinary(uploadSessionId: string, input: { storageObjectKey: string; contentHashSha256: string }) {
    const session = this.uploads.get(uploadSessionId);
    if (!session) return null;
    session.status = "uploading";
    session.storageObjectKey = input.storageObjectKey;
    session.contentHashSha256 = input.contentHashSha256;
    this.uploads.set(uploadSessionId, session);
    return {
      uploadSessionId,
      storageObjectKey: input.storageObjectKey,
      contentHashSha256: input.contentHashSha256,
      bytesStored: 0,
    };
  }

  listCreatorVideos(_creatorUserId: string) {
    return [] as CreatorVideoRecord[];
  }

  getPlaybackByVideoId(_videoId: string) {
    return null;
  }

  getThumbnailByVideoId(_videoId: string) {
    return null;
  }

  deleteCreatorVideo(_creatorUserId: string, _videoId: string) {
    return "not_found" as const;
  }

  getOrCreatePayout(projectId: string) {
    const existing = this.payouts.get(projectId);
    if (existing) return existing;
    const payout: PayoutRecord = {
      projectId,
      payoutStatus: "scheduled",
      executionStartAt: plusDaysIso(1),
      settlementDueAt: plusDaysIso(3),
      rollingReserveEnabled: false,
    };
    this.payouts.set(projectId, payout);
    return payout;
  }

  getOrCreateDispute(disputeId: string) {
    const existing = this.disputes.get(disputeId);
    if (existing) return existing;
    const openedAt = nowIso();
    const dispute: DisputeRecord = {
      disputeId,
      status: "open",
      openedAt,
      acknowledgementDueAt: plusHoursIso(24),
      triageDueAt: plusHoursIso(72),
      resolutionDueAt: plusDaysIso(10),
    };
    this.disputes.set(disputeId, dispute);
    return dispute;
  }
}

export const store = new InMemoryStore();
