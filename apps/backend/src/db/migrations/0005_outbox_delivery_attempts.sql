create table if not exists outbox_delivery_attempts (
  id bigserial primary key,
  outbox_event_id uuid not null references outbox_events(id) on delete cascade,
  attempt_no int not null,
  transport text not null check (transport in ('webhook', 'noop')),
  status text not null check (status in ('sent', 'failed')),
  http_status int,
  error_message text,
  attempted_at timestamptz not null default now()
);

create unique index if not exists uq_outbox_delivery_attempt
  on outbox_delivery_attempts(outbox_event_id, attempt_no);

create index if not exists idx_outbox_delivery_attempts_attempted_at
  on outbox_delivery_attempts(attempted_at desc);
