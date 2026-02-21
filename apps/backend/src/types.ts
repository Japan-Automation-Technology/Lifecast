export type SupportStatus =
  | "prepared"
  | "pending_confirmation"
  | "succeeded"
  | "failed"
  | "canceled"
  | "refunded";

export type UploadStatus = "created" | "uploading" | "processing" | "ready" | "failed";

export type DisputeStatus = "open" | "won" | "lost" | "closed";

export type PayoutStatus = "scheduled" | "executing" | "settled" | "blocked";

export interface SupportRecord {
  supportId: string;
  projectId: string;
  planId: string;
  amountMinor: number;
  currency: string;
  status: SupportStatus;
  rewardType: "physical";
  cancellationWindowHours: 48;
  checkoutSessionId?: string;
}

export interface UploadSession {
  uploadSessionId: string;
  status: UploadStatus;
  videoId?: string;
  contentHashSha256?: string;
  storageObjectKey?: string;
  uploadUrl?: string;
  expiresAt?: string;
}

export interface CreatorVideoRecord {
  videoId: string;
  status: UploadStatus;
  fileName: string;
  playbackUrl?: string;
  thumbnailUrl?: string;
  playCount: number;
  watchCompletedCount: number;
  watchTimeTotalMs: number;
  createdAt: string;
}

export interface DisputeRecord {
  disputeId: string;
  status: DisputeStatus;
  openedAt: string;
  acknowledgementDueAt: string;
  triageDueAt: string;
  resolutionDueAt: string;
}

export interface PayoutRecord {
  projectId: string;
  payoutStatus: PayoutStatus;
  executionStartAt: string;
  settlementDueAt: string;
  settledAt?: string;
  rollingReserveEnabled: false;
}

export interface ModerationReportResult {
  reportId: string;
  autoReviewTriggered: boolean;
  trustScore24h: number;
  uniqueReporters24h: number;
}

export interface DisputeRecoveryResult {
  disputeId: string;
  accepted: boolean;
}
