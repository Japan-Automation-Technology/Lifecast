alter table projects
  add column if not exists subtitle text,
  add column if not exists cover_image_url text,
  add column if not exists category text,
  add column if not exists location text,
  add column if not exists description text,
  add column if not exists external_urls jsonb not null default '[]'::jsonb,
  add column if not exists duration_days int;

