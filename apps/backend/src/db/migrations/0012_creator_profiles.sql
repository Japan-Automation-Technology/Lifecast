create table if not exists creator_profiles (
  creator_user_id uuid primary key references users(id) on delete cascade,
  username text not null unique,
  display_name text,
  bio text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_creator_profiles_username on creator_profiles(username);
