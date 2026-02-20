create table if not exists video_likes (
  video_id uuid not null references video_assets(video_id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (video_id, user_id)
);
create index if not exists idx_video_likes_user_created on video_likes(user_id, created_at desc);

create table if not exists video_comments (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references video_assets(video_id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 400),
  created_at timestamptz not null default now()
);
create index if not exists idx_video_comments_video_created on video_comments(video_id, created_at desc);
create index if not exists idx_video_comments_user_created on video_comments(user_id, created_at desc);
