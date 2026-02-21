alter table projects
  add column if not exists project_image_urls jsonb not null default '[]'::jsonb;

update projects
set project_image_urls = case
  when coalesce(trim(cover_image_url), '') <> '' then jsonb_build_array(cover_image_url)
  else '[]'::jsonb
end
where coalesce(jsonb_array_length(project_image_urls), 0) = 0;
