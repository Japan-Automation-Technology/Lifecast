create table if not exists video_delete_jobs (
  id uuid primary key default gen_random_uuid(),
  creator_user_id uuid not null references users(id),
  video_id uuid not null,
  provider_upload_id text not null,
  status text not null check (status in ('pending', 'running', 'succeeded', 'failed')) default 'pending',
  attempt int not null default 0,
  error_message text,
  next_run_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists idx_video_delete_jobs_pending
  on video_delete_jobs(status, next_run_at, created_at);

create index if not exists idx_video_delete_jobs_provider_upload
  on video_delete_jobs(provider_upload_id);
