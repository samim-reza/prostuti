-- ============================================================================
-- 0008 · AI semantic cache, usage log, Edge-Function invoker, housekeeping,
--        admin RPCs
-- ============================================================================

-- Functions may reference tables created by later migrations.
set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- Semantic cache for LLM responses.
--   exact hit   → (namespace, prompt_hash)
--   semantic hit → cosine similarity ≥ threshold on the prompt embedding
--   negative    → "nothing useful" answers are cached too (short TTL) so the
--                 same empty lookup never hammers the LLM (cache penetration)
-- Service-role only: no client policies.
-- ---------------------------------------------------------------------------
create table public.ai_semantic_cache (
  id          bigint generated always as identity primary key,
  namespace   text not null,
  prompt_hash text not null,
  embedding   extensions.vector(1536),
  response    jsonb not null,
  is_negative boolean not null default false,
  model       text,
  hits        int not null default 0,
  created_at  timestamptz not null default now(),
  last_hit_at timestamptz,
  expires_at  timestamptz not null,
  unique (namespace, prompt_hash)
);
create index ai_semantic_cache_embedding_hnsw on public.ai_semantic_cache using hnsw (embedding extensions.vector_cosine_ops);
create index ai_semantic_cache_expiry_idx on public.ai_semantic_cache (expires_at);
alter table public.ai_semantic_cache enable row level security;

create or replace function public.semantic_cache_match(
  p_namespace text, p_embedding extensions.vector, p_threshold real default 0.95
)
returns table (id bigint, response jsonb, is_negative boolean, similarity real)
language sql stable security definer
set search_path = ''
as $$
  select c.id, c.response, c.is_negative, (1 - (c.embedding operator(extensions.<=>) p_embedding))::real
    from public.ai_semantic_cache c
   where c.namespace = p_namespace and c.expires_at > now() and c.embedding is not null
     and 1 - (c.embedding operator(extensions.<=>) p_embedding) >= p_threshold
   order by c.embedding operator(extensions.<=>) p_embedding
   limit 1;
$$;
revoke execute on function public.semantic_cache_match(text, extensions.vector, real) from public, anon, authenticated;

create table public.ai_usage_log (
  id                bigint generated always as identity primary key,
  user_id           uuid,
  function_name     text not null,
  model             text,
  prompt_tokens     int,
  completion_tokens int,
  cache             text check (cache in ('exact', 'semantic', 'negative') or cache is null),
  latency_ms        int,
  created_at        timestamptz not null default now()
);
create index ai_usage_log_created_idx on public.ai_usage_log (created_at desc);
alter table public.ai_usage_log enable row level security;
create policy "ai_usage_log: admin reads" on public.ai_usage_log for select to authenticated using (public.is_admin());

-- AI explanations requested from inside the app (per-question, per-user log).
create table public.ai_explanations (
  question_id bigint primary key references public.questions (id) on delete cascade,
  explanation text not null,
  model       text,
  created_at  timestamptz not null default now()
);
alter table public.ai_explanations enable row level security;
create policy "ai_explanations: readable" on public.ai_explanations for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Call an Edge Function asynchronously (pg_net). Secrets live in Vault:
--   project_url  → https://<ref>.supabase.co
--   cron_secret  → shared secret checked by the functions (x-cron-secret)
-- Silently no-ops when the secrets are not configured (e.g. local dev).
-- ---------------------------------------------------------------------------
create or replace function public.invoke_edge_function(p_name text, p_body jsonb default '{}'::jsonb, p_timeout_ms int default 5000)
returns bigint
language plpgsql security definer
set search_path = ''
as $$
declare
  v_url    text;
  v_secret text;
  v_id     bigint;
begin
  select decrypted_secret into v_url    from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'cron_secret' limit 1;
  if v_url is null or v_secret is null then return null; end if;
  select net.http_post(
           url := v_url || '/functions/v1/' || p_name,
           body := coalesce(p_body, '{}'::jsonb),
           headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
           timeout_milliseconds := p_timeout_ms)
    into v_id;
  return v_id;
