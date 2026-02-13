drop index if exists uq_projects_creator_user;

create unique index if not exists uq_projects_creator_active_draft
  on projects(creator_user_id)
  where status in ('draft', 'active');

