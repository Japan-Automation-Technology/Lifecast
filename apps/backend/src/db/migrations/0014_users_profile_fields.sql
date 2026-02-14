alter table users
  add column if not exists username text,
  add column if not exists display_name text,
  add column if not exists bio text,
  add column if not exists avatar_url text,
  add column if not exists email text,
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists uq_users_username_ci
  on users (lower(username))
  where username is not null;

create index if not exists idx_users_email_ci
  on users (lower(email))
  where email is not null;

update users
set username = 'user_' || replace(id::text, '-', '')
where username is null;
