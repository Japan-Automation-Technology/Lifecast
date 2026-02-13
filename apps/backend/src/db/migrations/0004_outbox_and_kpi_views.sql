create table if not exists outbox_events (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null unique,
  topic text not null,
  payload jsonb not null,
  status text not null check (status in ('pending', 'sent', 'failed')) default 'pending',
  attempts int not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_outbox_pending on outbox_events(status, next_attempt_at, created_at);

drop view if exists analytics_funnel_daily;
create view analytics_funnel_daily as
select
  date_trunc('day', event_time at time zone 'UTC')::date as event_date_utc,
  event_name,
  count(*)::bigint as event_count,
  count(distinct coalesce(user_id::text, anonymous_id))::bigint as actor_count
from analytics_events
where event_name in (
  'video_watch_completed',
  'support_button_tapped',
  'plan_selected',
  'checkout_page_reached',
  'payment_succeeded'
)
group by 1, 2;

drop view if exists analytics_kpi_daily;
create view analytics_kpi_daily as
with funnel as (
  select
    event_date_utc,
    sum(case when event_name = 'video_watch_completed' then event_count else 0 end)::numeric as watch_completed_count,
    sum(case when event_name = 'payment_succeeded' then event_count else 0 end)::numeric as payment_succeeded_count
  from analytics_funnel_daily
  group by event_date_utc
),
payment_base as (
  select
    date_trunc('day', event_time at time zone 'UTC')::date as event_date_utc,
    coalesce(user_id::text, anonymous_id) as actor_id,
    case
      when (attributes->>'amount_minor') ~ '^[0-9]+$' then (attributes->>'amount_minor')::numeric
      else null
    end as amount_minor
  from analytics_events
  where event_name = 'payment_succeeded'
),
payment_agg as (
  select
    event_date_utc,
    avg(amount_minor) as average_support_amount_minor,
    count(distinct actor_id)::numeric as supporter_count
  from payment_base
  group by event_date_utc
),
repeat_agg as (
  select
    event_date_utc,
    sum(case when cnt >= 2 then 1 else 0 end)::numeric as repeat_supporter_count,
    count(*)::numeric as total_supporter_count
  from (
    select event_date_utc, actor_id, count(*) as cnt
    from payment_base
    group by event_date_utc, actor_id
  ) t
  group by event_date_utc
)
select
  f.event_date_utc,
  f.watch_completed_count::bigint,
  f.payment_succeeded_count::bigint,
  case
    when f.watch_completed_count = 0 then 0
    else round((f.payment_succeeded_count / f.watch_completed_count) * 100, 4)
  end as support_conversion_rate_pct,
  coalesce(p.average_support_amount_minor, 0)::numeric(18, 2) as average_support_amount_minor,
  case
    when coalesce(r.total_supporter_count, 0) = 0 then 0
    else round((coalesce(r.repeat_supporter_count, 0) / r.total_supporter_count) * 100, 4)
  end as repeat_support_rate_pct
from funnel f
left join payment_agg p on p.event_date_utc = f.event_date_utc
left join repeat_agg r on r.event_date_utc = f.event_date_utc;
