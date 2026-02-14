import { randomUUID } from "node:crypto";
import { createHash } from "node:crypto";
import { mkdir, stat, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { dbPool, hasDb } from "./db.js";
import { InMemoryStore } from "./inMemory.js";
import { ProjectsService } from "./services/projectsService.js";
import { SupportsService } from "./services/supportsService.js";
import { UploadsService } from "./services/uploadsService.js";
import { buildServerEvent, validateEventPayload } from "../events/contract.js";
import type {
  CreatorVideoRecord,
  DisputeRecord,
  DisputeRecoveryResult,
  ModerationReportResult,
  PayoutRecord,
  SupportRecord,
  UploadSession,
} from "../types.js";

interface JournalLine {
  account_code: string;
  debit_minor: number;
  credit_minor: number;
  currency: string;
}

interface JournalEntryView {
  entry_id: string;
  entry_type: string;
  occurred_at: string;
  support_id: string | null;
  project_id: string | null;
  lines: JournalLine[];
}

interface JournalEntryRow {
  entry_id: string;
  entry_type: string;
  occurred_at: string | Date;
  support_id: string | null;
  project_id: string | null;
  lines: JournalLine[];
}

interface FunnelDailyRow {
  event_date_utc: string | Date;
  event_name: string;
  event_count: string | number;
  actor_count: string | number;
}

interface KpiDailyRow {
  event_date_utc: string | Date;
  watch_completed_count: string | number;
  payment_succeeded_count: string | number;
  support_conversion_rate_pct: string | number;
  average_support_amount_minor: string | number;
  repeat_support_rate_pct: string | number;
}

interface CloudflareDirectUploadResult {
  uid: string;
  uploadURL: string;
}

interface CloudflareVideoDetails {
  uid: string;
  readyToStream: boolean;
  playbackUrl?: string;
  preview?: string;
  thumbnail?: string;
  duration?: number;
  width?: number;
  height?: number;
}

const memory = new InMemoryStore();
const webhookMemoryDedup = new Set<string>();
const eventMemoryDedup = new Set<string>();
const eventMemoryDlq: Array<{
  event_id?: string;
  reason_code: string;
  reason_message: string;
  raw_payload: unknown;
  source: "client" | "server";
}> = [];

const LOCAL_VIDEO_ROOT = resolve(process.cwd(), ".data/video-objects");

function hasCloudflareStreamConfig() {
  return Boolean(process.env.CF_ACCOUNT_ID && process.env.CF_STREAM_TOKEN);
}

async function createCloudflareDirectUpload(): Promise<CloudflareDirectUploadResult | null> {
  const accountId = process.env.CF_ACCOUNT_ID;
  const token = process.env.CF_STREAM_TOKEN;
  if (!accountId || !token) return null;

  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/direct_upload`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      maxDurationSeconds: 180,
      requireSignedURLs: false,
    }),
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok || !payload?.success || !payload?.result?.uploadURL || !payload?.result?.uid) {
    return null;
  }

  return {
    uid: String(payload.result.uid),
    uploadURL: String(payload.result.uploadURL),
  };
}

async function getCloudflareVideoDetails(uid: string): Promise<CloudflareVideoDetails | null> {
  const accountId = process.env.CF_ACCOUNT_ID;
  const token = process.env.CF_STREAM_TOKEN;
  if (!accountId || !token) return null;

  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/${uid}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok || !payload?.success || !payload?.result) {
    return null;
  }

  const result = payload.result;
  return {
    uid: String(result.uid ?? uid),
    readyToStream: Boolean(result.readyToStream),
    playbackUrl: typeof result.playback?.hls === "string" ? result.playback.hls : undefined,
    preview: typeof result.preview === "string" ? result.preview : undefined,
    thumbnail: typeof result.thumbnail === "string" ? result.thumbnail : undefined,
    duration: typeof result.duration === "number" ? result.duration : undefined,
    width: typeof result.input?.width === "number" ? result.input.width : undefined,
    height: typeof result.input?.height === "number" ? result.input.height : undefined,
  };
}

async function deleteCloudflareVideo(uid: string): Promise<boolean> {
  const accountId = process.env.CF_ACCOUNT_ID;
  const token = process.env.CF_STREAM_TOKEN;
  if (!accountId || !token) return false;

  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/${uid}`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });

  if (!response.ok) {
    return false;
  }
  const payload = await response.json().catch(() => null);
  return Boolean(payload?.success);
}

