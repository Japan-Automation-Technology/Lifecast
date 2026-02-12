import { randomUUID } from "node:crypto";
import { dbPool, hasDb } from "./db.js";
import { InMemoryStore } from "./inMemory.js";
import type {
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

const memory = new InMemoryStore();

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
        values ($1, 'pending_confirmation', 'succeeded', 'webhook_confirmed', 'system', now())
      `,
        [support.id],
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

  async listJournalEntries(filters: { projectId?: string; supportId?: string; limit?: number }) {
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

  async createUploadSession() {
    if (!hasDb() || !dbPool) {
      return memory.createUploadSession();
    }

    const creatorUserId = process.env.LIFECAST_DEV_CREATOR_USER_ID;
    if (!creatorUserId) {
      return memory.createUploadSession();
    }

    const client = await dbPool.connect();
    try {
      const uploadSessionId = randomUUID();
      const uploadUrl = `https://upload.lifecast.jp/${uploadSessionId}`;
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();

      await client.query(
        `
        insert into video_upload_sessions (
          id, creator_user_id, status, file_name, content_type, file_size_bytes,
          provider_upload_id, created_at, updated_at
        )
        values ($1, $2, 'created', $3, 'video/mp4', 1, $4, now(), now())
      `,
        [uploadSessionId, creatorUserId, `upload-${uploadSessionId}.mp4`, uploadSessionId],
      );

      return {
        uploadSessionId,
        status: "created",
        uploadUrl,
        expiresAt,
      } satisfies UploadSession;
    } catch {
      return memory.createUploadSession();
    } finally {
      client.release();
    }
  }

  async completeUploadSession(uploadSessionId: string, contentHashSha256: string) {
    if (!hasDb() || !dbPool) {
      return memory.completeUploadSession(uploadSessionId, contentHashSha256);
    }

    const client = await dbPool.connect();
    try {
      const result = await client.query<{
        id: string;
        status: UploadSession["status"];
        provider_asset_id: string | null;
      }>(
        `
        update video_upload_sessions
        set status = 'processing',
            content_hash_sha256 = $2,
            processing_started_at = now(),
            processing_deadline_at = now() + interval '30 minutes',
            updated_at = now()
        where id = $1
        returning id, status, provider_asset_id
      `,
        [uploadSessionId, contentHashSha256],
      );

      if (result.rowCount === 0) {
        return null;
      }

      const row = result.rows[0];
      return {
        uploadSessionId: row.id,
        status: row.status,
        videoId: row.provider_asset_id ?? undefined,
        contentHashSha256,
      } satisfies UploadSession;
    } catch {
      return memory.completeUploadSession(uploadSessionId, contentHashSha256);
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
        provider_asset_id: string | null;
        content_hash_sha256: string | null;
        created_at: string | Date;
      }>(
        `
        select id, status, provider_asset_id, content_hash_sha256, created_at
        from video_upload_sessions
        where id = $1
      `,
        [uploadSessionId],
      );

      if (result.rowCount === 0) {
        return null;
      }

      const row = result.rows[0];
      const uploadUrl = `https://upload.lifecast.jp/${row.id}`;
      const expiresAt = new Date(new Date(row.created_at).getTime() + 60 * 60 * 1000).toISOString();

      return {
        uploadSessionId: row.id,
        status: row.status,
        videoId: row.provider_asset_id ?? undefined,
        contentHashSha256: row.content_hash_sha256 ?? undefined,
        uploadUrl,
        expiresAt,
      } satisfies UploadSession;
    } catch {
      return memory.getUploadSession(uploadSessionId);
    } finally {
      client.release();
    }
  }
}

export const store = new HybridStore();
