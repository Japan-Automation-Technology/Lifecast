-- LifeCast MVP database draft (PostgreSQL 16+)
-- Scope: Journal / Support / Dispute / UploadSession

create extension if not exists pgcrypto;

-- ---------- Enums ----------
create type support_status as enum (
  'prepared',
  'pending_confirmation',
  'succeeded',
  'failed',
  'canceled',
  'refunded'
);

create type project_status as enum (
  'draft',
  'active',
  'stopped',
  'succeeded',
  'failed'
);

create type upload_status as enum (
  'created',
  'uploading',
  'processing',
  'ready',
  'failed'
);

create type dispute_status as enum (
  'open',
  'won',
  'lost',
  'closed'
);

create type journal_entry_type as enum (
  'support_hold',
  'payout_release',
  'refund',
  'dispute_open',
  'dispute_close',
  'loss_booking'
);

create type payout_status as enum (
  'scheduled',
  'executing',
  'settled',
  'blocked'
);

create type moderation_report_status as enum (
  'open',
  'under_review',
  'resolved',
  'dismissed'
);

create type notification_channel as enum (
  'push',
  'in_app',
  'email',
  'ops_pager'
);

-- ---------- Minimal referenced tables ----------
create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists projects (
  id uuid primary key default gen_random_uuid(),
  creator_user_id uuid not null references users(id),
  title text not null,
  status project_status not null default 'draft',
  goal_amount_minor bigint not null check (goal_amount_minor > 0),
  currency char(3) not null,
  deadline_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_projects_creator on projects(creator_user_id);
create index if not exists idx_projects_status_deadline on projects(status, deadline_at);

create table if not exists project_plans (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  reward_summary text not null,
  is_physical_reward boolean not null default true,
  price_minor bigint not null check (price_minor > 0),
  currency char(3) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_plan_price_reasonable check (price_minor between 1 and 100000000)
);
create index if not exists idx_project_plans_project on project_plans(project_id);

-- ---------- Support ----------
create table if not exists support_transactions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id),
  plan_id uuid not null references project_plans(id),
  supporter_user_id uuid not null references users(id),
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null,
  status support_status not null default 'prepared',
  reward_type text not null default 'physical' check (reward_type in ('physical')),
  cancellation_window_hours int not null default 48 check (cancellation_window_hours = 48),
  provider text not null default 'stripe',
  provider_payment_intent_id text unique,
  provider_checkout_session_id text unique,
  prepared_at timestamptz not null default now(),
  confirmed_at timestamptz,
  succeeded_at timestamptz,
  refunded_at timestamptz,
  cancellation_requested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_support_status_times check (
    (status != 'succeeded' or succeeded_at is not null)
    and (status != 'refunded' or refunded_at is not null)
    and (cancellation_requested_at is null or cancellation_requested_at <= created_at + make_interval(hours => cancellation_window_hours))
  )
);
create index if not exists idx_support_project_status on support_transactions(project_id, status);
create index if not exists idx_support_supporter on support_transactions(supporter_user_id, created_at desc);
create index if not exists idx_support_provider_intent on support_transactions(provider_payment_intent_id);

create table if not exists support_status_history (
  id bigserial primary key,
  support_id uuid not null references support_transactions(id) on delete cascade,
  from_status support_status,
  to_status support_status not null,
  reason text,
  actor text not null default 'system',
  occurred_at timestamptz not null default now()
);
create index if not exists idx_support_status_history_support on support_status_history(support_id, occurred_at);

create table if not exists refund_records (
  id uuid primary key default gen_random_uuid(),
  support_id uuid not null unique references support_transactions(id) on delete cascade,
  reason_code text not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null,
  provider_refund_id text unique,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null check (status in ('requested', 'pending', 'succeeded', 'failed'))
);

