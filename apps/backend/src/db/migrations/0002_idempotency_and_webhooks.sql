create table if not exists api_idempotency_keys (
  id bigserial primary key,
  route_key text not null,
  idempotency_key text not null,
  request_fingerprint text not null,
  response_status int not null,
  response_body jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  unique (route_key, idempotency_key)
);
create index if not exists idx_api_idempotency_expires_at on api_idempotency_keys(expires_at);

create table if not exists processed_webhooks (
  id bigserial primary key,
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz not null default now(),
  process_result text not null check (process_result in ('processed', 'ignored', 'duplicate')),
  unique (provider, provider_event_id)
);
create index if not exists idx_processed_webhooks_processed_at on processed_webhooks(processed_at desc);