exception when others then
  -- never break the calling transaction because of a background call
  return null;
end $$;
revoke execute on function public.invoke_edge_function(text, jsonb, int) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Housekeeping (hourly) & nightly rollover (00:05 Bangladesh time)
-- ---------------------------------------------------------------------------
create or replace function public.housekeeping()
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  delete from public.rate_limit_counters where window_start < now() - interval '2 days';
  delete from public.ai_semantic_cache where expires_at < now();
  delete from public.push_outbox where (sent_at is not null and sent_at < now() - interval '7 days')
                                    or created_at < now() - interval '3 days';
  update public.exam_sessions set status = 'expired'
   where status = 'in_progress' and deadline_at < now() - interval '6 hours';
  delete from public.news_articles where fetched_at < now() - interval '120 days';
  delete from net._http_response where created < now() - interval '1 day';
exception when undefined_table then
  null;
end $$;

create or replace function public.nightly_rollover()
returns void
language plpgsql security definer
set search_path = ''
as $$
declare r record;
begin
  -- yesterday's untouched study days become "missed"
  update public.study_plan_days set status = 'missed'
   where day_date < public.bd_today() and status = 'pending' and kind <> 'rest';
  -- plans whose exam date has passed are completed
  update public.study_plans set status = 'completed'
   where status = 'active' and exam_date < public.bd_today();
  -- readiness snapshot for everyone active in the last 30 days
  for r in select id from public.profiles where last_active_date >= public.bd_today() - 30 loop
    perform public.snapshot_readiness(r.id);
  end loop;
  -- broken streaks reset
  update public.profiles set streak_count = 0
   where streak_count > 0 and last_active_date < public.bd_today() - 1;
end $$;

-- ---------------------------------------------------------------------------
-- Admin / moderator RPCs
-- ---------------------------------------------------------------------------
create or replace function public.admin_dashboard()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.is_staff() then raise exception 'forbidden' using errcode = 'PT403'; end if;
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'active_today', (select count(*) from public.profiles where last_active_date = public.bd_today()),
    'posts_today', (select count(*) from public.posts where created_at >= (public.bd_today()::timestamp at time zone 'Asia/Dhaka')),
    'questions', (select count(*) from public.questions where status = 'published'),
    'questions_unverified', (select count(*) from public.questions where review_status = 'unverified' and status <> 'rejected'),
    'questions_flagged', (select count(*) from public.questions where review_status = 'flagged'),
    'facts', (select count(*) from public.facts where status = 'active'),
    'notes_today', (select count(*) from public.daily_notes where note_date = public.bd_today()),
    'daily_exam_today', exists (select 1 from public.daily_exams where exam_date = public.bd_today()),
    'active_plans', (select count(*) from public.study_plans where status = 'active'),
    'open_reports', (select count(*) from public.reports where status = 'open'),
    'ai_calls_today', (select count(*) from public.ai_usage_log where created_at >= (public.bd_today()::timestamp at time zone 'Asia/Dhaka')),
    'ai_cache_hits_today', (select count(*) from public.ai_usage_log where cache is not null and created_at >= (public.bd_today()::timestamp at time zone 'Asia/Dhaka')));
end $$;