-- ---------- Dispute ----------
create table if not exists disputes (
  id uuid primary key default gen_random_uuid(),
  support_id uuid not null references support_transactions(id),
  project_id uuid not null references projects(id),
  provider text not null default 'stripe',
  provider_dispute_id text unique,
  status dispute_status not null default 'open',
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null,
  opened_at timestamptz not null default now(),
  acknowledgement_due_at timestamptz not null default (now() + interval '24 hours'),
  triage_due_at timestamptz not null default (now() + interval '72 hours'),
  resolution_due_at timestamptz not null default (now() + interval '10 days'),
  resolved_at timestamptz,
  final_liability text not null check (final_liability in ('unknown', 'creator', 'platform', 'shared')) default 'unknown',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_disputes_status on disputes(status, opened_at desc);
create index if not exists idx_disputes_support on disputes(support_id);

create table if not exists moderation_reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id),
  reporter_user_id uuid not null references users(id),
  reason_code text not null check (reason_code in ('fraud', 'copyright', 'policy_violation', 'no_progress', 'other')),
  details text not null,
  reporter_trust_weight numeric(6,2) not null default 1.00,
  status moderation_report_status not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists idx_reports_project_time on moderation_reports(project_id, created_at desc);
create index if not exists idx_reports_project_weight on moderation_reports(project_id, reporter_trust_weight, created_at desc);
create unique index if not exists uq_reports_project_reporter_day
  on moderation_reports(project_id, reporter_user_id, date_trunc('day', created_at at time zone 'UTC'));

create table if not exists dispute_events (
  id bigserial primary key,
  dispute_id uuid not null references disputes(id) on delete cascade,
  event_type text not null check (
    event_type in (
      'dispute_opened',
      'dispute_resolved_won',
      'dispute_resolved_lost',
      'recovery_attempted',
      'recovery_failed_loss_booked'
    )
  ),
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index if not exists idx_dispute_events_dispute on dispute_events(dispute_id, occurred_at);

-- ---------- Video upload session ----------
create table if not exists video_upload_sessions (
  id uuid primary key default gen_random_uuid(),
  creator_user_id uuid not null references users(id),
  project_id uuid references projects(id),
  status upload_status not null default 'created',
  file_name text not null,
  content_type text not null check (content_type in ('video/mp4', 'video/quicktime')),
  file_size_bytes bigint not null check (file_size_bytes > 0),
  content_hash_sha256 char(64),
  storage_object_key text,
  provider_upload_id text,
  provider_asset_id text,
  error_code text,
  error_message text,
  retry_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  processing_started_at timestamptz,
  processing_deadline_at timestamptz,
  completed_at timestamptz
);
create index if not exists idx_upload_sessions_creator on video_upload_sessions(creator_user_id, created_at desc);
create index if not exists idx_upload_sessions_status on video_upload_sessions(status, updated_at);
create unique index if not exists uq_upload_hash_per_creator
  on video_upload_sessions(creator_user_id, content_hash_sha256)
  where content_hash_sha256 is not null and status in ('processing', 'ready');

create table if not exists project_payouts (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null unique references projects(id) on delete cascade,
  status payout_status not null default 'scheduled',
  execution_start_at timestamptz not null,
  settlement_due_at timestamptz not null,
  settled_at timestamptz,
  rolling_reserve_enabled boolean not null default false check (rolling_reserve_enabled = false),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_payout_schedule check (settlement_due_at >= execution_start_at)
);
create index if not exists idx_project_payouts_status on project_payouts(status, settlement_due_at);

create table if not exists notification_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id),
  channel notification_channel not null,
  event_key text not null,
  payload jsonb not null default '{}'::jsonb,
  send_after timestamptz not null default now(),
  sent_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_notification_events_pending on notification_events(channel, send_after) where sent_at is null and failed_at is null;

