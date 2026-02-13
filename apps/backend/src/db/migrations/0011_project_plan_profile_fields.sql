alter table project_plans
  add column if not exists description text,
  add column if not exists image_url text;