create or replace function public.admin_list_questions(
  p_review text default 'unverified', p_subject smallint default null, p_limit int default 20, p_after_id bigint default null
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.is_staff() then raise exception 'forbidden' using errcode = 'PT403'; end if;
  return (select coalesce(jsonb_agg(public.question_public_json(q) || jsonb_build_object(
             'correct_index', q.correct_index, 'explanation', q.explanation, 'status', q.status,
             'review_status', q.review_status, 'exam_tags', q.exam_tags, 'fact_id', q.fact_id,
             'created_at', q.created_at) order by q.id desc), '[]'::jsonb)
            from (select * from public.questions
                   where (p_review is null or review_status = p_review)
                     and status <> 'rejected'
                     and (p_subject is null or subject_id = p_subject)
                     and (p_after_id is null or id < p_after_id)
                   order by id desc limit least(coalesce(p_limit, 20), 100)) q);
end $$;

create or replace function public.admin_update_question(p_id bigint, p_patch jsonb)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_staff() then raise exception 'forbidden' using errcode = 'PT403'; end if;
  update public.questions set
    stem          = coalesce(p_patch ->> 'stem', stem),
    options       = coalesce(p_patch -> 'options', options),
    correct_index = coalesce((p_patch ->> 'correct_index')::smallint, correct_index),
    explanation   = coalesce(p_patch ->> 'explanation', explanation),
    topic_id      = coalesce((p_patch ->> 'topic_id')::int, topic_id),
    difficulty    = coalesce((p_patch ->> 'difficulty')::smallint, difficulty),
    status        = coalesce(p_patch ->> 'status', status),
    review_status = coalesce(p_patch ->> 'review_status', review_status)
  where id = p_id;
end $$;

create or replace function public.admin_list_reports(p_status text default 'open', p_limit int default 30, p_before timestamptz default null)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.is_staff() then raise exception 'forbidden' using errcode = 'PT403'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
             'id', r.id, 'target_type', r.target_type, 'target_id', r.target_id, 'reason', r.reason,
             'details', r.details, 'status', r.status, 'created_at', r.created_at,
             'reporter', jsonb_build_object('id', p.id, 'username', p.username, 'full_name', p.full_name),
             'preview', case r.target_type
                          when 'post' then (select left(body, 200) from public.posts where id::text = r.target_id)
                          when 'comment' then (select left(body, 200) from public.comments where id::text = r.target_id)
                          when 'question' then (select left(stem, 200) from public.questions where id::text = r.target_id)
                          when 'user' then (select coalesce(full_name, username::text) from public.profiles where id::text = r.target_id)
                        end) order by r.created_at desc), '[]'::jsonb)
            from (select * from public.reports
                   where (p_status is null or status = p_status) and (p_before is null or created_at < p_before)
                   order by created_at desc limit least(coalesce(p_limit, 30), 100)) r
            join public.profiles p on p.id = r.reporter_id);
end $$;

create or replace function public.admin_resolve_report(p_report bigint, p_action text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v public.reports;
begin
  if not public.is_staff() then raise exception 'forbidden' using errcode = 'PT403'; end if;
  select * into v from public.reports where id = p_report;
  if not found then raise exception 'report_not_found' using errcode = 'PT404'; end if;
  if p_action = 'hide' then
    if v.target_type = 'post' then update public.posts set is_hidden = true where id::text = v.target_id;
    elsif v.target_type = 'comment' then update public.comments set is_hidden = true where id::text = v.target_id;
    elsif v.target_type = 'question' then update public.questions set status = 'rejected' where id::text = v.target_id;
    elsif v.target_type = 'user' then update public.profiles set is_banned = true where id::text = v.target_id;
    end if;
  elsif p_action = 'restore' then
    if v.target_type = 'post' then update public.posts set is_hidden = false where id::text = v.target_id;
    elsif v.target_type = 'comment' then update public.comments set is_hidden = false where id::text = v.target_id;
    end if;
  end if;
  update public.reports
     set status = case when p_action = 'dismiss' then 'dismissed' else 'actioned' end,
         reviewed_by = auth.uid(), reviewed_at = now()
   where target_type = v.target_type and target_id = v.target_id and status = 'open';
end $$;

create or replace function public.admin_set_role(p_user uuid, p_role public.user_role)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = 'PT403'; end if;
  update public.profiles set role = p_role where id = p_user;
end $$;

-- Re-run a pipeline stage from the admin screen.
create or replace function public.admin_run_pipeline(p_stage text)
returns bigint
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = 'PT403'; end if;
  if p_stage not in ('ingest-news', 'generate-daily-notes', 'generate-daily-exam', 'dispatch-notifications') then
    raise exception 'invalid_stage';
  end if;
  return public.invoke_edge_function(p_stage, jsonb_build_object('mode', 'manual'), 150000);
end $$;
