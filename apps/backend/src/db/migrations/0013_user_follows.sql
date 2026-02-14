create table if not exists user_follows (
  follower_user_id uuid not null references users(id),
  followed_creator_user_id uuid not null references users(id),
  created_at timestamptz not null default now(),
  primary key (follower_user_id, followed_creator_user_id)
);

create index if not exists idx_user_follows_followed on user_follows(followed_creator_user_id, created_at desc);
