import { randomUUID } from "node:crypto";
import { createHash } from "node:crypto";
import { mkdir, stat, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { dbPool, hasDb } from "./db.js";
import { InMemoryStore } from "./inMemory.js";
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

function normalizeCurrency(value: string | undefined, fallback = "JPY") {
  return (value ?? fallback).toUpperCase().slice(0, 3);
}

function toIso(value: Date | string) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

export class HybridStore {
  async prepareSupport(input: { projectId: string; planId: string; quantity: number }) {
    if (!hasDb() || !dbPool) {
      return memory.prepareSupport(input);
    }

    const client = await dbPool.connect();
    try {
      const planRow = await client.query<{ price_minor: number; currency: string }>(
        `
        select price_minor, currency
        from project_plans
        where id = $1 and project_id = $2
      `,
        [input.planId, input.projectId],
      );

      if (planRow.rowCount === 0) {
        return null;
      }

      const amountMinor = Number(planRow.rows[0].price_minor) * input.quantity;
      const currency = planRow.rows[0].currency;
      const supportId = randomUUID();
      const checkoutSessionId = randomUUID();

      const devSupporter = process.env.LIFECAST_DEV_SUPPORTER_USER_ID;
      if (!devSupporter) {
        return memory.prepareSupport(input);
      }

      await client.query(
        `
        insert into support_transactions (
          id, project_id, plan_id, supporter_user_id,
          amount_minor, currency, status,
          reward_type, cancellation_window_hours,
          provider, provider_checkout_session_id,
          prepared_at, created_at, updated_at
        )
        values (
          $1, $2, $3, $4,
          $5, $6, 'prepared',
          'physical', 48,
          'stripe', $7,
          now(), now(), now()
        )
      `,
        [supportId, input.projectId, input.planId, devSupporter, amountMinor, currency, checkoutSessionId],
      );

      await client.query(
        `
        insert into support_status_history (support_id, from_status, to_status, reason, actor, occurred_at)
        values ($1, null, 'prepared', 'support_prepared', 'system', now())
      `,
        [supportId],
      );

      return {
        supportId,
        projectId: input.projectId,
        planId: input.planId,
        amountMinor,
        currency,
        status: "prepared",
        rewardType: "physical",
        cancellationWindowHours: 48,
        checkoutSessionId,
      } satisfies SupportRecord;
    } catch {
      return memory.prepareSupport(input);
    } finally {
      client.release();
    }
  }

  async confirmSupport(supportId: string) {
    if (!hasDb() || !dbPool) {
      return memory.confirmSupport(supportId);
    }

    const client = await dbPool.connect();
    try {
      const current = await client.query<{ status: SupportRecord["status"] }>(
        `
        select status
        from support_transactions
        where id = $1
      `,
        [supportId],
      );

      if (current.rowCount === 0) {
        return null;
      }

      const fromStatus = current.rows[0].status;
      if (fromStatus === "pending_confirmation" || fromStatus === "succeeded") {
        return this.getSupport(supportId);
      }

      const row = await client.query<{
        id: string;
        project_id: string;
        plan_id: string;
        amount_minor: number;
        currency: string;
        status: SupportRecord["status"];
        reward_type: "physical";
        cancellation_window_hours: 48;
      }>(
        `
        update support_transactions
        set status = 'pending_confirmation',
            confirmed_at = now(),
            updated_at = now()
        where id = $1
        returning id, project_id, plan_id, amount_minor, currency, status, reward_type, cancellation_window_hours
      `,
        [supportId],
      );

      if (row.rowCount === 0) {
        return null;
      }

      await client.query(
        `
        insert into support_status_history (support_id, from_status, to_status, reason, actor, occurred_at)
        values ($1, $2, 'pending_confirmation', 'support_confirmed', 'user', now())
      `,
        [supportId, fromStatus],
      );

      const record = row.rows[0];
      return {
        supportId: record.id,
        projectId: record.project_id,
        planId: record.plan_id,
        amountMinor: Number(record.amount_minor),
        currency: record.currency,
        status: record.status,
        rewardType: record.reward_type,
        cancellationWindowHours: record.cancellation_window_hours,
      } satisfies SupportRecord;
    } catch {
      return memory.confirmSupport(supportId);
    } finally {
      client.release();
    }
  }

  async getSupport(supportId: string) {
    if (!hasDb() || !dbPool) {
      return memory.getSupport(supportId);
    }

    const client = await dbPool.connect();
    try {
      const row = await client.query<{
        id: string;
        project_id: string;
        plan_id: string;
        amount_minor: number;
        currency: string;
        status: SupportRecord["status"];
        reward_type: "physical";
        cancellation_window_hours: 48;
        provider_checkout_session_id: string | null;
      }>(
        `
        select id, project_id, plan_id, amount_minor, currency, status, reward_type, cancellation_window_hours, provider_checkout_session_id
        from support_transactions
        where id = $1
      `,
        [supportId],
      );

      if (row.rowCount === 0) {
        return null;
      }

      const record = row.rows[0];
      return {
        supportId: record.id,
        projectId: record.project_id,
        planId: record.plan_id,
        amountMinor: Number(record.amount_minor),
        currency: record.currency,
        status: record.status,
        rewardType: record.reward_type,
        cancellationWindowHours: record.cancellation_window_hours,
        checkoutSessionId: record.provider_checkout_session_id ?? undefined,
      } satisfies SupportRecord;
    } catch {
      return memory.getSupport(supportId);
    } finally {
      client.release();
    }
  }

  async markSupportSucceededByWebhook(supportId: string) {
    if (!hasDb() || !dbPool) {
      return memory.markSupportSucceededByWebhook(supportId);
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const current = await client.query<{
        id: string;
        project_id: string;
        plan_id: string;
        supporter_user_id: string;
        amount_minor: number;
        currency: string;
        status: SupportRecord["status"];
        reward_type: "physical";
        cancellation_window_hours: 48;
      }>(
        `
        select id, project_id, plan_id, supporter_user_id, amount_minor, currency, status, reward_type, cancellation_window_hours
        from support_transactions
        where id = $1
        for update
      `,
        [supportId],
      );

      if (current.rowCount === 0) {
        await client.query("rollback");
        return null;
      }

      const existing = current.rows[0];
      if (existing.status === "succeeded") {
        await client.query("commit");
        return {
          supportId: existing.id,
          projectId: existing.project_id,
          planId: existing.plan_id,
          amountMinor: Number(existing.amount_minor),
          currency: existing.currency,
          status: existing.status,
          rewardType: existing.reward_type,
          cancellationWindowHours: existing.cancellation_window_hours,
        } satisfies SupportRecord;
      }

      const row = await client.query<{
        id: string;
        project_id: string;
        plan_id: string;
        supporter_user_id: string;
        amount_minor: number;
        currency: string;
        status: SupportRecord["status"];
        reward_type: "physical";
        cancellation_window_hours: 48;
      }>(
        `
        update support_transactions
        set status = 'succeeded',
            succeeded_at = now(),
            updated_at = now()
        where id = $1
        returning id, project_id, plan_id, supporter_user_id, amount_minor, currency, status, reward_type, cancellation_window_hours
      `,
        [supportId],
      );

      if (row.rowCount === 0) {
        await client.query("rollback");
        return null;
      }

      const support = row.rows[0];

      await client.query(
        `
        insert into support_status_history (support_id, from_status, to_status, reason, actor, occurred_at)
        values ($1, $2, 'succeeded', 'webhook_confirmed', 'system', now())
      `,
        [support.id, existing.status],
      );

      const entryId = randomUUID();
      await client.query(
        `
        insert into journal_entries (id, entry_type, project_id, support_id, occurred_at, description)
        values ($1, 'support_hold', $2, $3, now(), 'Support succeeded and funds held')
      `,
        [entryId, support.project_id, support.id],
      );

      await client.query(
        `
        insert into journal_lines (journal_entry_id, ledger_account_id, currency, debit_minor, credit_minor)
        values
          ($1, (select id from ledger_accounts where code = 'CASH_CLEARING'), $2, $3, 0),
          ($1, (select id from ledger_accounts where code = 'SUPPORT_LIABILITY'), $2, 0, $3)
      `,
        [entryId, support.currency, Number(support.amount_minor)],
      );

      const creatorRow = await client.query<{ creator_user_id: string }>(
        `select creator_user_id from projects where id = $1`,
        [support.project_id],
      );

      const creatorUserId = creatorRow.rows[0]?.creator_user_id;
      if (creatorUserId) {
        await client.query(
          `
          insert into notification_events (id, user_id, channel, event_key, payload, send_after, created_at)
          values
            ($1, $2, 'push', 'support_succeeded_creator', $3::jsonb, now(), now()),
            ($4, $2, 'in_app', 'support_succeeded_creator', $3::jsonb, now(), now())
        `,
          [
            randomUUID(),
            creatorUserId,
            JSON.stringify({ support_id: support.id, project_id: support.project_id }),
            randomUUID(),
          ],
        );
      }

      await client.query(
        `
        insert into notification_events (id, user_id, channel, event_key, payload, send_after, created_at)
        values
          ($1, $2, 'push', 'support_payment_succeeded', $3::jsonb, now(), now()),
          ($4, $2, 'in_app', 'support_payment_succeeded', $3::jsonb, now(), now()),
          ($5, $2, 'email', 'support_payment_succeeded', $3::jsonb, now(), now())
      `,
        [
          randomUUID(),
          support.supporter_user_id,
          JSON.stringify({ support_id: support.id, project_id: support.project_id }),
          randomUUID(),
          randomUUID(),
        ],
      );

      await client.query("commit");

      return {
        supportId: support.id,
        projectId: support.project_id,
        planId: support.plan_id,
        amountMinor: Number(support.amount_minor),
        currency: support.currency,
        status: support.status,
        rewardType: support.reward_type,
        cancellationWindowHours: support.cancellation_window_hours,
      } satisfies SupportRecord;
    } catch {
      await client.query("rollback");
      return memory.markSupportSucceededByWebhook(supportId);
    } finally {
      client.release();
    }
  }

  async markSupportRefundedByWebhook(input: { supportId: string; providerRefundId?: string; reasonCode?: string }) {
    if (!hasDb() || !dbPool) {
      const existing = await memory.getSupport(input.supportId);
      if (!existing) return null;
      existing.status = "refunded";
      return existing;
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const current = await client.query<{
        id: string;
        project_id: string;
        plan_id: string;
        supporter_user_id: string;
        amount_minor: number;
        currency: string;
        status: SupportRecord["status"];
        reward_type: "physical";
        cancellation_window_hours: 48;
      }>(
        `
        select id, project_id, plan_id, supporter_user_id, amount_minor, currency, status, reward_type, cancellation_window_hours
        from support_transactions
        where id = $1
        for update
      `,
        [input.supportId],
      );

      if (current.rowCount === 0) {
        await client.query("rollback");
        return null;
      }

      const support = current.rows[0];
      if (support.status === "refunded") {
        await client.query("commit");
        return {
          supportId: support.id,
          projectId: support.project_id,
          planId: support.plan_id,
          amountMinor: Number(support.amount_minor),
          currency: support.currency,
          status: support.status,
          rewardType: support.reward_type,
          cancellationWindowHours: support.cancellation_window_hours,
        } satisfies SupportRecord;
      }

      await client.query(
        `
        update support_transactions
        set status = 'refunded',
            refunded_at = now(),
            updated_at = now()
        where id = $1
      `,
        [input.supportId],
      );

      await client.query(
        `
        insert into support_status_history (support_id, from_status, to_status, reason, actor, occurred_at)
        values ($1, $2, 'refunded', 'webhook_refund_confirmed', 'system', now())
      `,
        [input.supportId, support.status],
      );

      await client.query(
        `
        insert into refund_records (
          support_id, reason_code, amount_minor, currency, provider_refund_id, status, requested_at, completed_at
        )
        values ($1, $2, $3, $4, $5, 'succeeded', now(), now())
        on conflict (support_id)
        do update set
          reason_code = excluded.reason_code,
          provider_refund_id = coalesce(excluded.provider_refund_id, refund_records.provider_refund_id),
          status = 'succeeded',
          completed_at = now()
      `,
        [
          input.supportId,
          input.reasonCode ?? "refund_webhook",
          Number(support.amount_minor),
          support.currency,
          input.providerRefundId ?? null,
        ],
      );

      const entryId = randomUUID();
      await client.query(
        `
        insert into journal_entries (id, entry_type, project_id, support_id, occurred_at, description)
        values ($1, 'refund', $2, $3, now(), 'Support refund completed')
      `,
        [entryId, support.project_id, support.id],
      );

      await client.query(
        `
        insert into journal_lines (journal_entry_id, ledger_account_id, currency, debit_minor, credit_minor)
        values
          ($1, (select id from ledger_accounts where code = 'SUPPORT_LIABILITY'), $2, $3, 0),
          ($1, (select id from ledger_accounts where code = 'CASH_CLEARING'), $2, 0, $3)
      `,
        [entryId, support.currency, Number(support.amount_minor)],
      );

      await client.query("commit");
      return {
        supportId: support.id,
        projectId: support.project_id,
        planId: support.plan_id,
        amountMinor: Number(support.amount_minor),
        currency: support.currency,
        status: "refunded",
        rewardType: support.reward_type,
        cancellationWindowHours: support.cancellation_window_hours,
      } satisfies SupportRecord;
    } catch {
      await client.query("rollback");
      return null;
    } finally {
      client.release();
    }
  }

  async createDisputeFromWebhook(input: {
    providerDisputeId: string;
    supportId: string;
    amountMinor: number;
    currency: string;
    reason?: string;
  }) {
    if (!hasDb() || !dbPool) {
      return null;
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const support = await client.query<{ id: string; project_id: string; currency: string }>(
        `
        select id, project_id, currency
        from support_transactions
        where id = $1
      `,
        [input.supportId],
      );
      if (!support.rowCount) {
        await client.query("rollback");
        return null;
      }

      const supportRow = support.rows[0];
      const amountMinor = Math.max(1, input.amountMinor);
      const currency = normalizeCurrency(input.currency || supportRow.currency);

      const dispute = await client.query<{ id: string; project_id: string }>(
        `
        insert into disputes (
          support_id, project_id, provider, provider_dispute_id, status, amount_minor, currency, opened_at, created_at, updated_at
        )
        values ($1, $2, 'stripe', $3, 'open', $4, $5, now(), now(), now())
        on conflict (provider_dispute_id)
        do update set updated_at = now()
        returning id, project_id
      `,
        [input.supportId, supportRow.project_id, input.providerDisputeId, amountMinor, currency],
      );

      const disputeId = dispute.rows[0].id;
      const entryId = randomUUID();
      await client.query(
        `
        insert into journal_entries (id, entry_type, project_id, support_id, dispute_id, occurred_at, description)
        values ($1, 'dispute_open', $2, $3, $4, now(), 'Dispute opened and reserve moved')
      `,
        [entryId, supportRow.project_id, input.supportId, disputeId],
      );

      await client.query(
        `
        insert into journal_lines (journal_entry_id, ledger_account_id, currency, debit_minor, credit_minor)
        values
          ($1, (select id from ledger_accounts where code = 'SUPPORT_LIABILITY'), $2, $3, 0),
          ($1, (select id from ledger_accounts where code = 'DISPUTE_RESERVE'), $2, 0, $3)
      `,
        [entryId, currency, amountMinor],
      );

      await client.query(
        `
        insert into dispute_events (dispute_id, event_type, payload, occurred_at)
        values ($1, 'dispute_opened', $2::jsonb, now())
      `,
        [disputeId, JSON.stringify({ reason: input.reason ?? "webhook_dispute_opened", amount_minor: amountMinor, currency })],
      );

      await client.query("commit");
      return { disputeId };
    } catch {
      await client.query("rollback");
      return null;
    } finally {
      client.release();
    }
  }

  async closeDisputeFromWebhook(input: { providerDisputeId: string; outcome: "won" | "lost"; reason?: string }) {
    if (!hasDb() || !dbPool) {
      return null;
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const dispute = await client.query<{
        id: string;
        support_id: string;
        project_id: string;
        amount_minor: number;
        currency: string;
        status: DisputeRecord["status"];
      }>(
        `
        select id, support_id, project_id, amount_minor, currency, status
        from disputes
        where provider_dispute_id = $1
        for update
      `,
        [input.providerDisputeId],
      );
      if (!dispute.rowCount) {
        await client.query("rollback");
        return null;
      }

      const d = dispute.rows[0];
      const nextStatus = input.outcome;
      if (d.status === nextStatus || d.status === "closed") {
        await client.query("commit");
        return { disputeId: d.id };
      }

      await client.query(
        `
        update disputes
        set status = $2, resolved_at = now(), updated_at = now(), final_liability = $3
        where id = $1
      `,
        [d.id, nextStatus, nextStatus === "lost" ? "platform" : "unknown"],
      );

      const closeEntryId = randomUUID();
      await client.query(
        `
        insert into journal_entries (id, entry_type, project_id, support_id, dispute_id, occurred_at, description)
        values ($1, 'dispute_close', $2, $3, $4, now(), 'Dispute closed by webhook')
      `,
        [closeEntryId, d.project_id, d.support_id, d.id],
      );

      if (nextStatus === "won") {
        await client.query(
          `
          insert into journal_lines (journal_entry_id, ledger_account_id, currency, debit_minor, credit_minor)
          values
            ($1, (select id from ledger_accounts where code = 'DISPUTE_RESERVE'), $2, $3, 0),
            ($1, (select id from ledger_accounts where code = 'SUPPORT_LIABILITY'), $2, 0, $3)
        `,
          [closeEntryId, d.currency, Number(d.amount_minor)],
        );
      } else {
        await client.query(
          `
          insert into journal_lines (journal_entry_id, ledger_account_id, currency, debit_minor, credit_minor)
          values
            ($1, (select id from ledger_accounts where code = 'DISPUTE_RESERVE'), $2, $3, 0),
            ($1, (select id from ledger_accounts where code = 'CASH_CLEARING'), $2, 0, $3)
        `,
          [closeEntryId, d.currency, Number(d.amount_minor)],
        );
      }

      await client.query(
        `
        insert into dispute_events (dispute_id, event_type, payload, occurred_at)
        values ($1, $2, $3::jsonb, now())
      `,
        [
          d.id,
          nextStatus === "won" ? "dispute_resolved_won" : "dispute_resolved_lost",
          JSON.stringify({ reason: input.reason ?? "webhook_dispute_closed", outcome: nextStatus }),
        ],
      );

      if (nextStatus === "lost") {
        const lossEntryId = randomUUID();
        await client.query(
          `
          insert into journal_entries (id, entry_type, project_id, support_id, dispute_id, occurred_at, description)
          values ($1, 'loss_booking', $2, $3, $4, now(), 'Dispute loss booked')
        `,
          [lossEntryId, d.project_id, d.support_id, d.id],
        );

        await client.query(
          `
          insert into journal_lines (journal_entry_id, ledger_account_id, currency, debit_minor, credit_minor)
          values
            ($1, (select id from ledger_accounts where code = 'DISPUTE_LOSS_EXPENSE'), $2, $3, 0),
            ($1, (select id from ledger_accounts where code = 'SUPPORT_LIABILITY'), $2, 0, $3)
        `,
          [lossEntryId, d.currency, Number(d.amount_minor)],
        );

        await client.query(
          `
          insert into dispute_events (dispute_id, event_type, payload, occurred_at)
          values ($1, 'recovery_failed_loss_booked', $2::jsonb, now())
        `,
          [d.id, JSON.stringify({ amount_minor: d.amount_minor, currency: d.currency })],
        );
      }

      await client.query("commit");
      return { disputeId: d.id };
    } catch {
      await client.query("rollback");
      return null;
    } finally {
      client.release();
    }
  }

  async recordPayoutRelease(input: { projectId: string; amountMinor: number; currency: string }) {
    if (!hasDb() || !dbPool) {
      return { projectId: input.projectId, ok: true };
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const project = await client.query(`select id from projects where id = $1`, [input.projectId]);
      if (!project.rowCount) {
        await client.query("rollback");
        return null;
      }

      const amountMinor = Math.max(1, input.amountMinor);
      const currency = normalizeCurrency(input.currency);
      const entryId = randomUUID();
      await client.query(
        `
        insert into journal_entries (id, entry_type, project_id, occurred_at, description)
        values ($1, 'payout_release', $2, now(), 'Project payout released')
      `,
        [entryId, input.projectId],
      );

      await client.query(
        `
        insert into journal_lines (journal_entry_id, ledger_account_id, currency, debit_minor, credit_minor)
        values
          ($1, (select id from ledger_accounts where code = 'SUPPORT_LIABILITY'), $2, $3, 0),
          ($1, (select id from ledger_accounts where code = 'CREATOR_PAYABLE'), $2, 0, $3),
          ($1, (select id from ledger_accounts where code = 'CREATOR_PAYABLE'), $2, $3, 0),
          ($1, (select id from ledger_accounts where code = 'CASH_CLEARING'), $2, 0, $3)
      `,
        [entryId, currency, amountMinor],
      );

      await client.query(
        `
        update project_payouts
        set status = 'settled', settled_at = now(), updated_at = now()
        where project_id = $1
      `,
        [input.projectId],
      );

      await client.query("commit");
      return { projectId: input.projectId, ok: true };
    } catch {
      await client.query("rollback");
      return null;
    } finally {
      client.release();
    }
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

  async createUploadSession(input?: { fileName?: string; contentType?: string; fileSizeBytes?: number }) {
    if (!hasDb() || !dbPool) {
      return memory.createUploadSession({ fileName: input?.fileName });
    }

    const client = await dbPool.connect();
    try {
      const uploadSessionId = randomUUID();
      let creatorUserId = process.env.LIFECAST_DEV_CREATOR_USER_ID;
      if (!creatorUserId) {
        const fallbackCreator = await client.query<{ id: string }>(`select id from users order by created_at asc limit 1`);
        creatorUserId = fallbackCreator.rows[0]?.id;
      }
      if (!creatorUserId) {
        return memory.createUploadSession({ fileName: input?.fileName });
      }

      const safeFileName = input?.fileName?.trim().slice(0, 255) || `upload-${uploadSessionId}.mp4`;
      const contentType = input?.contentType || "video/mp4";
      const fileSizeBytes = Math.max(1, Number(input?.fileSizeBytes ?? 1));
      const publicBaseUrl = (process.env.LIFECAST_PUBLIC_BASE_URL || "http://localhost:8080").replace(/\/$/, "");
      const cloudflareUpload = hasCloudflareStreamConfig() ? await createCloudflareDirectUpload() : null;
      const uploadUrl = cloudflareUpload?.uploadURL ?? `${publicBaseUrl}/v1/videos/uploads/${uploadSessionId}/binary`;
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();

      await client.query(
        `
        insert into video_upload_sessions (
          id, creator_user_id, status, file_name, content_type, file_size_bytes,
          provider_upload_id, created_at, updated_at
        )
        values ($1, $2, 'created', $3, $4, $5, $6, now(), now())
      `,
        [
          uploadSessionId,
          creatorUserId,
          safeFileName,
          contentType,
          fileSizeBytes,
          cloudflareUpload?.uid ?? uploadSessionId,
        ],
      );

      return {
        uploadSessionId,
        status: "created",
        uploadUrl,
        expiresAt,
      } satisfies UploadSession;
    } catch {
      return memory.createUploadSession({ fileName: input?.fileName });
    } finally {
      client.release();
    }
  }

  async completeUploadSession(uploadSessionId: string, contentHashSha256: string, storageObjectKey?: string) {
    if (!hasDb() || !dbPool) {
      return memory.completeUploadSession(uploadSessionId, contentHashSha256, storageObjectKey);
    }

    const client = await dbPool.connect();
    try {
      await client.query("begin");
      const generatedVideoId = randomUUID();
      const uploadObjectKey = storageObjectKey || `raw/${uploadSessionId}/source.mp4`;
      const result = await client.query<{
        id: string;
        status: UploadSession["status"];
        provider_upload_id: string | null;
        provider_asset_id: string | null;
        creator_user_id: string;
        storage_object_key: string | null;
      }>(
        `
        update video_upload_sessions
        set status = 'processing',
            content_hash_sha256 = $2,
            storage_object_key = coalesce($3, storage_object_key),
            provider_asset_id = coalesce(provider_asset_id, $4),
            processing_started_at = now(),
            processing_deadline_at = now() + interval '30 minutes',
            completed_at = coalesce(completed_at, now()),
            updated_at = now()
        where id = $1
        returning id, status, provider_upload_id, provider_asset_id, creator_user_id, storage_object_key
      `,
        [uploadSessionId, contentHashSha256, uploadObjectKey, generatedVideoId],
      );

      if (result.rowCount === 0) {
        await client.query("rollback");
        // If createUploadSession fell back to in-memory, allow complete via same fallback path.
        return memory.completeUploadSession(uploadSessionId, contentHashSha256, storageObjectKey);
      }

      const row = result.rows[0];
      const cloudflareMode = hasCloudflareStreamConfig();
      const videoId = row.provider_asset_id ?? row.provider_upload_id ?? generatedVideoId;

      await client.query(
        `
        insert into video_assets (
          video_id, creator_user_id, upload_session_id, status, origin_object_key, created_at, updated_at
        )
        values ($1, $2, $3, 'processing', $4, now(), now())
        on conflict (video_id)
        do update set
          status = 'processing',
          origin_object_key = coalesce(excluded.origin_object_key, video_assets.origin_object_key),
          updated_at = now()
      `,
        [videoId, row.creator_user_id, row.id, row.storage_object_key ?? uploadObjectKey],
      );
      if (!cloudflareMode) {
        await client.query(
          `
          insert into video_processing_jobs (id, video_id, stage, status, attempt, run_after, created_at, updated_at)
          values ($1, $2, 'probe', 'pending', 0, now(), now(), now())
          on conflict do nothing
        `,
          [randomUUID(), videoId],
        );
      }

      await client.query(
        `
        insert into outbox_events (event_id, topic, payload, status, next_attempt_at)
        values ($1, 'video.upload.completed', $2::jsonb, 'pending', now())
        on conflict (event_id) do nothing
      `,
        [
          randomUUID(),
          JSON.stringify({
            event_name: "video_upload_completed",
            upload_session_id: row.id,
            video_id: videoId,
            creator_user_id: row.creator_user_id,
            content_hash_sha256: contentHashSha256,
            occurred_at: new Date().toISOString(),
          }),
        ],
      );

      await client.query("commit");
      return {
        uploadSessionId: row.id,
        status: row.status,
        videoId,
        contentHashSha256,
        storageObjectKey: row.storage_object_key ?? uploadObjectKey,
      } satisfies UploadSession;
    } catch (error) {
      await client.query("rollback");
      const pgError = error as { code?: string; constraint?: string; message?: string };
      if (pgError.code === "23505" && pgError.constraint === "uq_upload_hash_per_creator") {
        const conflict = new Error("Upload content hash already exists for this creator");
        (conflict as Error & { code: string }).code = "UPLOAD_HASH_CONFLICT";
        throw conflict;
      }
      throw error;
    } finally {
      client.release();
    }
  }

  async getUploadSession(uploadSessionId: string) {
    if (!hasDb() || !dbPool) {
      return memory.getUploadSession(uploadSessionId);
    }

    const client = await dbPool.connect();
    try {
      const result = await client.query<{
        id: string;
        status: UploadSession["status"];
        provider_upload_id: string | null;
        provider_asset_id: string | null;
        content_hash_sha256: string | null;
        storage_object_key: string | null;
        created_at: string | Date;
      }>(
        `
        select id, status, provider_upload_id, provider_asset_id, content_hash_sha256, storage_object_key, created_at
        from video_upload_sessions
        where id = $1
      `,
        [uploadSessionId],
      );

      if (result.rowCount === 0) {
        // If session only exists in memory fallback, keep behavior consistent.
        return memory.getUploadSession(uploadSessionId);
      }

      const row = result.rows[0];
      const uploadUrl = `https://upload.lifecast.jp/${row.id}`;
      const expiresAt = new Date(new Date(row.created_at).getTime() + 60 * 60 * 1000).toISOString();
      let latestStatus = row.status;
      let latestVideoId = row.provider_asset_id ?? row.provider_upload_id ?? undefined;

      if (hasCloudflareStreamConfig() && row.provider_upload_id) {
        const details = await getCloudflareVideoDetails(row.provider_upload_id);
        if (details?.readyToStream) {
          latestStatus = "ready";
          latestVideoId = details.uid;
          await client.query(
            `
            update video_upload_sessions
            set status = 'ready',
                provider_asset_id = $2,
                updated_at = now()
            where id = $1
          `,
            [uploadSessionId, details.uid],
          );
          await client.query(
            `
            update video_assets
            set status = 'ready',
                manifest_url = coalesce($2, manifest_url),
                thumbnail_url = coalesce($3, thumbnail_url),
                updated_at = now()
            where video_id = $1
          `,
            [details.uid, details.playbackUrl ?? details.preview ?? null, details.thumbnail ?? null],
          );
        }
      }

      return {
        uploadSessionId: row.id,
        status: latestStatus,
        videoId: latestVideoId,
        contentHashSha256: row.content_hash_sha256 ?? undefined,
        storageObjectKey: row.storage_object_key ?? undefined,
        uploadUrl,
        expiresAt,
      } satisfies UploadSession;
    } catch {
      return memory.getUploadSession(uploadSessionId);
    } finally {
      client.release();
    }
  }

  async writeUploadBinary(
    uploadSessionId: string,
    input: { contentType: string; payload: Buffer; fileName?: string },
  ) {
    if (!hasDb() || !dbPool) {
      const fallbackKey = `local/${uploadSessionId}/source.mp4`;
      const hash = createHash("sha256").update(input.payload).digest("hex");
      return memory.writeUploadBinary(uploadSessionId, {
        storageObjectKey: fallbackKey,
        contentHashSha256: hash,
      });
    }

    const client = await dbPool.connect();
    try {
      const sessionResult = await client.query<{
        id: string;
        file_name: string;
      }>(
        `
        select id, file_name
        from video_upload_sessions
        where id = $1
      `,
        [uploadSessionId],
      );

      if (sessionResult.rowCount === 0) {
        return null;
      }

      const safeName = (input.fileName?.trim() || sessionResult.rows[0].file_name || "source.mp4").replace(/[^A-Za-z0-9._-]/g, "_");
      const objectKey = `local/${uploadSessionId}/${safeName}`;
      const absolutePath = resolve(LOCAL_VIDEO_ROOT, objectKey);
      const hash = createHash("sha256").update(input.payload).digest("hex");

      await mkdir(dirname(absolutePath), { recursive: true });
      await writeFile(absolutePath, input.payload);
      await stat(absolutePath);

      await client.query(
        `
        update video_upload_sessions
        set status = 'uploading',
            storage_object_key = $2,
            content_type = $3,
            file_size_bytes = $4,
            updated_at = now()
        where id = $1
      `,
        [uploadSessionId, objectKey, input.contentType, input.payload.byteLength],
      );

      return {
        uploadSessionId,
        storageObjectKey: objectKey,
        contentHashSha256: hash,
        bytesStored: input.payload.byteLength,
      };
    } finally {
      client.release();
    }
  }

  async listCreatorVideos(creatorUserId: string, limit = 30) {
    if (!hasDb() || !dbPool) {
      return memory.listCreatorVideos(creatorUserId);
    }

    const client = await dbPool.connect();
    try {
      const publicBaseUrl = (process.env.LIFECAST_PUBLIC_BASE_URL || "http://localhost:8080").replace(/\/$/, "");
      const result = await client.query<{
        video_id: string;
        status: UploadSession["status"];
        file_name: string;
        created_at: string | Date;
      }>(
        `
        select
          va.video_id,
          va.status,
          vus.file_name,
          va.created_at
        from video_assets va
        join video_upload_sessions vus on vus.id = va.upload_session_id
        where va.creator_user_id = $1
          and va.status = 'ready'
        order by va.created_at desc
        limit $2
      `,
        [creatorUserId, Math.min(Math.max(limit, 1), 100)],
      );

      return result.rows.map((row) => ({
        videoId: row.video_id,
        status: row.status,
        fileName: row.file_name,
        playbackUrl: `${publicBaseUrl}/v1/videos/${row.video_id}/playback`,
        createdAt: toIso(row.created_at),
      })) satisfies CreatorVideoRecord[];
    } finally {
      client.release();
    }
  }

  async getVideoPlaybackById(videoId: string) {
    if (!hasDb() || !dbPool) {
      return memory.getPlaybackByVideoId(videoId);
    }

    const client = await dbPool.connect();
    try {
      const result = await client.query<{
        video_id: string;
        status: UploadSession["status"];
        origin_object_key: string | null;
        manifest_url: string | null;
        thumbnail_url: string | null;
        content_type: string;
      }>(
        `
        select
          va.video_id,
          va.status,
          va.origin_object_key,
          va.manifest_url,
          va.thumbnail_url,
          vus.content_type
        from video_assets va
        join video_upload_sessions vus on vus.id = va.upload_session_id
        where va.video_id = $1
      `,
        [videoId],
      );

      if (result.rowCount === 0) return null;
      const row = result.rows[0];
      if (row.manifest_url && /^https?:\/\//.test(row.manifest_url)) {
        let shouldUseExternal = true;
        try {
          const parsed = new URL(row.manifest_url);
          // Guard against bad data that points manifest_url back to this API playback endpoint.
          if (parsed.pathname === `/v1/videos/${row.video_id}/playback`) {
            shouldUseExternal = false;
          }
        } catch {
          shouldUseExternal = false;
        }

        if (shouldUseExternal) {
          return {
            videoId: row.video_id,
            status: row.status,
            contentType: "application/vnd.apple.mpegurl",
            externalPlaybackUrl: row.manifest_url,
          };
        }
      }
      if (!row.origin_object_key) return null;

      return {
        videoId: row.video_id,
        status: row.status,
        contentType: row.content_type || "video/mp4",
        absolutePath: resolve(LOCAL_VIDEO_ROOT, row.origin_object_key),
      };
    } finally {
      client.release();
    }
  }
}

export const store = new HybridStore();