async function scheduleCloudflareDeleteJob(client: import("pg").PoolClient, input: {
  creatorUserId: string;
  videoId: string;
  providerUploadId: string;
}) {
  await client.query(
    `
    insert into video_delete_jobs (
      creator_user_id, video_id, provider_upload_id, status, attempt, next_run_at, created_at, updated_at
    )
    values ($1, $2, $3, 'pending', 0, now(), now(), now())
  `,
    [input.creatorUserId, input.videoId, input.providerUploadId],
  );
}

function normalizeCurrency(value: string | undefined, fallback = "JPY") {
  return (value ?? fallback).toUpperCase().slice(0, 3);
}

function toIso(value: Date | string) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

export class HybridStore {
  private readonly supportsService = new SupportsService(memory);
  private readonly projectsService = new ProjectsService(memory);
  private readonly uploadsService = new UploadsService(memory);

  async prepareSupport(input: { projectId: string; planId: string; quantity: number; supporterUserId: string }) {
    return this.supportsService.prepareSupport(input);
  }

  async confirmSupport(supportId: string) {
    return this.supportsService.confirmSupport(supportId);
  }

  async getSupport(supportId: string) {
    return this.supportsService.getSupport(supportId);
  }

  async markSupportSucceededByWebhook(supportId: string) {
    return this.supportsService.markSupportSucceededByWebhook(supportId);
  }

  async markSupportRefundedByWebhook(input: { supportId: string; providerRefundId?: string; reasonCode?: string }) {
    return this.supportsService.markSupportRefundedByWebhook(input);
  }

  async createDisputeFromWebhook(input: {
    supportId: string;
    providerDisputeId: string;
    amountMinor: number;
    currency: string;
    reason?: string;
  }) {
    return this.supportsService.createDisputeFromWebhook(input);
  }

  async closeDisputeFromWebhook(input: { providerDisputeId: string; outcome: "won" | "lost"; reason?: string }) {
    return this.supportsService.closeDisputeFromWebhook(input);
  }

  async recordPayoutRelease(input: { projectId: string; amountMinor: number; currency: string }) {
    return this.supportsService.recordPayoutRelease(input);
  }

  async getJournalReconciliation(filters: { projectId?: string; currency?: string; providerTotalMinor?: number }) {
    if (!hasDb() || !dbPool) {
      return { currency: filters.currency ?? "JPY", cashClearingNetMinor: 0, deltaMinor: undefined };
    }
    const client = await dbPool.connect();
    try {
      const values: unknown[] = ["CASH_CLEARING"];
      const where: string[] = ["la.code = $1"];
      if (filters.projectId) {
        values.push(filters.projectId);
        where.push(`je.project_id = $${values.length}`);
      }
      if (filters.currency) {
        values.push(normalizeCurrency(filters.currency));
        where.push(`jl.currency = $${values.length}`);
      }

      const result = await client.query<{ net_minor: string; currency: string }>(
        `
        select
          coalesce(sum(jl.debit_minor - jl.credit_minor), 0)::text as net_minor,
          coalesce(max(jl.currency), $${values.length + 1}) as currency
        from journal_lines jl
        join journal_entries je on je.id = jl.journal_entry_id
        join ledger_accounts la on la.id = jl.ledger_account_id
        where ${where.join(" and ")}
      `,
        [...values, normalizeCurrency(filters.currency)],
      );

      const cashClearingNetMinor = Number(result.rows[0]?.net_minor ?? "0");
      const currency = result.rows[0]?.currency ?? normalizeCurrency(filters.currency);
      const deltaMinor =
        typeof filters.providerTotalMinor === "number" ? cashClearingNetMinor - filters.providerTotalMinor : undefined;

      return {
        currency,
        cashClearingNetMinor,
        providerTotalMinor: filters.providerTotalMinor,
        deltaMinor,
      };
    } catch {
      return { currency: filters.currency ?? "JPY", cashClearingNetMinor: 0, deltaMinor: undefined };
    } finally {
      client.release();
    }
  }

