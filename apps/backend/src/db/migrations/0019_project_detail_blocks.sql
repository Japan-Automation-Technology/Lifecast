alter table projects
  add column if not exists project_detail_blocks jsonb not null default '[]'::jsonb;
