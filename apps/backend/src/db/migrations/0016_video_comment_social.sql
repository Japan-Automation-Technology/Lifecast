create table if not exists video_comment_likes (
  comment_id uuid not null references video_comments(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create index if not exists idx_video_comment_likes_user_created on video_comment_likes(user_id, created_at desc);