  async processStripeWebhook(input: {
    eventId: string;
    eventType: string;
    payload: Record<string, unknown>;
    supportId?: string;
  }) {
    if (!hasDb() || !dbPool) {
      const dedupeKey = `stripe:${input.eventId}`;
      if (webhookMemoryDedup.has(dedupeKey)) {
        return { deduped: true, processed: false };
      }
      webhookMemoryDedup.add(dedupeKey);
      if (input.supportId && ["checkout.session.completed", "payment_intent.succeeded"].includes(input.eventType)) {
        const support = await this.markSupportSucceededByWebhook(input.supportId);
        if (support) {
          await this.emitServerEvent({
            eventName: "payment_succeeded",
            anonymousId: `supporter:${support.supportId}`,
            attributes: {
              project_id: support.projectId,
              plan_id: support.planId,
              support_id: support.supportId,
              payment_provider: "stripe",
              amount_minor: support.amountMinor,
              currency: support.currency,
            },
          });
        }
        return { deduped: false, processed: true };
      }
      if (input.supportId && input.eventType === "charge.refunded") {
        await this.markSupportRefundedByWebhook({
          supportId: input.supportId,
          providerRefundId: input.eventId,
          reasonCode: "charge_refunded",
        });
        return { deduped: false, processed: true };
      }
      return { deduped: false, processed: false };
    }

    const client = await dbPool.connect();
    try {
      const inserted = await client.query<{ id: number }>(
        `
        insert into processed_webhooks (provider, provider_event_id, event_type, payload, process_result)
        values ('stripe', $1, $2, $3::jsonb, 'ignored')
        on conflict (provider, provider_event_id) do nothing
        returning id
      `,
        [input.eventId, input.eventType, JSON.stringify(input.payload)],
      );
      if (!inserted.rowCount) {
        return { deduped: true, processed: false };
      }

      let processed = false;
      const objectPayload = (input.payload.data as { object?: Record<string, unknown> } | undefined)?.object ?? {};
      const metadata =
        typeof objectPayload.metadata === "object" && objectPayload.metadata !== null
          ? (objectPayload.metadata as Record<string, unknown>)
          : undefined;
      const metadataSupportId = metadata && typeof metadata.support_id === "string" ? metadata.support_id : undefined;
      const webhookSupportId = input.supportId ?? metadataSupportId;

      if (input.supportId && ["checkout.session.completed", "payment_intent.succeeded"].includes(input.eventType)) {
        const support = await this.markSupportSucceededByWebhook(input.supportId);
        if (support) {
          await this.emitServerEvent({
            eventName: "payment_succeeded",
            anonymousId: `supporter:${support.supportId}`,
            attributes: {
              project_id: support.projectId,
              plan_id: support.planId,
              support_id: support.supportId,
              payment_provider: "stripe",
              amount_minor: support.amountMinor,
              currency: support.currency,
            },
          });
        }
        processed = true;
      }
      if (webhookSupportId && input.eventType === "charge.refunded") {
        await this.markSupportRefundedByWebhook({
          supportId: webhookSupportId,
          providerRefundId: typeof objectPayload.id === "string" ? objectPayload.id : input.eventId,
          reasonCode: "charge_refunded",
        });
        processed = true;
      }
      if (webhookSupportId && input.eventType === "charge.dispute.created") {
        await this.createDisputeFromWebhook({
          providerDisputeId: typeof objectPayload.id === "string" ? objectPayload.id : input.eventId,
          supportId: webhookSupportId,
          amountMinor: typeof objectPayload.amount === "number" ? objectPayload.amount : 1,
          currency: normalizeCurrency(typeof objectPayload.currency === "string" ? objectPayload.currency : "JPY"),
          reason: typeof objectPayload.reason === "string" ? objectPayload.reason : "dispute_created",
        });
        processed = true;
      }
      if (input.eventType === "charge.dispute.closed") {
        const outcomeRaw = typeof objectPayload.status === "string" ? objectPayload.status : "";
        const outcome: "won" | "lost" = outcomeRaw === "won" ? "won" : "lost";
        const disputeId = typeof objectPayload.id === "string" ? objectPayload.id : input.eventId;
        await this.closeDisputeFromWebhook({
          providerDisputeId: disputeId,
          outcome,
          reason: "dispute_closed",
        });
        processed = true;
      }

      await client.query(
        `
        update processed_webhooks
        set process_result = $3
        where provider = 'stripe' and provider_event_id = $1 and event_type = $2
      `,
        [input.eventId, input.eventType, processed ? "processed" : "ignored"],
      );

      return { deduped: false, processed };
    } catch {
      return { deduped: false, processed: false };
    } finally {
      client.release();
    }
  }

