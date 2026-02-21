create index if not exists idx_analytics_events_video_event_time
  on analytics_events((attributes->>'video_id'), event_name, event_time desc)
  where attributes ? 'video_id';
