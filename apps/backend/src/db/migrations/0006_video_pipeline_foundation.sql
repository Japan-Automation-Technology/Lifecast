create table if not exists video_assets (
  video_id uuid primary key,
  creator_user_id uuid not null references users(id),
  upload_session_id uuid not null unique references video_upload_sessions(id) on delete cascade,
  status upload_status not null check (status in ('processing', 'ready', 'failed')),
  origin_object_key text,
  duration_ms int,
  width int,
  height int,
  has_audio boolean,
  manifest_url text,
  thumbnail_url text,
  failed_reason text,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_video_assets_creator_created on video_assets(creator_user_id, created_at desc);
create index if not exists idx_video_assets_status_updated on video_assets(status, updated_at desc);

create table if not exists video_renditions (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references video_assets(video_id) on delete cascade,
  profile text not null check (profile in ('360p', '540p', '720p')),
  bitrate_kbps int not null check (bitrate_kbps > 0),
  codec text,
  status text not null check (status in ('pending', 'ready', 'failed')) default 'pending',
  playlist_url text,
  segment_count int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (video_id, profile)
);

create table if not exists video_processing_jobs (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references video_assets(video_id) on delete cascade,
  stage text not null check (stage in ('probe', 'transcode', 'package')),
  status text not null check (status in ('pending', 'running', 'succeeded', 'failed')) default 'pending',
  attempt int not null default 0,
  error_message text,
  run_after timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_video_processing_jobs_pending on video_processing_jobs(status, run_after, created_at);
create unique index if not exists uq_video_job_open_stage
  on video_processing_jobs(video_id, stage)
  where status in ('pending', 'running');