-- ---------- Accounting journal ----------
create table if not exists ledger_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  account_type text not null check (account_type in ('asset', 'liability', 'revenue', 'expense', 'equity')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into ledger_accounts (code, name, account_type)
values
  ('CASH_CLEARING', 'Cash Clearing', 'asset'),
  ('SUPPORT_LIABILITY', 'Support Liability', 'liability'),
  ('CREATOR_PAYABLE', 'Creator Payable', 'liability'),
  ('PLATFORM_FEE_REVENUE', 'Platform Fee Revenue', 'revenue'),
  ('PROCESSOR_FEE_EXPENSE', 'Processor Fee Expense', 'expense'),
  ('REFUND_PAYABLE', 'Refund Payable', 'liability'),
  ('DISPUTE_RESERVE', 'Dispute Reserve', 'liability'),
  ('DISPUTE_LOSS_EXPENSE', 'Dispute Loss Expense', 'expense')
on conflict (code) do nothing;

create table if not exists journal_entries (
  id uuid primary key default gen_random_uuid(),
  entry_type journal_entry_type not null,
  project_id uuid references projects(id),
  support_id uuid references support_transactions(id),
  dispute_id uuid references disputes(id),
  external_ref text,
  description text,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_journal_entries_project_occurred on journal_entries(project_id, occurred_at desc);
create index if not exists idx_journal_entries_support on journal_entries(support_id, occurred_at desc);

create table if not exists journal_lines (
  id bigserial primary key,
  journal_entry_id uuid not null references journal_entries(id) on delete cascade,
  ledger_account_id uuid not null references ledger_accounts(id),
  currency char(3) not null,
  debit_minor bigint not null default 0 check (debit_minor >= 0),
  credit_minor bigint not null default 0 check (credit_minor >= 0),
  created_at timestamptz not null default now(),
  constraint chk_one_sided_amount check (
    (debit_minor = 0 and credit_minor > 0) or
    (credit_minor = 0 and debit_minor > 0)
  )
);
create index if not exists idx_journal_lines_entry on journal_lines(journal_entry_id);
create index if not exists idx_journal_lines_account on journal_lines(ledger_account_id, created_at);

-- Balance validation trigger: each journal entry must net to zero per currency.
create or replace function validate_journal_entry_balanced()
returns trigger
language plpgsql
as $$
declare
  unbalanced_count int;
begin
  select count(*)
    into unbalanced_count
  from (
    select currency, sum(debit_minor) as debits, sum(credit_minor) as credits
    from journal_lines
    where journal_entry_id = coalesce(new.journal_entry_id, old.journal_entry_id)
    group by currency
    having sum(debit_minor) <> sum(credit_minor)
  ) q;

  if unbalanced_count > 0 then
    raise exception 'Journal entry % is unbalanced', coalesce(new.journal_entry_id, old.journal_entry_id);
  end if;

  return null;
end;
$$;

drop trigger if exists trg_validate_journal_entry_balanced on journal_lines;
create constraint trigger trg_validate_journal_entry_balanced
after insert or update or delete on journal_lines
deferrable initially deferred
for each row execute function validate_journal_entry_balanced();

-- ---------- Utility ----------
create or replace function touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_touch_projects on projects;
create trigger trg_touch_projects
before update on projects
for each row execute function touch_updated_at();

drop trigger if exists trg_touch_project_plans on project_plans;
create trigger trg_touch_project_plans
before update on project_plans
for each row execute function touch_updated_at();

drop trigger if exists trg_touch_support_transactions on support_transactions;
create trigger trg_touch_support_transactions
before update on support_transactions
for each row execute function touch_updated_at();

drop trigger if exists trg_touch_disputes on disputes;
create trigger trg_touch_disputes
before update on disputes
for each row execute function touch_updated_at();

drop trigger if exists trg_touch_moderation_reports on moderation_reports;
create trigger trg_touch_moderation_reports
before update on moderation_reports
for each row execute function touch_updated_at();

drop trigger if exists trg_touch_video_upload_sessions on video_upload_sessions;
create trigger trg_touch_video_upload_sessions
before update on video_upload_sessions
for each row execute function touch_updated_at();

drop trigger if exists trg_touch_project_payouts on project_payouts;
create trigger trg_touch_project_payouts
before update on project_payouts
for each row execute function touch_updated_at();