  async ingestEvents(input: { events: unknown[]; source: "client" | "server" }) {
    if (!hasDb() || !dbPool) {
      let accepted = 0;
      let rejected = 0;
      const rejectedDetails: Array<{ event_id?: string; reason: string }> = [];
      for (const raw of input.events) {
        const validated = validateEventPayload(raw);
        if (!validated.ok || !validated.normalized) {
          rejected += 1;
          rejectedDetails.push({
            event_id: (raw as { event_id?: string } | null)?.event_id,
            reason: validated.errors.join("; "),
          });
          eventMemoryDlq.push({
            event_id: (raw as { event_id?: string } | null)?.event_id,
            reason_code: "SCHEMA_MISMATCH",
            reason_message: validated.errors.join("; "),
            raw_payload: raw,
            source: input.source,
          });
          continue;
        }

        if (eventMemoryDedup.has(validated.normalized.event_id)) {
          continue;
        }
        eventMemoryDedup.add(validated.normalized.event_id);
        accepted += 1;
      }
      return { accepted, rejected, rejectedDetails };
    }

    const client = await dbPool.connect();
    try {
      let accepted = 0;
      let rejected = 0;
      const rejectedDetails: Array<{ event_id?: string; reason: string }> = [];

      for (const raw of input.events) {
        const validated = validateEventPayload(raw);
        if (!validated.ok || !validated.normalized) {
          rejected += 1;
          rejectedDetails.push({
            event_id: (raw as { event_id?: string } | null)?.event_id,
            reason: validated.errors.join("; "),
          });
          await client.query(
            `
            insert into analytics_event_dlq (event_id, reason_code, reason_message, raw_payload, source)
            values ($1, 'SCHEMA_MISMATCH', $2, $3::jsonb, $4)
          `,
            [
              (raw as { event_id?: string } | null)?.event_id ?? null,
              validated.errors.join("; "),
              JSON.stringify(raw ?? {}),
              input.source,
            ],
          );
          continue;
        }

        const e = validated.normalized;
        const result = await client.query(
          `
          insert into analytics_events (
            event_id, event_name, event_time, user_id, anonymous_id, session_id,
            client_platform, app_version, attributes, raw_payload, source
          )
          values (
            $1, $2, $3, $4, $5, $6,
            $7, $8, $9::jsonb, $10::jsonb, $11
          )
          on conflict (event_id) do nothing
        `,
          [
            e.event_id,
            e.event_name,
            e.event_time,
            e.user_id ?? null,
            e.anonymous_id ?? null,
            e.session_id,
            e.client_platform,
            e.app_version,
            JSON.stringify(e.attributes),
            JSON.stringify(raw ?? {}),
            input.source,
          ],
        );
        if ((result.rowCount ?? 0) > 0) {
          accepted += 1;
        }
      }
      return { accepted, rejected, rejectedDetails };
    } finally {
      client.release();
    }
  }

  async emitServerEvent(input: {
    eventName: string;
    userId?: string;
    anonymousId?: string;
    sessionId?: string;
    attributes: Record<string, unknown>;
  }) {
    const appVersion = process.env.LIFECAST_SERVER_APP_VERSION ?? "backend-0.1.0";
    const event = buildServerEvent({
      eventName: input.eventName,
      userId: input.userId,
      anonymousId: input.anonymousId,
      sessionId: input.sessionId,
      appVersion,
      attributes: input.attributes,
    });
    const ingestion = await this.ingestEvents({ events: [event], source: "server" });
    if (ingestion.accepted > 0) {
      await this.enqueueOutboxEvent({
        topic: `analytics.${input.eventName}`,
        eventId: String(event.event_id),
        payload: event,
      });
    }
    return ingestion;
  }

