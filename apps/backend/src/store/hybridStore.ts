import { randomUUID } from "node:crypto";
import { dbPool, hasDb } from "./db.js";
import { InMemoryStore } from "./inMemory.js";
import type { DisputeRecord, PayoutRecord, SupportRecord, UploadSession } from "../types.js";

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

      // MVP placeholder user linkage until auth integration lands.
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
        returning id, project_id, plan_id, amount_minor, currency, status, reward_type, cancellation_window_hours
      `,
        [supportId],
      );

      if (row.rowCount === 0) {
        await client.query("rollback");
        return null;
      }

      const support = row.rows[0];
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

  async createUploadSession() {
    return memory.createUploadSession();
  }

  async completeUploadSession(uploadSessionId: string, contentHashSha256: string) {
    return memory.completeUploadSession(uploadSessionId, contentHashSha256);
  }

  async getUploadSession(uploadSessionId: string) {
    return memory.getUploadSession(uploadSessionId);
  }

  async getOrCreatePayout(projectId: string) {
    return memory.getOrCreatePayout(projectId);
  }

  async getOrCreateDispute(disputeId: string) {
    return memory.getOrCreateDispute(disputeId);
  }
}

export const store = new HybridStore();
