-- ============================================================================
-- 0011 · Pipeline support for Edge Functions
--   pipeline_state  – small persisted blobs (e.g. the URL Bloom filter bitset)
--   pipeline_runs   – idempotency keys so cron jobs never double-send
--   broadcast_notification / queue_morning_routines – set-based fan-out
--   (one INSERT … SELECT instead of N round-trips from the function)
-- All service-role only.
-- ============================================================================

set check_function_bodies = off;

create table public.pipeline_state (
  key        text primary key,
  value      bytea,
  meta       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.pipeline_state enable row level security;

create table public.pipeline_runs (
  key        text primary key,
  result     jsonb,
  created_at timestamptz not null default now()
);
alter table public.pipeline_runs enable row level security;

-- Claims an idempotency key; returns false when it was already claimed.
create or replace function public.claim_pipeline_run(p_key text)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.pipeline_runs (key) values (p_key);
  return true;
exception when unique_violation then
  return false;
end $$;
revoke execute on function public.claim_pipeline_run(text) from public, anon, authenticated;

-- In-app notification (+ push when the category is enabled) for every user
-- active within p_active_days.
create or replace function public.broadcast_notification(
  p_type text, p_title text, p_body text, p_data jsonb, p_category text, p_active_days int default 30
)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare v_count int;
begin
  with targets as (
    select p.id, coalesce((p.notification_settings ->> p_category)::boolean, true) as wants_push
      from public.profiles p
     where not p.is_banned
       and (p.last_active_date >= public.bd_today() - p_active_days or p.created_at >= now() - make_interval(days => p_active_days))
  ), n as (
    insert into public.notifications (user_id, type, title, body, data)
    select id, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb) from targets
    returning user_id
  ), q as (
    insert into public.push_outbox (user_id, title, body, data)
    select id, p_title, p_body, coalesce(p_data, '{}'::jsonb) || jsonb_build_object('type', p_type)
      from targets where wants_push
    returning 1
  )
  select count(*) into v_count from n;
  return v_count;
end $$;
revoke execute on function public.broadcast_notification(text, text, text, jsonb, text, int) from public, anon, authenticated;

-- Morning routine: one personalised notification per user with a plan day today.
create or replace function public.queue_morning_routines()
returns int
language plpgsql security definer
set search_path = ''
as $$
declare v_count int;
begin
  with today as (
    select d.user_id, d.id as day_id, d.title_bn, d.total_items, d.kind
      from public.study_plan_days d
      join public.study_plans sp on sp.id = d.plan_id and sp.status = 'active'
     where d.day_date = public.bd_today()
  ), n as (
    insert into public.notifications (user_id, type, title, body, data)
    select t.user_id, 'routine', 'আজকের রুটিন তৈরি ☀️',
           t.title_bn || ' · ' || t.total_items || 'টি কাজ। চলুন শুরু করি!',
           jsonb_build_object('day_id', t.day_id, 'route', '/plan/day/' || t.day_id)
      from today t
    returning user_id, title, body, data
  ), q as (
    insert into public.push_outbox (user_id, title, body, data)
    select n.user_id, n.title, n.body, n.data || jsonb_build_object('type', 'routine')
      from n join public.profiles p on p.id = n.user_id
     where coalesce((p.notification_settings ->> 'routine')::boolean, true)
    returning 1
  )
  select count(*) into v_count from n;
  return v_count;
end $$;
revoke execute on function public.queue_morning_routines() from public, anon, authenticated;

-- Facts first seen on a given day (for the daily exam generator).
create index if not exists facts_first_seen_idx on public.facts (first_seen_date) where status = 'active';
