create table if not exists analytics_events (
  id bigserial primary key,
  event_id uuid not null unique,
  event_name text not null,
  event_time timestamptz not null,
  user_id uuid,
  anonymous_id text,
  session_id text not null,
  client_platform text not null check (client_platform in ('ios', 'android', 'server')),
  app_version text not null,
  attributes jsonb not null default '{}'::jsonb,
  raw_payload jsonb not null,
  source text not null check (source in ('client', 'server')),
  received_at timestamptz not null default now()
);

create index if not exists idx_analytics_events_name_time on analytics_events(event_name, event_time desc);
create index if not exists idx_analytics_events_project_id on analytics_events((attributes->>'project_id'));

create table if not exists analytics_event_dlq (
  id bigserial primary key,
  event_id text,
  reason_code text not null,
  reason_message text not null,
  raw_payload jsonb not null,
  source text not null check (source in ('client', 'server')),
  received_at timestamptz not null default now()
);

create index if not exists idx_analytics_event_dlq_received on analytics_event_dlq(received_at desc);
