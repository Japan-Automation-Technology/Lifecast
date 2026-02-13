import { randomUUID } from "node:crypto";
import type { DisputeRecord, PayoutRecord, SupportRecord, UploadSession } from "../types.js";

const nowIso = () => new Date().toISOString();
const plusHoursIso = (hours: number) => new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
const plusDaysIso = (days: number) => new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();

export class InMemoryStore {
  private readonly supports = new Map<string, SupportRecord>();
  private readonly uploads = new Map<string, UploadSession>();
  private readonly payouts = new Map<string, PayoutRecord>();
  private readonly disputes = new Map<string, DisputeRecord>();

  prepareSupport(input: { projectId: string; planId: string; quantity: number }) {
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

  createUploadSession(input?: { fileName?: string }) {
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