  async enqueueOutboxEvent(input: { eventId: string; topic: string; payload: Record<string, unknown> }) {
    if (!hasDb() || !dbPool) {
      return { queued: true };
    }

    const client = await dbPool.connect();
    try {
      await client.query(
        `
        insert into outbox_events (event_id, topic, payload, status, next_attempt_at)
        values ($1, $2, $3::jsonb, 'pending', now())
        on conflict (event_id) do nothing
      `,
        [input.eventId, input.topic, JSON.stringify(input.payload)],
      );
      return { queued: true };
    } finally {
      client.release();
    }
  }

  async listJournalEntries(filters: { projectId?: string; supportId?: string; entryType?: string; limit?: number }) {
    if (!hasDb() || !dbPool) {
      return [] as JournalEntryView[];
    }

    const client = await dbPool.connect();
    try {
      const where: string[] = [];
      const values: unknown[] = [];
      if (filters.projectId) {
        values.push(filters.projectId);
        where.push(`je.project_id = $${values.length}`);
      }
      if (filters.supportId) {
        values.push(filters.supportId);
        where.push(`je.support_id = $${values.length}`);
      }
      if (filters.entryType) {
        values.push(filters.entryType);
        where.push(`je.entry_type = $${values.length}`);
      }
      const limit = Math.min(Math.max(filters.limit ?? 50, 1), 200);
      values.push(limit);

      const query = `
        select
          je.id as entry_id,
          je.entry_type,
          je.occurred_at,
          je.support_id,
          je.project_id,
          coalesce(
            json_agg(
              json_build_object(
                'account_code', la.code,
                'debit_minor', jl.debit_minor,
                'credit_minor', jl.credit_minor,
                'currency', jl.currency
              )
              order by jl.id
            ) filter (where jl.id is not null),
            '[]'::json
          ) as lines
        from journal_entries je
        left join journal_lines jl on jl.journal_entry_id = je.id
        left join ledger_accounts la on la.id = jl.ledger_account_id
        ${where.length ? `where ${where.join(" and ")}` : ""}
        group by je.id
        order by je.occurred_at desc
        limit $${values.length}
      `;

      const result = await client.query<JournalEntryRow>(query, values);
      return result.rows.map((row: JournalEntryRow) => ({
        entry_id: row.entry_id,
        entry_type: row.entry_type,
        occurred_at: toIso(row.occurred_at),
        support_id: row.support_id,
        project_id: row.project_id,
        lines: row.lines as JournalLine[],
      })) as JournalEntryView[];
    } catch {
      return [] as JournalEntryView[];
    } finally {
      client.release();
    }
  }

  async listFunnelDaily(filters: { dateFrom?: string; dateTo?: string; limit?: number }) {
    if (!hasDb() || !dbPool) {
      return [];
    }
    const client = await dbPool.connect();
    try {
      const where: string[] = [];
      const values: unknown[] = [];
      if (filters.dateFrom) {
        values.push(filters.dateFrom);
        where.push(`event_date_utc >= $${values.length}::date`);
      }
      if (filters.dateTo) {
        values.push(filters.dateTo);
        where.push(`event_date_utc <= $${values.length}::date`);
      }
      const limit = Math.min(Math.max(filters.limit ?? 100, 1), 365);
      values.push(limit);

      const result = await client.query<FunnelDailyRow>(
        `
        select event_date_utc, event_name, event_count, actor_count
        from analytics_funnel_daily
        ${where.length ? `where ${where.join(" and ")}` : ""}
        order by event_date_utc desc, event_name asc
        limit $${values.length}
      `,
        values,
      );
      return result.rows.map((row) => ({
        event_date_utc: row.event_date_utc instanceof Date ? row.event_date_utc.toISOString().slice(0, 10) : String(row.event_date_utc).slice(0, 10),
        event_name: row.event_name,
        event_count: Number(row.event_count),
        actor_count: Number(row.actor_count),
      }));
    } finally {
      client.release();
    }
  }

