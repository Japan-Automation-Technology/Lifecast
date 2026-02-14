import { randomUUID } from "node:crypto";
import { dbPool, hasDb } from "../db.js";
import type { InMemoryStore } from "../inMemory.js";
import type { DisputeRecord, SupportRecord } from "../../types.js";

function normalizeCurrency(value: string | undefined, fallback = "JPY") {
  return (value ?? fallback).toUpperCase().slice(0, 3);
}

export class SupportsService {
  constructor(private readonly memory: InMemoryStore) {}
  async prepareSupport(input: { projectId: string; planId: string; quantity: number; supporterUserId: string }) {
    if (!hasDb() || !dbPool) {
      return this.memory.prepareSupport(input);
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
        [supportId, input.projectId, input.planId, input.supporterUserId, amountMinor, currency, checkoutSessionId],
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
      return this.memory.prepareSupport(input);
    } finally {
      client.release();
    }
  }

  async confirmSupport(supportId: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.confirmSupport(supportId);
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
      return this.memory.confirmSupport(supportId);
    } finally {
      client.release();
    }
  }

  async getSupport(supportId: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.getSupport(supportId);
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
      return this.memory.getSupport(supportId);
    } finally {
      client.release();
    }
  }

  async markSupportSucceededByWebhook(supportId: string) {
    if (!hasDb() || !dbPool) {
      return this.memory.markSupportSucceededByWebhook(supportId);
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
      return this.memory.markSupportSucceededByWebhook(supportId);
    } finally {
      client.release();
    }
  }

  async markSupportRefundedByWebhook(input: { supportId: string; providerRefundId?: string; reasonCode?: string }) {
    if (!hasDb() || !dbPool) {
      const existing = await this.memory.getSupport(input.supportId);
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

}