  async listKpiDaily(filters: { dateFrom?: string; dateTo?: string; limit?: number }) {
    if (!hasDb() || !dbPool) {
      return [];
    }
    const client = await dbPool.connect();
    try {
      const where: string[] = [];
      const values: unknown[] = [];
      if (filters.dateFrom) {
        values.push(filters.dateFrom);
        where.push(`event_date_utc >= $${values.length}::date`);
      }
      if (filters.dateTo) {
        values.push(filters.dateTo);
        where.push(`event_date_utc <= $${values.length}::date`);
      }
      const limit = Math.min(Math.max(filters.limit ?? 100, 1), 365);
      values.push(limit);

      const result = await client.query<KpiDailyRow>(
        `
        select
          event_date_utc,
          watch_completed_count,
          payment_succeeded_count,
          support_conversion_rate_pct,
          average_support_amount_minor,
          repeat_support_rate_pct
        from analytics_kpi_daily
        ${where.length ? `where ${where.join(" and ")}` : ""}
        order by event_date_utc desc
        limit $${values.length}
      `,
        values,
      );

      return result.rows.map((row) => ({
        event_date_utc: row.event_date_utc instanceof Date ? row.event_date_utc.toISOString().slice(0, 10) : String(row.event_date_utc).slice(0, 10),
        watch_completed_count: Number(row.watch_completed_count),
        payment_succeeded_count: Number(row.payment_succeeded_count),
        support_conversion_rate_pct: Number(row.support_conversion_rate_pct),
        average_support_amount_minor: Number(row.average_support_amount_minor),
        repeat_support_rate_pct: Number(row.repeat_support_rate_pct),
      }));
    } finally {
      client.release();
    }
  }

  async getOpsQueueStatus() {
    if (!hasDb() || !dbPool) {
      return {
        outbox: { pending: 0, failed: 0, oldest_pending_at: null, last_delivery_at: null },
        notifications: { pending: 0, failed: 0, oldest_pending_at: null },
      };
    }

    const client = await dbPool.connect();
    try {
      const outbox = await client.query<{
        pending: string;
        failed: string;
        oldest_pending_at: string | null;
        last_delivery_at: string | null;
      }>(
        `
        select
          count(*) filter (where oe.status = 'pending')::text as pending,
          count(*) filter (where oe.status = 'failed')::text as failed,
          min(oe.created_at) filter (where oe.status = 'pending')::text as oldest_pending_at,
          max(oda.attempted_at)::text as last_delivery_at
        from outbox_events oe
        left join outbox_delivery_attempts oda on oda.outbox_event_id = oe.id
      `,
      );

      const notifications = await client.query<{
        pending: string;
        failed: string;
        oldest_pending_at: string | null;
      }>(
        `
        select
          count(*) filter (where sent_at is null and failed_at is null)::text as pending,
          count(*) filter (where failed_at is not null)::text as failed,
          min(created_at) filter (where sent_at is null and failed_at is null)::text as oldest_pending_at
        from notification_events
      `,
      );

      return {
        outbox: {
          pending: Number(outbox.rows[0]?.pending ?? "0"),
          failed: Number(outbox.rows[0]?.failed ?? "0"),
          oldest_pending_at: outbox.rows[0]?.oldest_pending_at ?? null,
          last_delivery_at: outbox.rows[0]?.last_delivery_at ?? null,
        },
        notifications: {
          pending: Number(notifications.rows[0]?.pending ?? "0"),
          failed: Number(notifications.rows[0]?.failed ?? "0"),
          oldest_pending_at: notifications.rows[0]?.oldest_pending_at ?? null,
        },
      };
    } finally {
      client.release();
    }
  }

  async createProjectReport(input: { projectId: string; reasonCode: string; details: string }) {
    if (!hasDb() || !dbPool) {
      return {
        reportId: randomUUID(),
        autoReviewTriggered: false,
        trustScore24h: 1,
        uniqueReporters24h: 1,
      } satisfies ModerationReportResult;
    }

    const reporterUserId = process.env.LIFECAST_DEV_REPORTER_USER_ID ?? process.env.LIFECAST_DEV_SUPPORTER_USER_ID;
    if (!reporterUserId) {
      return {
        reportId: randomUUID(),
        autoReviewTriggered: false,
        trustScore24h: 1,
        uniqueReporters24h: 1,
      } satisfies ModerationReportResult;
    }

    const client = await dbPool.connect();
    try {
      const reportId = randomUUID();
      await client.query(
        `
        insert into moderation_reports (
          id, project_id, reporter_user_id, reason_code, details, reporter_trust_weight, status, created_at, updated_at
        )
        values ($1, $2, $3, $4, $5, 1.00, 'open', now(), now())
      `,
        [reportId, input.projectId, reporterUserId, input.reasonCode, input.details],
      );

      const score = await client.query<{ score: string; reporters: string }>(
        `
        select
          coalesce(sum(reporter_trust_weight), 0)::text as score,
          count(distinct reporter_user_id)::text as reporters
        from moderation_reports
        where project_id = $1 and created_at >= now() - interval '24 hours'
      `,
        [input.projectId],
      );

      const trustScore24h = Number(score.rows[0]?.score ?? "0");
      const uniqueReporters24h = Number(score.rows[0]?.reporters ?? "0");
      const autoReviewTriggered = trustScore24h >= 5.0 && uniqueReporters24h >= 3;

      if (autoReviewTriggered) {
        await client.query(
          `
          update moderation_reports
          set status = 'under_review', updated_at = now()
          where project_id = $1 and status = 'open'
        `,
          [input.projectId],
        );
      }

      return {
        reportId,
        autoReviewTriggered,
        trustScore24h,
        uniqueReporters24h,
      } satisfies ModerationReportResult;
    } catch {
      return {
        reportId: randomUUID(),
        autoReviewTriggered: false,
        trustScore24h: 1,
        uniqueReporters24h: 1,
      } satisfies ModerationReportResult;
    } finally {
      client.release();
    }
  }

  async getOrCreatePayout(projectId: string) {
    if (!hasDb() || !dbPool) {
      return memory.getOrCreatePayout(projectId);
    }

    const client = await dbPool.connect();
    try {
      const existing = await client.query<{
        project_id: string;
        status: PayoutRecord["payoutStatus"];
        execution_start_at: string | Date;
        settlement_due_at: string | Date;
        settled_at: string | Date | null;
        rolling_reserve_enabled: false;
      }>(
        `
        select project_id, status, execution_start_at, settlement_due_at, settled_at, rolling_reserve_enabled
        from project_payouts
        where project_id = $1
      `,
        [projectId],
      );

      if (existing.rowCount && existing.rows[0]) {
        const row = existing.rows[0];
        return {
          projectId: row.project_id,
          payoutStatus: row.status,
          executionStartAt: toIso(row.execution_start_at),
          settlementDueAt: toIso(row.settlement_due_at),
          settledAt: row.settled_at ? toIso(row.settled_at) : undefined,
          rollingReserveEnabled: false,
        } satisfies PayoutRecord;
      }

      const project = await client.query<{ deadline_at: string | Date }>(
        `select deadline_at from projects where id = $1`,
        [projectId],
      );
      if (project.rowCount === 0) {
        return null;
      }

      const base = new Date(project.rows[0].deadline_at);
      const now = new Date();
      const executionStart = base > now ? new Date(base.getTime() + 24 * 60 * 60 * 1000) : new Date(now.getTime() + 24 * 60 * 60 * 1000);
      const settlementDue = new Date(executionStart.getTime() + 2 * 24 * 60 * 60 * 1000);

      await client.query(
        `
        insert into project_payouts (
          id, project_id, status, execution_start_at, settlement_due_at, rolling_reserve_enabled, created_at, updated_at
        )
        values ($1, $2, 'scheduled', $3, $4, false, now(), now())
      `,
        [randomUUID(), projectId, executionStart.toISOString(), settlementDue.toISOString()],
      );

      return {
        projectId,
        payoutStatus: "scheduled",
        executionStartAt: executionStart.toISOString(),
        settlementDueAt: settlementDue.toISOString(),
        rollingReserveEnabled: false,
      } satisfies PayoutRecord;
    } catch {
      return memory.getOrCreatePayout(projectId);
    } finally {
      client.release();
    }
  }

  async getOrCreateDispute(disputeId: string) {
    if (!hasDb() || !dbPool) {
      return memory.getOrCreateDispute(disputeId);
    }

    const client = await dbPool.connect();
    try {
      const row = await client.query<{
        id: string;
        status: DisputeRecord["status"];
        opened_at: string | Date;
        acknowledgement_due_at: string | Date;
        triage_due_at: string | Date;
        resolution_due_at: string | Date;
      }>(
        `
        select id, status, opened_at, acknowledgement_due_at, triage_due_at, resolution_due_at
        from disputes
        where id = $1
      `,
        [disputeId],
      );

      if (row.rowCount === 0) {
        return null;
      }

      const dispute = row.rows[0];
      return {
        disputeId: dispute.id,
        status: dispute.status,
        openedAt: toIso(dispute.opened_at),
        acknowledgementDueAt: toIso(dispute.acknowledgement_due_at),
        triageDueAt: toIso(dispute.triage_due_at),
        resolutionDueAt: toIso(dispute.resolution_due_at),
      } satisfies DisputeRecord;
    } catch {
      return memory.getOrCreateDispute(disputeId);
    } finally {
      client.release();
    }
  }

  async createDisputeRecoveryAttempt(input: {
    disputeId: string;
    action: "transfer_reversal_attempt" | "account_debit_attempt";
    amountMinor: number;
    currency: string;
    note?: string;
  }) {
    if (!hasDb() || !dbPool) {
      return { disputeId: input.disputeId, accepted: true } satisfies DisputeRecoveryResult;
    }

    const client = await dbPool.connect();
    try {
      const exists = await client.query(`select id from disputes where id = $1`, [input.disputeId]);
      if (exists.rowCount === 0) {
        return null;
      }

      await client.query(
        `
        insert into dispute_events (dispute_id, event_type, payload, occurred_at)
        values ($1, 'recovery_attempted', $2::jsonb, now())
      `,
        [
          input.disputeId,
          JSON.stringify({
            action: input.action,
            amount_minor: input.amountMinor,
            currency: input.currency,
            note: input.note,
          }),
        ],
      );

      return { disputeId: input.disputeId, accepted: true } satisfies DisputeRecoveryResult;
    } catch {
      return { disputeId: input.disputeId, accepted: true } satisfies DisputeRecoveryResult;
    } finally {
      client.release();
    }
  }


  async getProjectByCreator(creatorUserId: string) {
    return this.projectsService.getProjectByCreator(creatorUserId);
  }

  async listProjectsByCreator(creatorUserId: string) {
    return this.projectsService.listProjectsByCreator(creatorUserId);
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
    return this.projectsService.createProjectForCreator(input);
  }

  async deleteProjectForCreator(input: { creatorUserId: string; projectId: string }) {
    return this.projectsService.deleteProjectForCreator(input);
  }

  async endProjectForCreator(input: { creatorUserId: string; projectId: string; reason?: string }) {
    return this.projectsService.endProjectForCreator(input);
  }

  async createUploadSession(input?: {
    fileName?: string;
    contentType?: string;
    fileSizeBytes?: number;
    projectId?: string;
    creatorUserId?: string;
  }) {
    return this.uploadsService.createUploadSession(input);
  }

  async completeUploadSession(uploadSessionId: string, contentHashSha256: string, storageObjectKey?: string) {
    return this.uploadsService.completeUploadSession(uploadSessionId, contentHashSha256, storageObjectKey);
  }

  async getUploadSession(uploadSessionId: string) {
    return this.uploadsService.getUploadSession(uploadSessionId);
  }

  async writeUploadBinary(
    uploadSessionId: string,
    input: { contentType: string; payload: Buffer; fileName?: string },
  ) {
    return this.uploadsService.writeUploadBinary(uploadSessionId, input);
  }

  async listCreatorVideos(creatorUserId: string, limit = 30) {
    return this.uploadsService.listCreatorVideos(creatorUserId, limit);
  }

  async getVideoPlaybackById(videoId: string) {
    return this.uploadsService.getVideoPlaybackById(videoId);
  }

  async getVideoThumbnailById(videoId: string) {
    return this.uploadsService.getVideoThumbnailById(videoId);
  }

  async deleteCreatorVideo(creatorUserId: string, videoId: string) {
    return this.uploadsService.deleteCreatorVideo(creatorUserId, videoId);
  }
}

export const store = new HybridStore();
