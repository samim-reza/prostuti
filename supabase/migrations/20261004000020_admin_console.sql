-- ============================================================================
-- 0020 · Web admin console (admin/)
--
-- The console is a static SPA that only holds the public anon key plus the
-- signed-in staff member's JWT. Every rule lives here:
--   • security-definer RPCs with `set search_path = ''`
--   • an is_admin() / is_staff() check that raises PT403
--   • input validation (PT400), not-found (PT404), conflicts (PT409)
--   • keyset pagination for every list
--   • every mutation is written to admin_audit_log
-- Existing RPCs (admin_grant_addon, admin_set_role, admin_resolve_report,
-- admin_run_pipeline, admin_list_reports) are reused: the console calls them
-- through thin audited wrappers so their contracts stay untouched.
--
-- Roles: moderators may use the moderation and question-review RPCs (staff);
-- everything else is admin-only.
-- ============================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- Audit log (append-only, admin-readable)
-- ---------------------------------------------------------------------------
create table if not exists public.admin_audit_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid references public.profiles (id) on delete set null,
  action      text not null check (action ~ '^[a-z_]+\.[a-z_]+$'),
  target_type text,
  target_id   text,
  details     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists admin_audit_log_created_idx on public.admin_audit_log (created_at desc, id desc);
create index if not exists admin_audit_log_actor_idx   on public.admin_audit_log (actor_id, id desc);
create index if not exists admin_audit_log_target_idx  on public.admin_audit_log (target_type, target_id, id desc);
create index if not exists admin_audit_log_action_idx  on public.admin_audit_log (action, id desc);
alter table public.admin_audit_log enable row level security;
drop policy if exists "admin_audit_log: admin reads" on public.admin_audit_log;
create policy "admin_audit_log: admin reads" on public.admin_audit_log
  for select to authenticated using (public.is_admin());
revoke insert, update, delete, truncate on public.admin_audit_log from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Supporting indexes (keyset cursors, FK lookups, dashboard counters)
-- ---------------------------------------------------------------------------
create index if not exists profiles_created_idx           on public.profiles (created_at desc, id desc);
create index if not exists profiles_target_schedule_idx   on public.profiles (target_schedule_id) where target_schedule_id is not null;
create index if not exists question_attempts_question_idx on public.question_attempts (question_id, selected_index);
create index if not exists reports_target_idx             on public.reports (target_type, target_id, status);
create index if not exists exam_sessions_submitted_idx    on public.exam_sessions (submitted_at desc) where status = 'submitted';
create index if not exists study_plans_schedule_idx       on public.study_plans (schedule_id) where status = 'active';
create index if not exists daily_notes_date_idx           on public.daily_notes (note_date desc, importance desc, id);
create index if not exists news_articles_source_idx       on public.news_articles (source_id, fetched_at desc);
create index if not exists user_entitlements_addon_idx    on public.user_entitlements (addon_code, expires_at);

-- ---------------------------------------------------------------------------
-- Client error reports (table from 0019): admins may read them. 0019 revokes
-- every table privilege, so SELECT is granted back and RLS limits it to admins.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.client_errors') is not null then
    execute 'drop policy if exists "client_errors: admin reads" on public.client_errors';
    execute 'create policy "client_errors: admin reads" on public.client_errors
               for select to authenticated using (public.is_admin())';
    execute 'grant select on public.client_errors to authenticated';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- AI price list for cost estimates (USD per 1M tokens). Private, editable in
-- the console under App config.
-- ---------------------------------------------------------------------------
insert into public.app_config (key, value, description, is_public) values
  ('ai_pricing',
   '{"usd_to_bdt": 122, "models": {"gpt-5.4-mini": {"input": 0.25, "output": 2.0}, "text-embedding-3-small": {"input": 0.02, "output": 0}}}'::jsonb,
   'USD per 1M tokens by model, used for AI cost estimates in the admin console', false)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Internal helpers (not callable by clients)
-- ---------------------------------------------------------------------------
create or replace function public._console_assert_staff()
returns uuid
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.is_staff() then
    raise exception 'forbidden' using errcode = 'PT403';
  end if;
  return auth.uid();
end $$;

create or replace function public._console_assert_admin()
returns uuid
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = 'PT403';
  end if;
  return auth.uid();
end $$;

create or replace function public._admin_audit(
  p_action text, p_target_type text, p_target_id text, p_details jsonb default '{}'::jsonb
)
returns void
language sql security definer
set search_path = ''
as $$
  insert into public.admin_audit_log (actor_id, action, target_type, target_id, details)
  values (auth.uid(), p_action, p_target_type, p_target_id, coalesce(p_details, '{}'::jsonb));
$$;

-- {key: {from, to}} for every top-level key whose value changed.
create or replace function public._jsonb_diff(p_old jsonb, p_new jsonb)
returns jsonb
language sql immutable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(k.key, jsonb_build_object('from', p_old -> k.key, 'to', p_new -> k.key)), '{}'::jsonb)
    from (select jsonb_object_keys(coalesce(p_old, '{}'::jsonb) || coalesce(p_new, '{}'::jsonb)) as key) k
   where (p_old -> k.key) is distinct from (p_new -> k.key);
$$;

-- '%term%' with LIKE metacharacters escaped.
create or replace function public._like_pattern(p text)
returns text
language sql immutable
set search_path = ''
as $$
  select '%' || replace(replace(replace(p, '\', '\\'), '%', '\%'), '_', '\_') || '%';
$$;

create or replace function public._is_http_url(p text)
returns boolean
language sql immutable
set search_path = ''
as $$
  select p ~* '^https?://[^\s/$.?#][^\s]*$' and char_length(p) <= 1000;
$$;

-- Estimated USD cost of a token count under the configured price list.
create or replace function public._ai_cost(p_model text, p_in numeric, p_out numeric, p_pricing jsonb)
returns numeric
language sql immutable
set search_path = ''
as $$
  select coalesce(p_in, 0) * coalesce((p_pricing -> 'models' -> p_model ->> 'input')::numeric, 0) / 1000000
       + coalesce(p_out, 0) * coalesce((p_pricing -> 'models' -> p_model ->> 'output')::numeric, 0) / 1000000;
$$;

-- Validates one question payload (seed format or console format).
-- Returns an error code, or null when the payload is valid. Subject and
-- topic existence are checked by the callers (they need the ids anyway).
create or replace function public._admin_question_error(p jsonb)
returns text
language plpgsql immutable
set search_path = ''
as $$
declare
  v_opts jsonb;
  v_n    int;
  v_ci   jsonb;
  v_tags jsonb;
  v_stem text;
  v_year text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return 'not_an_object'; end if;
  v_stem := btrim(coalesce(p ->> 'stem', ''));
  if char_length(v_stem) < 3 or char_length(v_stem) > 2000 then return 'stem_length'; end if;

  v_opts := p -> 'options';
  if v_opts is null or jsonb_typeof(v_opts) <> 'array' then return 'options_not_array'; end if;
  v_n := jsonb_array_length(v_opts);
  if v_n < 2 or v_n > 5 then return 'options_count'; end if;
  if exists (select 1 from jsonb_array_elements(v_opts) o
              where jsonb_typeof(o) <> 'string' or btrim(o #>> '{}') = '' or char_length(o #>> '{}') > 500) then
    return 'option_invalid';
  end if;
  if (select count(distinct btrim(o #>> '{}')) from jsonb_array_elements(v_opts) o) <> v_n then
    return 'options_not_distinct';
  end if;

  v_ci := p -> 'correct_index';
  if v_ci is null or jsonb_typeof(v_ci) <> 'number' or (v_ci #>> '{}') !~ '^\d{1,2}$'
     or (v_ci #>> '{}')::int >= v_n then
    return 'correct_index_range';
  end if;

  if p ? 'difficulty' and jsonb_typeof(p -> 'difficulty') <> 'null'
     and coalesce(p ->> 'difficulty', '') !~ '^[1-5]$' then
    return 'difficulty_range';
  end if;
  if coalesce(p ->> 'language', 'bn') not in ('bn', 'en') then return 'language_invalid'; end if;

  v_tags := p -> 'exam_tags';
  if v_tags is not null and jsonb_typeof(v_tags) <> 'null' then
    if jsonb_typeof(v_tags) <> 'array' then return 'exam_tags_not_array'; end if;
    if exists (select 1 from jsonb_array_elements(v_tags) t
                where jsonb_typeof(t) <> 'string' or (t #>> '{}') not in ('bcs', 'bank', 'govt')) then
      return 'exam_tag_invalid';
    end if;
  end if;

  if char_length(coalesce(p ->> 'explanation', '')) > 4000 then return 'explanation_length'; end if;
  if coalesce(p ->> 'source_kind', 'curated') not in
       ('previous_exam', 'book', 'newspaper', 'website', 'ai_generated', 'curated') then
    return 'source_kind_invalid';
  end if;
  if char_length(coalesce(p ->> 'source_name', '')) > 200 then return 'source_name_length'; end if;
  if char_length(coalesce(p ->> 'source_ref', '')) > 300 then return 'source_ref_length'; end if;
  if nullif(btrim(coalesce(p ->> 'source_url', '')), '') is not null
     and not public._is_http_url(btrim(p ->> 'source_url')) then
    return 'source_url_invalid';
  end if;
  v_year := nullif(coalesce(p ->> 'year', p ->> 'source_year'), '');
  if v_year is not null and (v_year !~ '^\d{4}$' or v_year::int not between 1950 and 2100) then
    return 'year_invalid';
  end if;
  return null;
end $$;

-- Ids of one page of questions matching the console filters (newest first).
--   p_search matches the stem (trigram index); "#123" / "123" also matches the id.
create or replace function public._admin_question_page(
  p_subject smallint, p_topic int, p_tag text, p_status text, p_review text,
  p_source_kind text, p_source_id bigint, p_search text, p_limit int, p_after_id bigint
)
returns table (id bigint)
language plpgsql stable
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if p_search ~ '^#?\d{1,18}$' then
    v_id := ltrim(p_search, '#')::bigint;
  end if;
  return query
  select q.id
    from public.questions q
   where (p_subject is null or q.subject_id = p_subject)
     and (p_topic is null or q.topic_id = p_topic)
     and (p_tag is null
          or (p_tag = 'none' and cardinality(q.exam_tags) = 0)
          or (p_tag <> 'none' and q.exam_tags @> array[p_tag]))
     and (p_status is null or q.status = p_status)
     and (p_review is null or q.review_status = p_review)
     and (p_source_id is null or q.source_id = p_source_id)
     and (p_source_kind is null
          or q.source_id in (select s.id from public.sources s where s.kind::text = p_source_kind))
     and (p_search is null or q.id = v_id or q.stem ilike public._like_pattern(p_search))
     and (p_after_id is null or q.id < p_after_id)
   order by q.id desc
   limit p_limit;
end $$;

-- Shared filter validation for the question list / export RPCs.
create or replace function public._admin_question_filters_check(
  p_tag text, p_status text, p_review text, p_source_kind text, p_search text
)
returns void
language plpgsql immutable
set search_path = ''
as $$
begin
  if p_tag is not null and p_tag not in ('bcs', 'bank', 'govt', 'none') then
    raise exception 'invalid_tag' using errcode = 'PT400';
  end if;
  if p_status is not null and p_status not in ('draft', 'published', 'rejected', 'archived') then
    raise exception 'invalid_status' using errcode = 'PT400';
  end if;
  if p_review is not null and p_review not in ('unverified', 'verified', 'flagged') then
    raise exception 'invalid_review_status' using errcode = 'PT400';
  end if;
  if p_source_kind is not null and p_source_kind not in
       ('previous_exam', 'book', 'newspaper', 'website', 'ai_generated', 'curated') then
    raise exception 'invalid_source_kind' using errcode = 'PT400';
  end if;
  if p_search is not null and char_length(p_search) > 200 then
    raise exception 'search_too_long' using errcode = 'PT400';
  end if;
end $$;

-- Users a broadcast reaches. Banned users never receive anything.
create or replace function public._admin_broadcast_targets(
  p_exam text, p_district text, p_locale text, p_active_days int
)
returns table (id uuid, locale text, wants_push boolean)
language sql stable
set search_path = ''
as $$
  select p.id, p.locale, coalesce((p.notification_settings ->> 'announcements')::boolean, true)
    from public.profiles p
   where not p.is_banned
     and (p_exam is null or p.target_exams @> array[p_exam])
     and (p_district is null or p.district = p_district)
     and (p_locale is null or p.locale = p_locale)
     and (p_active_days is null
          or p.last_active_date >= public.bd_today() - p_active_days
          or p.created_at >= now() - make_interval(days => p_active_days));
$$;

-- Validation for well-known remote-config keys. Null = valid.
create or replace function public._admin_config_error(p_key text, p_value jsonb)
returns text
language plpgsql stable
set search_path = ''
as $$
declare v_model record;
begin
  case p_key
    when 'min_app_version', 'latest_app_version' then
      if jsonb_typeof(p_value) <> 'string' or (p_value #>> '{}') !~ '^\d+\.\d+\.\d+(\+\d+)?$' then
        return 'expected a version string like "1.2.3"';
      end if;
    when 'morning_routine_time', 'notes_ready_time' then
      if jsonb_typeof(p_value) <> 'string' or (p_value #>> '{}') !~ '^([01]\d|2[0-3]):[0-5]\d$' then
        return 'expected a time string like "06:30"';
      end if;
    when 'default_schedule_id' then
      if jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}') !~ '^\d{1,12}$'
         or not exists (select 1 from public.exam_schedules where id = (p_value #>> '{}')::bigint) then
        return 'expected the id of an existing exam schedule';
      end if;
    when 'ads' then
      if jsonb_typeof(p_value) <> 'object' then return 'expected an object'; end if;
      if p_value ? 'rewarded_enabled' and jsonb_typeof(p_value -> 'rewarded_enabled') <> 'boolean' then
        return 'rewarded_enabled must be true or false';
      end if;
      if exists (select 1 from jsonb_each(p_value) e where e.key like '%_unit' and jsonb_typeof(e.value) <> 'string') then
        return 'ad unit ids must be strings';
      end if;
    when 'maintenance' then
      if jsonb_typeof(p_value) <> 'object' or jsonb_typeof(p_value -> 'enabled') is distinct from 'boolean' then
        return 'expected an object with "enabled": true/false';
      end if;
    when 'placement' then
      if jsonb_typeof(p_value) <> 'object'
         or coalesce(p_value ->> 'per_group', '') !~ '^\d{1,2}$'
         or (p_value ->> 'per_group')::int not between 1 and 50
         or coalesce(p_value ->> 'duration_minutes', '') !~ '^\d{1,3}$'
         or (p_value ->> 'duration_minutes')::int not between 5 and 180 then
        return 'expected {"per_group": 1-50, "duration_minutes": 5-180}';
      end if;
    when 'support' then
      if jsonb_typeof(p_value) <> 'object' then return 'expected an object'; end if;
    when 'ai_pricing' then
      if jsonb_typeof(p_value) <> 'object' or jsonb_typeof(p_value -> 'models') is distinct from 'object' then
        return 'expected {"usd_to_bdt": n, "models": {"<model>": {"input": n, "output": n}}}';
      end if;
      if p_value ? 'usd_to_bdt' and jsonb_typeof(p_value -> 'usd_to_bdt') <> 'number' then
        return 'usd_to_bdt must be a number';
      end if;
      for v_model in select e.key, e.value from jsonb_each(p_value -> 'models') e loop
        if jsonb_typeof(v_model.value) <> 'object'
           or jsonb_typeof(v_model.value -> 'input') is distinct from 'number'
           or jsonb_typeof(v_model.value -> 'output') is distinct from 'number'
           or (v_model.value ->> 'input')::numeric < 0 or (v_model.value ->> 'output')::numeric < 0 then
          return 'model "' || v_model.key || '" needs non-negative numeric input/output prices';
        end if;
      end loop;
    else
      null;
  end case;
  return null;
end $$;

revoke execute on function public._console_assert_staff() from public, anon, authenticated;
revoke execute on function public._console_assert_admin() from public, anon, authenticated;
revoke execute on function public._admin_audit(text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public._jsonb_diff(jsonb, jsonb) from public, anon, authenticated;
revoke execute on function public._like_pattern(text) from public, anon, authenticated;
revoke execute on function public._is_http_url(text) from public, anon, authenticated;
revoke execute on function public._ai_cost(text, numeric, numeric, jsonb) from public, anon, authenticated;
revoke execute on function public._admin_question_error(jsonb) from public, anon, authenticated;
revoke execute on function public._admin_question_page(smallint, int, text, text, text, text, bigint, text, int, bigint) from public, anon, authenticated;
revoke execute on function public._admin_question_filters_check(text, text, text, text, text) from public, anon, authenticated;
revoke execute on function public._admin_broadcast_targets(text, text, text, int) from public, anon, authenticated;
revoke execute on function public._admin_config_error(text, jsonb) from public, anon, authenticated;

-- ===========================================================================
-- Dashboard
-- ===========================================================================
create or replace function public.admin_console_stats()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_today   date := public.bd_today();
  v_start   timestamptz := public.bd_today()::timestamp at time zone 'Asia/Dhaka';
  v_pricing jsonb := coalesce((select value from public.app_config where key = 'ai_pricing'), '{}'::jsonb);
  v_errors  jsonb;
  v_cron    jsonb := '[]'::jsonb;
begin
  perform public._console_assert_admin();

  if to_regclass('public.client_errors') is not null then
    -- 0019 merges repeats within an hour into one row (occurrences, last_seen_at),
    -- so a row seen in the window was created at most one hour before it.
    select jsonb_build_object('events', coalesce(sum(occurrences), 0), 'groups', count(distinct fingerprint),
                              'fatal', coalesce(sum(occurrences) filter (where fatal), 0),
                              'users', count(distinct user_id))
      into v_errors
      from public.client_errors
     where created_at >= now() - interval '25 hours'
       and last_seen_at >= now() - interval '24 hours';
  end if;

  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'job', j.jobname, 'schedule', j.schedule, 'active', j.active, 'status', d.status,
             'started_at', d.start_time, 'ended_at', d.end_time, 'message', left(d.return_message, 300))
             order by j.jobname), '[]'::jsonb)
      into v_cron
      from cron.job j
      left join (select distinct on (r.jobid) r.jobid, r.status, r.start_time, r.end_time, r.return_message
                   from cron.job_run_details r
                  where r.start_time >= now() - interval '3 days'
                  order by r.jobid, r.start_time desc) d on d.jobid = j.jobid
     where j.jobname like 'prostuti-%';
  exception when others then
    v_cron := '[]'::jsonb;
  end;

  return jsonb_build_object(
    'generated_at', now(),
    'bd_today', v_today,
    'users', (select jsonb_build_object(
                'total', count(*),
                'new_7d', count(*) filter (where created_at >= now() - interval '7 days'),
                'new_today', count(*) filter (where created_at >= v_start),
                'active_today', count(*) filter (where last_active_date = v_today),
                'active_7d', count(*) filter (where last_active_date >= v_today - 6),
                'banned', count(*) filter (where is_banned),
                'staff', count(*) filter (where role <> 'user'))
                from public.profiles),
    'exams_today', (select jsonb_build_object(
                      'submitted', count(*),
                      'by_kind', coalesce((select jsonb_object_agg(k.kind, k.n) from (
                                   select kind, count(*) n from public.exam_sessions
                                    where status = 'submitted' and submitted_at >= v_start group by kind) k), '{}'::jsonb))
                      from public.exam_sessions
                     where status = 'submitted' and submitted_at >= v_start),
    'questions', (select coalesce(jsonb_agg(jsonb_build_object('status', x.status, 'review_status', x.review_status,
                                                               'count', x.n) order by x.status, x.review_status), '[]'::jsonb)
                    from (select status, review_status, count(*) n from public.questions group by 1, 2) x),
    'reports', (select jsonb_build_object('open', coalesce(sum(t.n), 0),
                                          'by_type', coalesce(jsonb_object_agg(t.target_type, t.n), '{}'::jsonb))
                  from (select target_type, count(*) n from public.reports where status = 'open' group by 1) t),
    'today', jsonb_build_object(
      'notes', (select jsonb_build_object(
                  'published', count(*) filter (where status = 'published'),
                  'draft', count(*) filter (where status = 'draft'),
                  'archived', count(*) filter (where status = 'archived'),
                  'missing_en', count(*) filter (where status = 'published' and title_en is null))
                  from public.daily_notes where note_date = v_today),
      'daily_exam', (select jsonb_build_object(
                       'id', e.id, 'status', e.status, 'title_bn', e.title_bn,
                       'question_count', cardinality(e.question_ids),
                       'submissions', (select count(*) from public.exam_sessions s
                                        where s.daily_exam_id = e.id and s.status = 'submitted'))
                       from public.daily_exams e where e.exam_date = v_today)),
    'ai_7d', (select jsonb_build_object(
                'calls', coalesce(sum(m.calls), 0),
                'cache_hits', coalesce(sum(m.hits), 0),
                'prompt_tokens', coalesce(sum(m.pt), 0),
                'completion_tokens', coalesce(sum(m.ct), 0),
                'cost_usd', round(coalesce(sum(public._ai_cost(m.model, m.pt, m.ct, v_pricing)), 0), 4),
                'usd_to_bdt', v_pricing -> 'usd_to_bdt')
                from (select model, count(*) calls, count(*) filter (where cache is not null) hits,
                             sum(prompt_tokens) pt, sum(completion_tokens) ct
                        from public.ai_usage_log
                       where created_at >= now() - interval '7 days'
                       group by model) m),
    'series', (with days as (select (v_today - g)::date as d from generate_series(0, 13) g),
                    su as (select (created_at at time zone 'Asia/Dhaka')::date as d, count(*) n
                             from public.profiles where created_at >= v_start - interval '13 days' group by 1),
                    ex as (select (submitted_at at time zone 'Asia/Dhaka')::date as d, count(*) n
                             from public.exam_sessions
                            where status = 'submitted' and submitted_at >= v_start - interval '13 days' group by 1),
                    ai as (select (created_at at time zone 'Asia/Dhaka')::date as d, model, count(*) calls,
                                  sum(prompt_tokens) pt, sum(completion_tokens) ct
                             from public.ai_usage_log where created_at >= v_start - interval '13 days' group by 1, 2),
                    aid as (select ai.d, sum(ai.calls) calls, sum(public._ai_cost(ai.model, ai.pt, ai.ct, v_pricing)) cost
                              from ai group by ai.d)
               select jsonb_agg(jsonb_build_object(
                        'day', days.d, 'signups', coalesce(su.n, 0), 'exams', coalesce(ex.n, 0),
                        'ai_calls', coalesce(aid.calls, 0), 'ai_cost_usd', round(coalesce(aid.cost, 0), 4))
                        order by days.d)
                 from days left join su using (d) left join ex using (d) left join aid using (d)),
    'client_errors_24h', v_errors,
    'pipeline', jsonb_build_object(
      'cron', v_cron,
      'recent_runs', (select coalesce(jsonb_agg(jsonb_build_object('key', r.key, 'created_at', r.created_at)
                                                order by r.created_at desc), '[]'::jsonb)
                        from (select key, created_at from public.pipeline_runs order by created_at desc limit 10) r),
      'news_sources', (select jsonb_build_object('total', count(*), 'enabled', count(*) filter (where enabled),
                                                 'failing', count(*) filter (where fail_count > 0),
                                                 'last_fetched_at', max(last_fetched_at))
                         from public.news_sources),
      'unprocessed_articles', (select count(*) from public.news_articles where processed_at is null),
      'pending_replans', (select count(*) from public.plan_replan_jobs where processed_at is null),
      'pending_push', (select count(*) from public.push_outbox where sent_at is null)));
end $$;

-- AI usage aggregates over the last p_days days (Bangladesh calendar days).
create or replace function public.admin_ai_usage_summary(p_days int default 7)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_days    int := coalesce(p_days, 7);
  v_from    timestamptz;
  v_pricing jsonb := coalesce((select value from public.app_config where key = 'ai_pricing'), '{}'::jsonb);
begin
  perform public._console_assert_admin();
  if v_days not between 1 and 90 then raise exception 'invalid_days' using errcode = 'PT400'; end if;
  v_from := (public.bd_today() - (v_days - 1))::timestamp at time zone 'Asia/Dhaka';

  return (
    with base as (
      select (created_at at time zone 'Asia/Dhaka')::date as d, function_name, model,
             count(*) calls, count(*) filter (where cache is not null) hits,
             coalesce(sum(prompt_tokens), 0) pt, coalesce(sum(completion_tokens), 0) ct,
             avg(latency_ms) lat
        from public.ai_usage_log
       where created_at >= v_from
       group by 1, 2, 3
    )
    select jsonb_build_object(
      'from', v_from,
      'pricing', v_pricing,
      'by_day', (select coalesce(jsonb_agg(jsonb_build_object(
                   'day', x.d, 'calls', x.calls, 'cache_hits', x.hits, 'prompt_tokens', x.pt,
                   'completion_tokens', x.ct, 'cost_usd', round(x.cost, 4)) order by x.d), '[]'::jsonb)
                   from (select d, sum(calls) calls, sum(hits) hits, sum(pt) pt, sum(ct) ct,
                                sum(public._ai_cost(model, pt, ct, v_pricing)) cost
                           from base group by d) x),
      'by_function', (select coalesce(jsonb_agg(jsonb_build_object(
                        'function_name', x.function_name, 'model', x.model, 'calls', x.calls,
                        'cache_hits', x.hits, 'prompt_tokens', x.pt, 'completion_tokens', x.ct,
                        'avg_latency_ms', round(x.lat), 'cost_usd', round(x.cost, 4))
                        order by x.cost desc, x.calls desc), '[]'::jsonb)
                        from (select function_name, model, sum(calls) calls, sum(hits) hits, sum(pt) pt, sum(ct) ct,
                                     sum(lat * calls) / nullif(sum(calls), 0) lat,
                                     sum(public._ai_cost(model, pt, ct, v_pricing)) cost
                                from base group by 1, 2) x),
      'unpriced_models', (select coalesce(jsonb_agg(distinct model), '[]'::jsonb) from base
                           where model is not null and (pt > 0 or ct > 0)
                             and not coalesce((v_pricing -> 'models') ? model, false)))
  );
end $$;

-- ===========================================================================
-- Users (admin only: e-mail addresses come from auth.users)
-- ===========================================================================
create or replace function public.admin_list_users(
  p_search text default null, p_role text default null, p_banned boolean default null,
  p_limit int default 25, p_after_created timestamptz default null, p_after_id uuid default null
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_q     text := nullif(btrim(p_search), '');
  v_limit int := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_uuid  uuid;
  v_pat   text;
begin
  perform public._console_assert_admin();
  if p_role is not null and p_role not in ('user', 'moderator', 'admin') then
    raise exception 'invalid_role' using errcode = 'PT400';
  end if;
  if v_q is not null and char_length(v_q) > 120 then
    raise exception 'search_too_long' using errcode = 'PT400';
  end if;
  if (p_after_created is null) <> (p_after_id is null) then
    raise exception 'invalid_cursor' using errcode = 'PT400';
  end if;
  if v_q ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_uuid := v_q::uuid;
  end if;
  v_pat := public._like_pattern(v_q);

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', r.id, 'username', r.username, 'full_name', r.full_name, 'email', r.email,
             'avatar_url', r.avatar_url, 'role', r.role, 'is_banned', r.is_banned, 'district', r.district,
             'target_exams', r.target_exams, 'onboarding_step', r.onboarding_step,
             'last_active_date', r.last_active_date, 'streak_count', r.streak_count,
             'exams_taken', r.exams_taken, 'locale', r.locale, 'created_at', r.created_at,
             'last_sign_in_at', r.last_sign_in_at)
             order by r.created_at desc, r.id desc), '[]'::jsonb)
      from (select p.*, u.email::text as email, u.last_sign_in_at
              from public.profiles p
              join auth.users u on u.id = p.id
             where (p_role is null or p.role::text = p_role)
               and (p_banned is null or p.is_banned = p_banned)
               and (v_q is null
                    or (v_uuid is not null and p.id = v_uuid)
                    or (v_uuid is null and v_q like '%@%' and u.email ilike v_pat)
                    or (v_uuid is null and v_q not like '%@%'
                        and (p.username::text ilike v_pat or p.full_name ilike v_pat or u.email ilike v_pat)))
               and (p_after_created is null or (p.created_at, p.id) < (p_after_created, p_after_id))
             order by p.created_at desc, p.id desc
             limit v_limit) r);
end $$;

create or replace function public.admin_get_user(p_user uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_p public.profiles;
  v_u record;
begin
  perform public._console_assert_admin();
  select * into v_p from public.profiles where id = p_user;
  if not found then raise exception 'user_not_found' using errcode = 'PT404'; end if;
  select u.email::text as email, u.created_at, u.last_sign_in_at, u.email_confirmed_at, u.banned_until,
         u.raw_app_meta_data ->> 'provider' as provider
    into v_u from auth.users u where u.id = p_user;

  return jsonb_build_object(
    'profile', to_jsonb(v_p),
    'auth', jsonb_build_object('email', v_u.email, 'created_at', v_u.created_at,
                               'last_sign_in_at', v_u.last_sign_in_at, 'email_confirmed_at', v_u.email_confirmed_at,
                               'banned_until', v_u.banned_until, 'provider', v_u.provider),
    'target_schedule', (select jsonb_build_object('id', s.id, 'title_en', s.title_en, 'title_bn', s.title_bn,
                                                  'expected_date', s.expected_date)
                          from public.exam_schedules s where s.id = v_p.target_schedule_id),
    'entitlements', (select coalesce(jsonb_agg(jsonb_build_object(
                       'id', e.id, 'addon_code', e.addon_code, 'addon_name', a.name_en, 'source', e.source,
                       'starts_at', e.starts_at, 'expires_at', e.expires_at,
                       'active', e.starts_at <= now() and e.expires_at > now(),
                       'upcoming', e.starts_at > now(), 'created_at', e.created_at)
                       order by e.expires_at desc), '[]'::jsonb)
                       from (select * from public.user_entitlements where user_id = p_user
                              order by expires_at desc limit 50) e
                       left join public.addons a on a.code = e.addon_code),
    'exams', (select jsonb_build_object(
                'submitted', count(*) filter (where status = 'submitted'),
                'in_progress', count(*) filter (where status = 'in_progress'),
                'last_submitted_at', max(submitted_at),
                'avg_score_pct', round(avg(case when status = 'submitted' and max_score > 0
                                                then score / max_score * 100 end), 1),
                'by_kind', coalesce((select jsonb_object_agg(k.kind, k.n) from (
                             select kind, count(*) n from public.exam_sessions
                              where user_id = p_user and status = 'submitted' group by kind) k), '{}'::jsonb))
                from public.exam_sessions where user_id = p_user),
    'attempts', (select count(*) from public.question_attempts where user_id = p_user),
    'plan', (select jsonb_build_object('id', sp.id, 'exam_date', sp.exam_date, 'start_date', sp.start_date,
                                       'version', sp.version, 'daily_minutes', sp.daily_minutes)
               from public.study_plans sp where sp.user_id = p_user and sp.status = 'active'),
    'reports', jsonb_build_object(
      'against_open', (select count(*) from public.reports
                        where target_type = 'user' and target_id = p_user::text and status = 'open'),
      'filed', (select count(*) from public.reports where reporter_id = p_user)),
    'promo_redemptions', (select coalesce(jsonb_agg(jsonb_build_object('code', r.code::text, 'redeemed_at', r.redeemed_at)
                                                    order by r.redeemed_at desc), '[]'::jsonb)
                            from public.promo_redemptions r where r.user_id = p_user),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'addon_code', x.addon_code,
                                                              'amount_bdt', x.amount_bdt, 'provider', x.provider,
                                                              'status', x.status, 'created_at', x.created_at)
                                           order by x.created_at desc), '[]'::jsonb)
                   from (select * from public.payments where user_id = p_user order by created_at desc limit 10) x),
    'audit', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'action', l.action, 'details', l.details,
                                                           'created_at', l.created_at, 'actor', ap.username)
                                        order by l.id desc), '[]'::jsonb)
                from (select * from public.admin_audit_log
                       where target_type = 'user' and target_id = p_user::text order by id desc limit 15) l
                left join public.profiles ap on ap.id = l.actor_id));
end $$;

create or replace function public.admin_change_role(p_user uuid, p_role text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   public.user_role;
begin
  if p_role is null or p_role not in ('user', 'moderator', 'admin') then
    raise exception 'invalid_role' using errcode = 'PT400';
  end if;
  if p_user = v_actor then
    raise exception 'cannot_change_own_role' using errcode = 'PT409';
  end if;
  select role into v_old from public.profiles where id = p_user for update;
  if not found then raise exception 'user_not_found' using errcode = 'PT404'; end if;
  if v_old::text = p_role then return; end if;
  perform public.admin_set_role(p_user, p_role::public.user_role);
  perform public._admin_audit('user.set_role', 'user', p_user::text,
                              jsonb_build_object('from', v_old, 'to', p_role));
end $$;

-- Ban = profile flag + Supabase Auth ban (blocks sign-in and token refresh)
-- + all sessions revoked. Admins must be demoted before they can be banned.
create or replace function public.admin_set_ban(p_user uuid, p_banned boolean, p_reason text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor   uuid := public._console_assert_admin();
  v_role    public.user_role;
  v_was     boolean;
  v_auth_ok boolean := true;
begin
  if p_banned is null then raise exception 'invalid_input' using errcode = 'PT400'; end if;
  if p_reason is not null and char_length(p_reason) > 500 then
    raise exception 'reason_too_long' using errcode = 'PT400';
  end if;
  if p_user = v_actor then raise exception 'cannot_ban_self' using errcode = 'PT409'; end if;
  select role, is_banned into v_role, v_was from public.profiles where id = p_user for update;
  if not found then raise exception 'user_not_found' using errcode = 'PT404'; end if;
  if p_banned and v_role = 'admin' then raise exception 'cannot_ban_admin' using errcode = 'PT409'; end if;

  update public.profiles set is_banned = p_banned where id = p_user;
  begin
    update auth.users
       set banned_until = case when p_banned then now() + interval '100 years' else null end
     where id = p_user;
    if p_banned then
      delete from auth.sessions where user_id = p_user;
    end if;
  exception when others then
    v_auth_ok := false;
  end;

  if v_was is distinct from p_banned then
    perform public._admin_audit(case when p_banned then 'user.ban' else 'user.unban' end, 'user', p_user::text,
                                jsonb_build_object('reason', nullif(btrim(p_reason), ''), 'auth_enforced', v_auth_ok));
  end if;
  return jsonb_build_object('is_banned', p_banned, 'auth_enforced', v_auth_ok);
end $$;

create or replace function public.admin_user_grant_addon(p_user uuid, p_addon text, p_days int)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_ent   public.user_entitlements;
begin
  if p_days is null or p_days not between 1 and 3650 then
    raise exception 'invalid_days' using errcode = 'PT400';
  end if;
  if not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'user_not_found' using errcode = 'PT404';
  end if;
  if not exists (select 1 from public.addons where code = p_addon) then
    raise exception 'addon_not_found' using errcode = 'PT404';
  end if;
  perform public.admin_grant_addon(p_user, p_addon, p_days);
  select * into v_ent from public.user_entitlements
   where user_id = p_user and addon_code = p_addon and source = 'admin'
   order by id desc limit 1;
  perform public._admin_audit('user.grant_addon', 'user', p_user::text,
                              jsonb_build_object('addon', p_addon, 'days', p_days, 'entitlement_id', v_ent.id,
                                                 'expires_at', v_ent.expires_at));
  return jsonb_build_object('id', v_ent.id, 'starts_at', v_ent.starts_at, 'expires_at', v_ent.expires_at);
end $$;

-- Ends a running entitlement now; a not-yet-started (stacked) one is removed.
create or replace function public.admin_revoke_entitlement(p_entitlement bigint, p_reason text default null)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_e     public.user_entitlements;
begin
  if p_reason is not null and char_length(p_reason) > 500 then
    raise exception 'reason_too_long' using errcode = 'PT400';
  end if;
  select * into v_e from public.user_entitlements where id = p_entitlement for update;
  if not found then raise exception 'entitlement_not_found' using errcode = 'PT404'; end if;
  if v_e.expires_at <= now() then raise exception 'entitlement_not_active' using errcode = 'PT409'; end if;
  if v_e.starts_at >= now() then
    delete from public.user_entitlements where id = v_e.id;
  else
    update public.user_entitlements set expires_at = now() where id = v_e.id;
  end if;
  perform public._admin_audit('user.revoke_entitlement', 'user', v_e.user_id::text,
                              jsonb_build_object('entitlement_id', v_e.id, 'addon', v_e.addon_code,
                                                 'source', v_e.source, 'previous_expires_at', v_e.expires_at,
                                                 'reason', nullif(btrim(p_reason), '')));
end $$;

create or replace function public.admin_reset_onboarding(p_user uuid, p_step text default 'profile')
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   text;
begin
  if p_step is null or p_step not in ('profile', 'interview', 'placement', 'plan', 'done') then
    raise exception 'invalid_step' using errcode = 'PT400';
  end if;
  select onboarding_step into v_old from public.profiles where id = p_user for update;
  if not found then raise exception 'user_not_found' using errcode = 'PT404'; end if;
  update public.profiles set onboarding_step = p_step where id = p_user;
  perform public._admin_audit('user.set_onboarding', 'user', p_user::text,
                              jsonb_build_object('from', v_old, 'to', p_step));
end $$;

-- ===========================================================================
-- Questions (staff; bulk import is admin-only)
-- ===========================================================================
create or replace function public.admin_search_questions(
  p_subject smallint default null, p_topic int default null, p_tag text default null,
  p_status text default null, p_review text default null, p_source_kind text default null,
  p_source_id bigint default null, p_search text default null,
  p_limit int default 25, p_after_id bigint default null
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_search text := nullif(btrim(p_search), '');
begin
  perform public._console_assert_staff();
  perform public._admin_question_filters_check(p_tag, p_status, p_review, p_source_kind, v_search);
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', q.id, 'subject_id', q.subject_id, 'topic_id', q.topic_id, 'stem', q.stem,
             'options', q.options, 'correct_index', q.correct_index, 'explanation', q.explanation,
             'difficulty', q.difficulty, 'language', q.language, 'source_id', q.source_id,
             'source_kind', s.kind, 'source_name', s.name, 'source_ref', q.source_ref, 'source_url', q.source_url,
             'exam_tags', q.exam_tags, 'year', q.year, 'status', q.status, 'review_status', q.review_status,
             'times_answered', q.times_answered, 'times_correct', q.times_correct, 'fact_id', q.fact_id,
             'created_at', q.created_at,
             'open_reports', (select count(*) from public.reports r
                               where r.target_type = 'question' and r.target_id = q.id::text and r.status = 'open'))
             order by q.id desc), '[]'::jsonb)
      from public.questions q
      left join public.sources s on s.id = q.source_id
     where q.id in (select pg.id from public._admin_question_page(p_subject, p_topic, p_tag, p_status, p_review,
                                                                  p_source_kind, p_source_id, v_search,
                                                                  least(greatest(coalesce(p_limit, 25), 1), 100),
                                                                  p_after_id) pg));
end $$;

create or replace function public.admin_get_question(p_id bigint)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_q public.questions;
begin
  perform public._console_assert_staff();
  select * into v_q from public.questions where id = p_id;
  if not found then raise exception 'question_not_found' using errcode = 'PT404'; end if;
  return (to_jsonb(v_q) - 'embedding' - 'stem_hash') || jsonb_build_object(
    'has_embedding', v_q.embedding is not null,
    'subject', (select jsonb_build_object('id', s.id, 'code', s.code, 'name_bn', s.name_bn, 'name_en', s.name_en)
                  from public.subjects s where s.id = v_q.subject_id),
    'topic', (select jsonb_build_object('id', t.id, 'code', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en)
                from public.topics t where t.id = v_q.topic_id),
    'source', (select to_jsonb(s) from public.sources s where s.id = v_q.source_id),
    'fact', (select jsonb_build_object('id', f.id, 'fact', f.fact, 'fact_en', f.fact_en, 'status', f.status,
                                       'first_seen_date', f.first_seen_date, 'superseded_by', f.superseded_by,
                                       'source_links', f.source_links)
               from public.facts f where f.id = v_q.fact_id),
    'created_by_user', (select jsonb_build_object('id', p.id, 'username', p.username, 'full_name', p.full_name)
                          from public.profiles p where p.id = v_q.created_by),
    'answer_stats', (select coalesce(jsonb_agg(jsonb_build_object('selected_index', a.selected_index, 'count', a.n)
                                               order by a.selected_index nulls last), '[]'::jsonb)
                       from (select selected_index, count(*) n from public.question_attempts
                              where question_id = v_q.id and mode in ('exam', 'practice')
                              group by selected_index) a),
    'reports', (select jsonb_build_object('open', count(*) filter (where status = 'open'), 'total', count(*))
                  from public.reports where target_type = 'question' and target_id = v_q.id::text),
    'daily_exam_dates', (select coalesce(jsonb_agg(d.exam_date order by d.exam_date desc), '[]'::jsonb)
                           from public.daily_exams d where v_q.id = any (d.question_ids)),
    'ai_explanation', (select e.explanation from public.ai_explanations e where e.question_id = v_q.id));
end $$;

-- Create (p_id null) or update a question. Payload keys:
--   subject_id, topic_id, stem, options[], correct_index, explanation, difficulty, language,
--   exam_tags[], year, status, review_status, source_id | (source_kind + source_name),
--   source_ref, source_url
create or replace function public.admin_save_question(p_id bigint, p_question jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor   uuid := public._console_assert_staff();
  v_err     text;
  v_subject smallint;
  v_topic   int;
  v_source  bigint;
  v_tags    text[];
  v_status  text := coalesce(nullif(p_question ->> 'status', ''), 'published');
  v_review  text := coalesce(nullif(p_question ->> 'review_status', ''), 'unverified');
  v_stem    text := btrim(p_question ->> 'stem');
  v_old     public.questions;
  v_new     public.questions;
  v_dup     bigint;
begin
  v_err := public._admin_question_error(p_question);
  if v_err is not null then raise exception 'invalid_question' using errcode = 'PT400', detail = v_err; end if;
  if coalesce(p_question ->> 'subject_id', '') !~ '^\d{1,4}$' then
    raise exception 'invalid_question' using errcode = 'PT400', detail = 'subject_required';
  end if;
  select id into v_subject from public.subjects where id = (p_question ->> 'subject_id')::smallint;
  if not found then raise exception 'invalid_question' using errcode = 'PT400', detail = 'subject_unknown'; end if;
  if nullif(p_question ->> 'topic_id', '') is not null then
    if (p_question ->> 'topic_id') !~ '^\d{1,9}$' then
      raise exception 'invalid_question' using errcode = 'PT400', detail = 'topic_invalid';
    end if;
    select id into v_topic from public.topics
     where id = (p_question ->> 'topic_id')::int and subject_id = v_subject;
    if not found then raise exception 'invalid_question' using errcode = 'PT400', detail = 'topic_subject_mismatch'; end if;
  end if;
  if v_status not in ('draft', 'published', 'rejected', 'archived') then
    raise exception 'invalid_question' using errcode = 'PT400', detail = 'status_invalid';
  end if;
  if v_review not in ('unverified', 'verified', 'flagged') then
    raise exception 'invalid_question' using errcode = 'PT400', detail = 'review_status_invalid';
  end if;

  if jsonb_typeof(p_question -> 'source_id') = 'number' then
    select id into v_source from public.sources where id = (p_question ->> 'source_id')::bigint;
    if not found then raise exception 'invalid_question' using errcode = 'PT400', detail = 'source_unknown'; end if;
  elsif nullif(btrim(p_question ->> 'source_name'), '') is not null then
    insert into public.sources (kind, name)
    values (coalesce(nullif(p_question ->> 'source_kind', ''), 'curated')::public.source_kind,
            btrim(p_question ->> 'source_name'))
    on conflict (kind, name) do nothing;
    select id into v_source from public.sources
     where kind = coalesce(nullif(p_question ->> 'source_kind', ''), 'curated')::public.source_kind
       and name = btrim(p_question ->> 'source_name');
  end if;

  select coalesce(array_agg(distinct t order by t), '{}') into v_tags
    from jsonb_array_elements_text(case when jsonb_typeof(p_question -> 'exam_tags') = 'array'
                                        then p_question -> 'exam_tags' else '[]'::jsonb end) t;

  begin
    if p_id is null then
      insert into public.questions
        (subject_id, topic_id, stem, options, correct_index, explanation, difficulty, language,
         source_id, source_ref, source_url, exam_tags, year, status, review_status, created_by)
      values
        (v_subject, v_topic, v_stem, p_question -> 'options', (p_question ->> 'correct_index')::smallint,
         nullif(btrim(p_question ->> 'explanation'), ''),
         coalesce(nullif(p_question ->> 'difficulty', '')::smallint, 2),
         coalesce(nullif(p_question ->> 'language', ''), 'bn'),
         v_source, nullif(btrim(p_question ->> 'source_ref'), ''), nullif(btrim(p_question ->> 'source_url'), ''),
         v_tags, nullif(p_question ->> 'year', '')::int, v_status, v_review, v_actor)
      returning * into v_new;
      perform public._admin_audit('question.create', 'question', v_new.id::text,
                                  jsonb_build_object('stem', left(v_new.stem, 200), 'subject_id', v_new.subject_id,
                                                     'status', v_new.status));
    else
      select * into v_old from public.questions where id = p_id for update;
      if not found then raise exception 'question_not_found' using errcode = 'PT404'; end if;
      update public.questions set
        subject_id    = v_subject,
        topic_id      = v_topic,
        stem          = v_stem,
        options       = p_question -> 'options',
        correct_index = (p_question ->> 'correct_index')::smallint,
        explanation   = nullif(btrim(p_question ->> 'explanation'), ''),
        difficulty    = coalesce(nullif(p_question ->> 'difficulty', '')::smallint, 2),
        language      = coalesce(nullif(p_question ->> 'language', ''), 'bn'),
        source_id     = v_source,
        source_ref    = nullif(btrim(p_question ->> 'source_ref'), ''),
        source_url    = nullif(btrim(p_question ->> 'source_url'), ''),
        exam_tags     = v_tags,
        year          = nullif(p_question ->> 'year', '')::int,
        status        = v_status,
        review_status = v_review,
        -- an edited stem/options make the stored embedding stale (semantic de-dup)
        embedding     = case when v_old.stem is distinct from v_stem or v_old.options is distinct from p_question -> 'options'
                             then null else embedding end
      where id = p_id
      returning * into v_new;
      perform public._admin_audit('question.update', 'question', p_id::text,
        public._jsonb_diff(to_jsonb(v_old) - 'embedding' - 'stem_hash' - 'times_answered' - 'times_correct',
                           to_jsonb(v_new) - 'embedding' - 'stem_hash' - 'times_answered' - 'times_correct'));
    end if;
  exception when unique_violation then
    select id into v_dup from public.questions
     where stem_hash = md5(lower(regexp_replace(v_stem, '\s+', '', 'g'))) and id is distinct from p_id;
    raise exception 'duplicate_question' using errcode = 'PT409', detail = coalesce(v_dup::text, '');
  end;
  return jsonb_build_object('id', v_new.id);
end $$;

-- Bulk verify / flag / reject / archive / publish.
create or replace function public.admin_set_question_status(
  p_ids bigint[], p_status text default null, p_review_status text default null
)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_staff();
  v_n     int;
begin
  if p_ids is null or cardinality(p_ids) = 0 or cardinality(p_ids) > 500 then
    raise exception 'invalid_ids' using errcode = 'PT400';
  end if;
  if p_status is null and p_review_status is null then
    raise exception 'nothing_to_change' using errcode = 'PT400';
  end if;
  perform public._admin_question_filters_check(null, p_status, p_review_status, null, null);
  update public.questions
     set status = coalesce(p_status, status),
         review_status = coalesce(p_review_status, review_status)
   where id = any (p_ids)
     and (status is distinct from coalesce(p_status, status)
          or review_status is distinct from coalesce(p_review_status, review_status));
  get diagnostics v_n = row_count;
  perform public._admin_audit('question.set_status', 'question',
                              case when cardinality(p_ids) = 1 then p_ids[1]::text end,
                              jsonb_build_object('ids', to_jsonb(p_ids), 'status', p_status,
                                                 'review_status', p_review_status, 'changed', v_n));
  return v_n;
end $$;

-- Which of these stems already exist (same normalisation as questions.stem_hash)?
create or replace function public.admin_find_duplicate_questions(p_stems text[])
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public._console_assert_staff();
  if p_stems is null or cardinality(p_stems) > 2000 then
    raise exception 'invalid_stems' using errcode = 'PT400';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('index', s.ord - 1, 'id', q.id, 'status', q.status)
                                    order by s.ord), '[]'::jsonb)
            from unnest(p_stems) with ordinality s(stem, ord)
            join public.questions q on q.stem_hash = md5(lower(regexp_replace(btrim(s.stem), '\s+', '', 'g'))));
end $$;

-- Bulk import in the seed-file format (supabase/seed/questions/README.md).
-- Invalid items are reported (not inserted), duplicates are skipped.
create or replace function public.admin_import_questions(
  p_items jsonb, p_status text default 'published', p_review_status text default 'unverified'
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor    uuid := public._console_assert_admin();
  v_default  constant text := 'প্রস্তুতি কিউরেটেড প্রশ্নব্যাংক';
  v_count    int;
  v_valid    int;
  v_invalid  jsonb;
  v_inserted jsonb;
  v_dups     jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'expected_array' using errcode = 'PT400';
  end if;
  v_count := jsonb_array_length(p_items);
  if v_count = 0 or v_count > 1000 then
    raise exception 'batch_size' using errcode = 'PT400', detail = '1-1000 items per call';
  end if;
  if pg_column_size(p_items) > 4 * 1024 * 1024 then
    raise exception 'batch_too_large' using errcode = 'PT400';
  end if;
  if p_status is null or p_review_status is null then
    raise exception 'invalid_status' using errcode = 'PT400';
  end if;
  perform public._admin_question_filters_check(null, p_status, p_review_status, null, null);

  -- Validate once, keep the resolved ids and the stem hash per item.
  create temp table if not exists _admin_import (
    idx int, doc jsonb, subject_id smallint, topic_id int, err text, h text
  ) on commit drop;
  truncate pg_temp._admin_import;
  insert into pg_temp._admin_import (idx, doc, subject_id, topic_id, err, h)
  select (i.ord - 1)::int, i.doc, s.id, t.id,
         coalesce(public._admin_question_error(i.doc),
                  case when s.id is null then 'subject_unknown'
                       when nullif(i.doc ->> 'topic', '') is not null and t.id is null then 'topic_unknown'
                       when t.id is not null and t.subject_id <> s.id then 'topic_subject_mismatch' end),
         md5(lower(regexp_replace(btrim(coalesce(i.doc ->> 'stem', '')), '\s+', '', 'g')))
    from jsonb_array_elements(p_items) with ordinality i(doc, ord)
    left join public.subjects s on s.code = i.doc ->> 'subject'
    left join public.topics t on t.code = nullif(i.doc ->> 'topic', '');

  -- Provenance: create missing sources (kind + name is the key).
  insert into public.sources (kind, name, year, exam_type)
  select distinct on (x.kind, x.name) x.kind::public.source_kind, x.name, x.year,
         case when x.kind = 'previous_exam' then (select e.code from public.exam_types e where e.code = x.tag) end
    from (select coalesce(i.doc ->> 'source_kind', 'curated') as kind,
                 coalesce(nullif(btrim(i.doc ->> 'source_name'), ''), v_default) as name,
                 nullif(i.doc ->> 'source_year', '')::int as year,
                 coalesce(i.doc -> 'exam_tags' ->> 0, 'bcs') as tag
            from pg_temp._admin_import i
           where i.err is null) x
  on conflict (kind, name) do nothing;

  -- Insert the first occurrence of every stem; existing stems are skipped.
  with firsts as (
    select distinct on (i.h) i.* from pg_temp._admin_import i where i.err is null order by i.h, i.idx
  ), ins as (
    insert into public.questions
      (subject_id, topic_id, stem, options, correct_index, explanation, difficulty, language,
       source_id, source_ref, source_url, exam_tags, year, status, review_status, created_by)
    select f.subject_id, f.topic_id, btrim(f.doc ->> 'stem'), f.doc -> 'options', (f.doc ->> 'correct_index')::smallint,
           nullif(btrim(f.doc ->> 'explanation'), ''), coalesce(nullif(f.doc ->> 'difficulty', '')::smallint, 2),
           coalesce(nullif(f.doc ->> 'language', ''), 'bn'),
           src.id, nullif(btrim(f.doc ->> 'source_ref'), ''), nullif(btrim(f.doc ->> 'source_url'), ''),
           coalesce((select array_agg(distinct x order by x)
                       from jsonb_array_elements_text(case when jsonb_typeof(f.doc -> 'exam_tags') = 'array'
                                                           then f.doc -> 'exam_tags' else '[]'::jsonb end) x), '{}'),
           nullif(coalesce(f.doc ->> 'year', f.doc ->> 'source_year'), '')::int,
           p_status, p_review_status, v_actor
      from firsts f
      left join public.sources src
        on src.kind::text = coalesce(f.doc ->> 'source_kind', 'curated')
       and src.name = coalesce(nullif(btrim(f.doc ->> 'source_name'), ''), v_default)
    on conflict (stem_hash) do nothing
    returning id, stem_hash
  )
  select coalesce(jsonb_agg(jsonb_build_object('index', f.idx, 'id', ins.id) order by f.idx), '[]'::jsonb)
    into v_inserted
    from ins join firsts f on f.h = ins.stem_hash;

  select count(*) filter (where i.err is null),
         coalesce(jsonb_agg(jsonb_build_object('index', i.idx, 'error', i.err) order by i.idx)
                    filter (where i.err is not null), '[]'::jsonb),
         coalesce(jsonb_agg(i.idx order by i.idx)
                    filter (where i.err is null
                              and not exists (select 1 from jsonb_array_elements(v_inserted) x
                                               where (x ->> 'index')::int = i.idx)), '[]'::jsonb)
    into v_valid, v_invalid, v_dups
    from pg_temp._admin_import i;

  perform public._admin_audit('question.import', 'question', null,
                              jsonb_build_object('items', v_count, 'inserted', jsonb_array_length(v_inserted),
                                                 'invalid', jsonb_array_length(v_invalid),
                                                 'duplicates', jsonb_array_length(v_dups), 'status', p_status));
  return jsonb_build_object('total', v_count, 'inserted', v_inserted, 'invalid', v_invalid, 'duplicates', v_dups);
end $$;

-- Export one page in the seed-file format (round-trips through import).
create or replace function public.admin_export_questions(
  p_subject smallint default null, p_topic int default null, p_tag text default null,
  p_status text default null, p_review text default null, p_source_kind text default null,
  p_source_id bigint default null, p_search text default null,
  p_limit int default 500, p_after_id bigint default null
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_search text := nullif(btrim(p_search), '');
begin
  perform public._console_assert_staff();
  perform public._admin_question_filters_check(p_tag, p_status, p_review, p_source_kind, v_search);
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', q.id, 'subject', s.code, 'topic', t.code, 'stem', q.stem, 'options', q.options,
             'correct_index', q.correct_index, 'explanation', q.explanation, 'difficulty', q.difficulty,
             'language', q.language, 'exam_tags', to_jsonb(q.exam_tags), 'source_kind', src.kind,
             'source_name', src.name, 'source_year', q.year, 'source_ref', q.source_ref,
             'source_url', q.source_url, 'status', q.status, 'review_status', q.review_status)
             order by q.id desc), '[]'::jsonb)
      from public.questions q
      join public.subjects s on s.id = q.subject_id
      left join public.topics t on t.id = q.topic_id
      left join public.sources src on src.id = q.source_id
     where q.id in (select pg.id from public._admin_question_page(p_subject, p_topic, p_tag, p_status, p_review,
                                                                  p_source_kind, p_source_id, v_search,
                                                                  least(greatest(coalesce(p_limit, 500), 1), 1000),
                                                                  p_after_id) pg));
end $$;

-- ===========================================================================
-- Moderation (staff)
-- ===========================================================================
-- Audited wrapper around admin_resolve_report.
--   hide    → hide post/comment, reject question, ban user (profile flag)
--   restore → un-hide post/comment
--   dismiss → close without action
--   resolve → mark actioned without touching the content
create or replace function public.admin_moderate_report(p_report bigint, p_action text, p_note text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_staff();
  v_r     public.reports;
  v_n     int;
begin
  if p_action is null or p_action not in ('hide', 'restore', 'dismiss', 'resolve') then
    raise exception 'invalid_action' using errcode = 'PT400';
  end if;
  if p_note is not null and char_length(p_note) > 500 then
    raise exception 'note_too_long' using errcode = 'PT400';
  end if;
  select * into v_r from public.reports where id = p_report;
  if not found then raise exception 'report_not_found' using errcode = 'PT404'; end if;
  if v_r.target_type = 'user' and p_action = 'hide'
     and exists (select 1 from public.profiles where id::text = v_r.target_id and role <> 'user') then
    raise exception 'cannot_ban_staff' using errcode = 'PT409';
  end if;
  if v_r.target_type = 'user' and p_action = 'hide' and v_r.target_id = v_actor::text then
    raise exception 'cannot_ban_self' using errcode = 'PT409';
  end if;
  select count(*) into v_n from public.reports
   where target_type = v_r.target_type and target_id = v_r.target_id and status = 'open';
  perform public.admin_resolve_report(p_report, p_action);
  perform public._admin_audit('report.' || p_action, v_r.target_type, v_r.target_id,
                              jsonb_build_object('report_id', v_r.id, 'reason', v_r.reason,
                                                 'closed_reports', v_n, 'note', nullif(btrim(p_note), '')));
  return jsonb_build_object('closed_reports', v_n);
end $$;

-- Full preview of a reported item plus every report filed against it.
create or replace function public.admin_get_report_target(p_target_type text, p_target_id text)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_uuid    uuid;
  v_qid     bigint;
  v_content jsonb;
begin
  perform public._console_assert_staff();
  if p_target_type is null or p_target_type not in ('post', 'comment', 'user', 'message', 'question') then
    raise exception 'invalid_target_type' using errcode = 'PT400';
  end if;
  if p_target_type = 'question' then
    if coalesce(p_target_id, '') !~ '^\d{1,18}$' then raise exception 'invalid_target_id' using errcode = 'PT400'; end if;
    v_qid := p_target_id::bigint;
  else
    if coalesce(p_target_id, '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'invalid_target_id' using errcode = 'PT400';
    end if;
    v_uuid := p_target_id::uuid;
  end if;

  if p_target_type = 'post' then
    select jsonb_build_object('id', p.id, 'body', p.body, 'image_paths', to_jsonb(p.image_paths), 'kind', p.kind,
                              'meta', p.meta, 'visibility', p.visibility, 'is_hidden', p.is_hidden,
                              'report_count', p.report_count, 'reaction_count', p.reaction_count,
                              'comment_count', p.comment_count, 'created_at', p.created_at, 'author_id', p.author_id)
      into v_content from public.posts p where p.id = v_uuid;
  elsif p_target_type = 'comment' then
    select jsonb_build_object('id', c.id, 'body', c.body, 'is_hidden', c.is_hidden, 'post_id', c.post_id,
                              'post_excerpt', (select left(p.body, 300) from public.posts p where p.id = c.post_id),
                              'created_at', c.created_at, 'author_id', c.author_id)
      into v_content from public.comments c where c.id = v_uuid;
  elsif p_target_type = 'message' then
    select jsonb_build_object('id', m.id, 'body', case when m.deleted_at is null then m.body end,
                              'kind', m.kind, 'deleted', m.deleted_at is not null,
                              'conversation_id', m.conversation_id, 'created_at', m.created_at,
                              'author_id', m.sender_id)
      into v_content from public.messages m where m.id = v_uuid;
  elsif p_target_type = 'question' then
    select jsonb_build_object('id', q.id, 'stem', q.stem, 'options', q.options, 'correct_index', q.correct_index,
                              'explanation', q.explanation, 'status', q.status, 'review_status', q.review_status,
                              'source_ref', q.source_ref, 'source_url', q.source_url, 'subject_id', q.subject_id)
      into v_content from public.questions q where q.id = v_qid;
  else
    select jsonb_build_object('id', u.id, 'username', u.username, 'full_name', u.full_name, 'bio', u.bio,
                              'avatar_url', u.avatar_url, 'role', u.role, 'is_banned', u.is_banned,
                              'posts_count', u.posts_count, 'created_at', u.created_at, 'author_id', u.id)
      into v_content from public.profiles u where u.id = v_uuid;
  end if;

  return jsonb_build_object(
    'target_type', p_target_type,
    'target_id', p_target_id,
    'content', v_content,
    'author', (select jsonb_build_object('id', a.id, 'username', a.username, 'full_name', a.full_name,
                                         'avatar_url', a.avatar_url, 'is_banned', a.is_banned, 'role', a.role)
                 from public.profiles a where a.id = (v_content ->> 'author_id')::uuid),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', r.id, 'reason', r.reason, 'details', r.details, 'status', r.status,
                  'created_at', r.created_at, 'reviewed_at', r.reviewed_at,
                  'reporter', jsonb_build_object('id', p.id, 'username', p.username, 'full_name', p.full_name))
                  order by r.created_at desc), '[]'::jsonb)
                  from (select * from public.reports
                         where target_type = p_target_type and target_id = p_target_id
                         order by created_at desc limit 100) r
                  join public.profiles p on p.id = r.reporter_id));
end $$;

-- ===========================================================================
-- Current affairs (admin)
-- ===========================================================================
create or replace function public.admin_list_note_days(p_before date default null, p_limit int default 30)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public._console_assert_admin();
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'date', d.note_date, 'published', d.published, 'draft', d.draft, 'archived', d.archived,
             'daily_exam', (select jsonb_build_object('id', e.id, 'status', e.status,
                                                      'question_count', cardinality(e.question_ids))
                              from public.daily_exams e where e.exam_date = d.note_date))
             order by d.note_date desc), '[]'::jsonb)
      from (select note_date,
                   count(*) filter (where status = 'published') published,
                   count(*) filter (where status = 'draft') draft,
                   count(*) filter (where status = 'archived') archived
              from public.daily_notes
             where p_before is null or note_date < p_before
             group by note_date
             order by note_date desc
             limit least(greatest(coalesce(p_limit, 30), 1), 120)) d);
end $$;

create or replace function public.admin_list_notes(p_date date)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public._console_assert_admin();
  if p_date is null then raise exception 'invalid_date' using errcode = 'PT400'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', n.id, 'note_date', n.note_date, 'category', n.category, 'title', n.title, 'summary', n.summary,
             'title_en', n.title_en, 'summary_en', n.summary_en, 'key_facts', n.key_facts,
             'key_facts_en', n.key_facts_en, 'probable_questions', n.probable_questions,
             'probable_questions_en', n.probable_questions_en, 'importance', n.importance,
             'source_links', n.source_links, 'status', n.status, 'model', n.model,
             'fact_count', cardinality(n.fact_ids), 'created_at', n.created_at)
             order by n.importance desc, n.id), '[]'::jsonb)
      from public.daily_notes n
     where n.note_date = p_date);
end $$;

create or replace function public.admin_update_note(p_id bigint, p_patch jsonb)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   public.daily_notes;
  v_new   public.daily_notes;
  v_key   text;
begin
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_patch' using errcode = 'PT400';
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if v_key not in ('title', 'summary', 'title_en', 'summary_en', 'key_facts', 'key_facts_en',
                     'probable_questions', 'probable_questions_en', 'importance', 'category', 'status') then
      raise exception 'invalid_patch' using errcode = 'PT400', detail = 'unknown field ' || v_key;
    end if;
  end loop;
  if p_patch ? 'title' and char_length(btrim(coalesce(p_patch ->> 'title', ''))) not between 1 and 300 then
    raise exception 'invalid_patch' using errcode = 'PT400', detail = 'title';
  end if;
  if p_patch ? 'summary' and char_length(btrim(coalesce(p_patch ->> 'summary', ''))) not between 1 and 5000 then
    raise exception 'invalid_patch' using errcode = 'PT400', detail = 'summary';
  end if;
  if char_length(coalesce(p_patch ->> 'title_en', '')) > 300 or char_length(coalesce(p_patch ->> 'summary_en', '')) > 5000 then
    raise exception 'invalid_patch' using errcode = 'PT400', detail = 'english text too long';
  end if;
  if p_patch ? 'importance' and coalesce(p_patch ->> 'importance', '') !~ '^[1-5]$' then
    raise exception 'invalid_patch' using errcode = 'PT400', detail = 'importance';
  end if;
  if p_patch ? 'status' and coalesce(p_patch ->> 'status', '') not in ('draft', 'published', 'archived') then
    raise exception 'invalid_patch' using errcode = 'PT400', detail = 'status';
  end if;
  if p_patch ? 'category' and coalesce(p_patch ->> 'category', '') not in
       ('bangladesh', 'international', 'economy', 'science_tech', 'sports', 'environment',
        'awards_people', 'organizations', 'days_events', 'misc') then
    raise exception 'invalid_patch' using errcode = 'PT400', detail = 'category';
  end if;
  for v_key in select k from unnest(array['key_facts', 'key_facts_en']) k loop
    if p_patch ? v_key and (jsonb_typeof(p_patch -> v_key) <> 'array'
        or exists (select 1 from jsonb_array_elements(p_patch -> v_key) f
                    where jsonb_typeof(f) <> 'object' or jsonb_typeof(f -> 'fact') is distinct from 'string')) then
      raise exception 'invalid_patch' using errcode = 'PT400', detail = v_key || ' must be [{"fact": "...", "tag"?: "..."}]';
    end if;
  end loop;
  for v_key in select k from unnest(array['probable_questions', 'probable_questions_en']) k loop
    if p_patch ? v_key and (jsonb_typeof(p_patch -> v_key) <> 'array'
        or exists (select 1 from jsonb_array_elements(p_patch -> v_key) f
                    where jsonb_typeof(f) <> 'object' or jsonb_typeof(f -> 'q') is distinct from 'string'
                       or jsonb_typeof(f -> 'a') is distinct from 'string')) then
      raise exception 'invalid_patch' using errcode = 'PT400', detail = v_key || ' must be [{"q": "...", "a": "..."}]';
    end if;
  end loop;

  select * into v_old from public.daily_notes where id = p_id for update;
  if not found then raise exception 'note_not_found' using errcode = 'PT404'; end if;
  update public.daily_notes set
    title                 = case when p_patch ? 'title' then btrim(p_patch ->> 'title') else title end,
    summary               = case when p_patch ? 'summary' then btrim(p_patch ->> 'summary') else summary end,
    title_en              = case when p_patch ? 'title_en' then nullif(btrim(p_patch ->> 'title_en'), '') else title_en end,
    summary_en            = case when p_patch ? 'summary_en' then nullif(btrim(p_patch ->> 'summary_en'), '') else summary_en end,
    key_facts             = case when p_patch ? 'key_facts' then p_patch -> 'key_facts' else key_facts end,
    key_facts_en          = case when p_patch ? 'key_facts_en' then p_patch -> 'key_facts_en' else key_facts_en end,
    probable_questions    = case when p_patch ? 'probable_questions' then p_patch -> 'probable_questions' else probable_questions end,
    probable_questions_en = case when p_patch ? 'probable_questions_en' then p_patch -> 'probable_questions_en' else probable_questions_en end,
    importance            = case when p_patch ? 'importance' then (p_patch ->> 'importance')::smallint else importance end,
    category              = case when p_patch ? 'category' then p_patch ->> 'category' else category end,
    status                = case when p_patch ? 'status' then p_patch ->> 'status' else status end
  where id = p_id
  returning * into v_new;
  perform public._admin_audit('note.update', 'daily_note', p_id::text,
    public._jsonb_diff(to_jsonb(v_old) - 'embedding', to_jsonb(v_new) - 'embedding')
      || jsonb_build_object('note_date', v_old.note_date));
end $$;

create or replace function public.admin_delete_note(p_id bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   public.daily_notes;
begin
  delete from public.daily_notes where id = p_id returning * into v_old;
  if not found then raise exception 'note_not_found' using errcode = 'PT404'; end if;
  perform public._admin_audit('note.delete', 'daily_note', p_id::text,
                              jsonb_build_object('note_date', v_old.note_date, 'title', v_old.title,
                                                 'category', v_old.category, 'status', v_old.status));
end $$;

create or replace function public.admin_get_daily_exam(p_date date)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_e public.daily_exams;
begin
  perform public._console_assert_admin();
  select * into v_e from public.daily_exams where exam_date = p_date;
  if not found then return null; end if;
  return to_jsonb(v_e) || jsonb_build_object(
    'questions', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', q.id, 'stem', q.stem, 'options', q.options, 'correct_index', q.correct_index,
                    'explanation', q.explanation, 'status', q.status, 'review_status', q.review_status,
                    'source_ref', q.source_ref, 'source_url', q.source_url, 'subject_id', q.subject_id,
                    'times_answered', q.times_answered, 'times_correct', q.times_correct)
                    order by u.ord), '[]'::jsonb)
                    from unnest(v_e.question_ids) with ordinality u(qid, ord)
                    join public.questions q on q.id = u.qid),
    'submissions', (select jsonb_build_object('count', count(*), 'avg_score', round(avg(score), 2),
                                              'max_score', max(score), 'avg_time_seconds', round(avg(time_taken_seconds)))
                      from public.exam_sessions where daily_exam_id = v_e.id and status = 'submitted'));
end $$;

create or replace function public.admin_list_news_sources()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public._console_assert_admin();
  return (
    select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object(
             'articles_24h', (select count(*) from public.news_articles a
                               where a.source_id = s.id and a.fetched_at >= now() - interval '24 hours'),
             'articles_7d', (select count(*) from public.news_articles a
                              where a.source_id = s.id and a.fetched_at >= now() - interval '7 days'))
             order by s.priority desc, s.name), '[]'::jsonb)
      from public.news_sources s);
end $$;

-- Create (p_id null) or update an RSS source. Editing resets the failure back-off.
create or replace function public.admin_save_news_source(p_id smallint, p_source jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   public.news_sources;
  v_new   public.news_sources;
  v_name  text := btrim(coalesce(p_source ->> 'name', ''));
  v_rss   text := btrim(coalesce(p_source ->> 'rss_url', ''));
  v_home  text := nullif(btrim(coalesce(p_source ->> 'homepage', '')), '');
  v_lang  text := coalesce(nullif(p_source ->> 'language', ''), 'bn');
  v_reg   text := coalesce(nullif(p_source ->> 'region', ''), 'BD');
  v_hint  text := nullif(btrim(coalesce(p_source ->> 'category_hint', '')), '');
  v_prio  text := coalesce(nullif(p_source ->> 'priority', ''), '5');
  v_en    boolean;
begin
  if p_source is null or jsonb_typeof(p_source) <> 'object' then
    raise exception 'invalid_source' using errcode = 'PT400';
  end if;
  if char_length(v_name) not between 2 and 100 then raise exception 'invalid_source' using errcode = 'PT400', detail = 'name'; end if;
  if not public._is_http_url(v_rss) then raise exception 'invalid_source' using errcode = 'PT400', detail = 'rss_url'; end if;
  if v_home is not null and not public._is_http_url(v_home) then
    raise exception 'invalid_source' using errcode = 'PT400', detail = 'homepage';
  end if;
  if v_lang not in ('bn', 'en') then raise exception 'invalid_source' using errcode = 'PT400', detail = 'language'; end if;
  if v_reg not in ('BD', 'INT') then raise exception 'invalid_source' using errcode = 'PT400', detail = 'region'; end if;
  if v_hint is not null and char_length(v_hint) > 50 then raise exception 'invalid_source' using errcode = 'PT400', detail = 'category_hint'; end if;
  if v_prio !~ '^\d{1,2}$' or v_prio::int not between 1 and 10 then
    raise exception 'invalid_source' using errcode = 'PT400', detail = 'priority';
  end if;
  if p_source ? 'enabled' and jsonb_typeof(p_source -> 'enabled') <> 'boolean' then
    raise exception 'invalid_source' using errcode = 'PT400', detail = 'enabled';
  end if;
  v_en := coalesce((p_source ->> 'enabled')::boolean, true);

  begin
    if p_id is null then
      insert into public.news_sources (name, homepage, rss_url, language, region, category_hint, priority, enabled)
      values (v_name, v_home, v_rss, v_lang, v_reg, v_hint, v_prio::smallint, v_en)
      returning * into v_new;
      perform public._admin_audit('news_source.create', 'news_source', v_new.id::text,
                                  jsonb_build_object('name', v_name, 'rss_url', v_rss));
    else
      select * into v_old from public.news_sources where id = p_id for update;
      if not found then raise exception 'source_not_found' using errcode = 'PT404'; end if;
      update public.news_sources set
        name = v_name, homepage = v_home, rss_url = v_rss, language = v_lang, region = v_reg,
        category_hint = v_hint, priority = v_prio::smallint, enabled = v_en,
        fail_count = case when v_en and (not v_old.enabled or v_old.rss_url <> v_rss) then 0 else fail_count end,
        last_error = case when v_en and (not v_old.enabled or v_old.rss_url <> v_rss) then null else last_error end
      where id = p_id
      returning * into v_new;
      perform public._admin_audit('news_source.update', 'news_source', p_id::text,
                                  public._jsonb_diff(to_jsonb(v_old), to_jsonb(v_new)));
    end if;
  exception when unique_violation then
    raise exception 'duplicate_feed' using errcode = 'PT409';
  end;
  return to_jsonb(v_new);
end $$;

-- Audited, rate-limited wrapper around admin_run_pipeline.
create or replace function public.admin_trigger_pipeline(p_stage text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_id    bigint;
begin
  if p_stage is null or p_stage not in ('ingest-news', 'generate-daily-notes', 'generate-daily-exam', 'dispatch-notifications') then
    raise exception 'invalid_stage' using errcode = 'PT400';
  end if;
  perform public.enforce_rate_limit('admin_pipeline:' || p_stage, 3, 600);
  v_id := public.admin_run_pipeline(p_stage);
  perform public._admin_audit('pipeline.run', 'pipeline', p_stage,
                              jsonb_build_object('request_id', v_id, 'configured', v_id is not null));
  return jsonb_build_object('request_id', v_id, 'configured', v_id is not null);
end $$;

-- Result of an async Edge Function call started by admin_trigger_pipeline.
create or replace function public.admin_pipeline_result(p_request_id bigint)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v jsonb;
begin
  perform public._console_assert_admin();
  begin
    select jsonb_build_object('status_code', r.status_code, 'content', left(r.content, 4000),
                              'error', r.error_msg, 'timed_out', r.timed_out, 'created', r.created)
      into v
      from net._http_response r where r.id = p_request_id;
  exception when others then
    return jsonb_build_object('available', false);
  end;
  return coalesce(v, jsonb_build_object('pending', true));
end $$;

-- ===========================================================================
-- Exam schedules (admin)
-- ===========================================================================
create or replace function public.admin_list_schedules()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_default text := (select value #>> '{}' from public.app_config where key = 'default_schedule_id');
begin
  perform public._console_assert_admin();
  return (
    select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object(
             'exam_type_name', et.name_en,
             'active_plans', (select count(*) from public.study_plans sp
                               where sp.schedule_id = s.id and sp.status = 'active'),
             'target_users', (select count(*) from public.profiles p where p.target_schedule_id = s.id),
             'is_default', s.id::text = v_default)
             order by s.expected_date, s.id), '[]'::jsonb)
      from public.exam_schedules s
      left join public.exam_types et on et.code = s.exam_type);
end $$;

-- Create (p_id null) or update. Changing expected_date re-plans every active
-- study plan for this exam and notifies those learners (trigger from 0007/0012).
create or replace function public.admin_save_schedule(p_id bigint, p_schedule jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor  uuid := public._console_assert_admin();
  v_old    public.exam_schedules;
  v_new    public.exam_schedules;
  v_type   text := p_schedule ->> 'exam_type';
  v_tbn    text := btrim(coalesce(p_schedule ->> 'title_bn', ''));
  v_ten    text := btrim(coalesce(p_schedule ->> 'title_en', ''));
  v_stage  text := coalesce(nullif(btrim(p_schedule ->> 'stage'), ''), 'preliminary');
  v_date   date;
  v_url    text := nullif(btrim(coalesce(p_schedule ->> 'source_url', '')), '');
  v_notes  text := nullif(btrim(coalesce(p_schedule ->> 'notes', '')), '');
  v_plans  int := 0;
begin
  if p_schedule is null or jsonb_typeof(p_schedule) <> 'object' then
    raise exception 'invalid_schedule' using errcode = 'PT400';
  end if;
  if not exists (select 1 from public.exam_types where code = v_type) then
    raise exception 'invalid_schedule' using errcode = 'PT400', detail = 'exam_type';
  end if;
  if char_length(v_tbn) not between 2 and 200 or char_length(v_ten) not between 2 and 200 then
    raise exception 'invalid_schedule' using errcode = 'PT400', detail = 'title';
  end if;
  if char_length(v_stage) > 40 then raise exception 'invalid_schedule' using errcode = 'PT400', detail = 'stage'; end if;
  if coalesce(p_schedule ->> 'expected_date', '') !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'invalid_schedule' using errcode = 'PT400', detail = 'expected_date';
  end if;
  v_date := (p_schedule ->> 'expected_date')::date;
  if v_date not between public.bd_today() - 3650 and public.bd_today() + 3650 then
    raise exception 'invalid_schedule' using errcode = 'PT400', detail = 'expected_date';
  end if;
  if v_url is not null and not public._is_http_url(v_url) then
    raise exception 'invalid_schedule' using errcode = 'PT400', detail = 'source_url';
  end if;
  if v_notes is not null and char_length(v_notes) > 1000 then
    raise exception 'invalid_schedule' using errcode = 'PT400', detail = 'notes';
  end if;
  if (p_schedule ? 'is_confirmed' and jsonb_typeof(p_schedule -> 'is_confirmed') <> 'boolean')
     or (p_schedule ? 'is_active' and jsonb_typeof(p_schedule -> 'is_active') <> 'boolean') then
    raise exception 'invalid_schedule' using errcode = 'PT400', detail = 'flags';
  end if;

  if p_id is null then
    insert into public.exam_schedules (exam_type, title_bn, title_en, stage, expected_date, is_confirmed,
                                       source_url, notes, is_active)
    values (v_type, v_tbn, v_ten, v_stage, v_date, coalesce((p_schedule ->> 'is_confirmed')::boolean, false),
            v_url, v_notes, coalesce((p_schedule ->> 'is_active')::boolean, true))
    returning * into v_new;
    perform public._admin_audit('schedule.create', 'exam_schedule', v_new.id::text, to_jsonb(v_new));
  else
    select * into v_old from public.exam_schedules where id = p_id for update;
    if not found then raise exception 'schedule_not_found' using errcode = 'PT404'; end if;
    if v_old.expected_date is distinct from v_date then
      select count(*) into v_plans from public.study_plans where schedule_id = p_id and status = 'active';
    end if;
    update public.exam_schedules set
      exam_type = v_type, title_bn = v_tbn, title_en = v_ten, stage = v_stage, expected_date = v_date,
      is_confirmed = coalesce((p_schedule ->> 'is_confirmed')::boolean, is_confirmed),
      source_url = v_url, notes = v_notes,
      is_active = coalesce((p_schedule ->> 'is_active')::boolean, is_active)
    where id = p_id
    returning * into v_new;
    perform public._admin_audit('schedule.update', 'exam_schedule', p_id::text,
      public._jsonb_diff(to_jsonb(v_old) - 'updated_at', to_jsonb(v_new) - 'updated_at')
        || jsonb_build_object('replanned_plans', v_plans));
  end if;
  return jsonb_build_object('id', v_new.id, 'date_changed', v_old.id is not null and v_old.expected_date is distinct from v_date,
                            'replanned_plans', v_plans);
end $$;

create or replace function public.admin_delete_schedule(p_id bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   public.exam_schedules;
begin
  select * into v_old from public.exam_schedules where id = p_id for update;
  if not found then raise exception 'schedule_not_found' using errcode = 'PT404'; end if;
  if exists (select 1 from public.study_plans where schedule_id = p_id and status = 'active')
     or exists (select 1 from public.app_config where key = 'default_schedule_id' and value #>> '{}' = p_id::text) then
    raise exception 'schedule_in_use' using errcode = 'PT409',
      hint = 'Deactivate it instead, or move plans / default_schedule_id first';
  end if;
  delete from public.exam_schedules where id = p_id;
  perform public._admin_audit('schedule.delete', 'exam_schedule', p_id::text, to_jsonb(v_old));
end $$;

-- ===========================================================================
-- Exam tracks (model-test patterns; table from 0016)
-- ===========================================================================
create or replace function public.admin_list_exam_tracks()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public._console_assert_admin();
  if to_regclass('public.exam_tracks') is null then return '[]'::jsonb; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(t) || jsonb_build_object(
             'available', (select coalesce(jsonb_object_agg(c.code, c.n), '{}'::jsonb)
                             from (select s.code, count(*) n
                                     from public.questions q join public.subjects s on s.id = q.subject_id
                                    where q.status = 'published' and q.exam_tags @> array[t.code]
                                    group by s.code) c))
             order by t.sort, t.code), '[]'::jsonb)
      from public.exam_tracks t);
end $$;

create or replace function public.admin_save_exam_track(p_code text, p_track jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor  uuid := public._console_assert_admin();
  v_old    jsonb;
  v_new    jsonb;
  v_sizes  int[];
  v_full   int;
  v_neg    numeric;
  v_secs   int;
  v_sum    numeric;
  v_dist   jsonb := p_track -> 'distribution';
  v_bad    text;
begin
  if to_regclass('public.exam_tracks') is null then
    raise exception 'exam_tracks_missing' using errcode = 'PT404';
  end if;
  if p_track is null or jsonb_typeof(p_track) <> 'object' then
    raise exception 'invalid_track' using errcode = 'PT400';
  end if;
  select to_jsonb(t) into v_old from public.exam_tracks t where t.code = p_code for update;
  if v_old is null then raise exception 'track_not_found' using errcode = 'PT404'; end if;

  if char_length(btrim(coalesce(p_track ->> 'name_bn', ''))) not between 1 and 80
     or char_length(btrim(coalesce(p_track ->> 'name_en', ''))) not between 1 and 80 then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'name';
  end if;
  if char_length(coalesce(p_track ->> 'description_bn', '')) > 500 or char_length(coalesce(p_track ->> 'description_en', '')) > 500 then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'description';
  end if;
  if jsonb_typeof(p_track -> 'sizes') is distinct from 'array'
     or jsonb_array_length(p_track -> 'sizes') not between 1 and 6
     or exists (select 1 from jsonb_array_elements(p_track -> 'sizes') x
                 where jsonb_typeof(x) <> 'number' or (x #>> '{}') !~ '^\d{1,3}$'
                    or (x #>> '{}')::int not between 5 and 300) then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'sizes: 1-6 whole numbers between 5 and 300';
  end if;
  select array_agg(distinct (x #>> '{}')::int order by (x #>> '{}')::int) into v_sizes
    from jsonb_array_elements(p_track -> 'sizes') x;
  if cardinality(v_sizes) <> jsonb_array_length(p_track -> 'sizes') then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'sizes must be distinct';
  end if;
  if coalesce(p_track ->> 'full_marks', '') !~ '^\d{1,3}$' or (p_track ->> 'full_marks')::int not between 10 and 300 then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'full_marks: 10-300';
  end if;
  v_full := (p_track ->> 'full_marks')::int;
  if coalesce(p_track ->> 'negative_mark', '') !~ '^\d(\.\d{1,2})?$' or (p_track ->> 'negative_mark')::numeric > 1 then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'negative_mark: 0-1, two decimals';
  end if;
  v_neg := (p_track ->> 'negative_mark')::numeric;
  if coalesce(p_track ->> 'seconds_per_question', '') !~ '^\d{1,3}$'
     or (p_track ->> 'seconds_per_question')::int not between 10 and 180 then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'seconds_per_question: 10-180';
  end if;
  v_secs := (p_track ->> 'seconds_per_question')::int;
  if jsonb_typeof(v_dist) is distinct from 'object' or v_dist = '{}'::jsonb then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'distribution';
  end if;
  select string_agg(e.key, ', ') into v_bad
    from jsonb_each(v_dist) e
   where not exists (select 1 from public.subjects s where s.code = e.key)
      or jsonb_typeof(e.value) <> 'number' or (e.value #>> '{}') !~ '^\d{1,4}$' or (e.value #>> '{}')::int < 1;
  if v_bad is not null then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'distribution: bad subject/marks for ' || v_bad;
  end if;
  select sum((e.value #>> '{}')::int) into v_sum from jsonb_each(v_dist) e;
  if v_sum <> v_full then
    raise exception 'invalid_track' using errcode = 'PT400',
      detail = format('distribution sums to %s but full_marks is %s', v_sum, v_full);
  end if;
  if p_track ? 'is_active' and jsonb_typeof(p_track -> 'is_active') <> 'boolean' then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'is_active';
  end if;
  if p_track ? 'sort' and coalesce(p_track ->> 'sort', '') !~ '^-?\d{1,4}$' then
    raise exception 'invalid_track' using errcode = 'PT400', detail = 'sort';
  end if;

  update public.exam_tracks t set
    name_bn = btrim(p_track ->> 'name_bn'),
    name_en = btrim(p_track ->> 'name_en'),
    description_bn = nullif(btrim(coalesce(p_track ->> 'description_bn', '')), ''),
    description_en = nullif(btrim(coalesce(p_track ->> 'description_en', '')), ''),
    sizes = v_sizes,
    full_marks = v_full,
    negative_mark = v_neg,
    seconds_per_question = v_secs,
    distribution = v_dist,
    sort = coalesce((p_track ->> 'sort')::int, t.sort),
    is_active = coalesce((p_track ->> 'is_active')::boolean, t.is_active)
  where t.code = p_code;
  select to_jsonb(t) into v_new from public.exam_tracks t where t.code = p_code;
  perform public._admin_audit('track.update', 'exam_track', p_code,
                              public._jsonb_diff(v_old - 'updated_at', v_new - 'updated_at'));
  return v_new;
end $$;

-- ===========================================================================
-- Monetization (admin)
-- ===========================================================================
create or replace function public.admin_list_addons()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public._console_assert_admin();
  return jsonb_build_object(
    'addons', (select coalesce(jsonb_agg(to_jsonb(a) || jsonb_build_object(
                 'active', (select coalesce(jsonb_object_agg(x.source, x.n), '{}'::jsonb)
                              from (select e.source, count(*) n from public.user_entitlements e
                                     where e.addon_code = a.code and e.expires_at > now() and e.starts_at <= now()
                                     group by e.source) x),
                 'revenue_30d_bdt', (select coalesce(sum(p.amount_bdt), 0) from public.payments p
                                      where p.addon_code = a.code and p.status = 'success'
                                        and p.created_at >= now() - interval '30 days'))
                 order by a.sort, a.code), '[]'::jsonb)
                 from public.addons a),
    'features', (select coalesce(jsonb_agg(to_jsonb(f) order by f.sort, f.code), '[]'::jsonb)
                   from public.features f));
end $$;

create or replace function public.admin_save_addon(p_code text, p_addon jsonb, p_create boolean default false)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   public.addons;
  v_new   public.addons;
  v_feats text[];
  v_bad   text;
begin
  if p_addon is null or jsonb_typeof(p_addon) <> 'object' then raise exception 'invalid_addon' using errcode = 'PT400'; end if;
  if coalesce(p_code, '') !~ '^[a-z][a-z0-9_]{1,39}$' then raise exception 'invalid_addon' using errcode = 'PT400', detail = 'code'; end if;
  if char_length(btrim(coalesce(p_addon ->> 'name_bn', ''))) not between 1 and 80
     or char_length(btrim(coalesce(p_addon ->> 'name_en', ''))) not between 1 and 80 then
    raise exception 'invalid_addon' using errcode = 'PT400', detail = 'name';
  end if;
  if char_length(coalesce(p_addon ->> 'description_bn', '')) > 500 or char_length(coalesce(p_addon ->> 'description_en', '')) > 500 then
    raise exception 'invalid_addon' using errcode = 'PT400', detail = 'description';
  end if;
  if jsonb_typeof(p_addon -> 'features') is distinct from 'array' or jsonb_array_length(p_addon -> 'features') = 0 then
    raise exception 'invalid_addon' using errcode = 'PT400', detail = 'features';
  end if;
  select string_agg(f, ', ') into v_bad from jsonb_array_elements_text(p_addon -> 'features') f
   where not exists (select 1 from public.features x where x.code = f);
  if v_bad is not null then raise exception 'invalid_addon' using errcode = 'PT400', detail = 'unknown features: ' || v_bad; end if;
  select array_agg(distinct f order by f) into v_feats from jsonb_array_elements_text(p_addon -> 'features') f;
  if coalesce(p_addon ->> 'price_bdt', '') !~ '^\d{1,6}(\.\d{1,2})?$' or (p_addon ->> 'price_bdt')::numeric > 100000 then
    raise exception 'invalid_addon' using errcode = 'PT400', detail = 'price_bdt';
  end if;
  if coalesce(p_addon ->> 'period_days', '') !~ '^\d{1,4}$' or (p_addon ->> 'period_days')::int not between 1 and 3650 then
    raise exception 'invalid_addon' using errcode = 'PT400', detail = 'period_days';
  end if;
  if coalesce(p_addon ->> 'trial_days', '') !~ '^\d{1,3}$' or (p_addon ->> 'trial_days')::int > 90 then
    raise exception 'invalid_addon' using errcode = 'PT400', detail = 'trial_days';
  end if;
  if nullif(p_addon ->> 'color', '') is not null and (p_addon ->> 'color') !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'invalid_addon' using errcode = 'PT400', detail = 'color';
  end if;
  if nullif(p_addon ->> 'icon', '') is not null and (p_addon ->> 'icon') !~ '^[a-z0-9_]{1,40}$' then
    raise exception 'invalid_addon' using errcode = 'PT400', detail = 'icon';
  end if;
  if char_length(coalesce(p_addon ->> 'badge', '')) > 30 then raise exception 'invalid_addon' using errcode = 'PT400', detail = 'badge'; end if;
  if jsonb_typeof(p_addon -> 'is_active') is distinct from 'boolean' then
    raise exception 'invalid_addon' using errcode = 'PT400', detail = 'is_active';
  end if;
  if coalesce(p_addon ->> 'sort', '0') !~ '^-?\d{1,4}$' then raise exception 'invalid_addon' using errcode = 'PT400', detail = 'sort'; end if;

  if coalesce(p_create, false) then
    insert into public.addons (code, name_bn, name_en, description_bn, description_en, features, price_bdt,
                               period_days, trial_days, badge, color, icon, is_active, sort)
    values (p_code, btrim(p_addon ->> 'name_bn'), btrim(p_addon ->> 'name_en'),
            nullif(btrim(coalesce(p_addon ->> 'description_bn', '')), ''), nullif(btrim(coalesce(p_addon ->> 'description_en', '')), ''),
            v_feats, (p_addon ->> 'price_bdt')::numeric, (p_addon ->> 'period_days')::int, (p_addon ->> 'trial_days')::int,
            nullif(btrim(coalesce(p_addon ->> 'badge', '')), ''), nullif(p_addon ->> 'color', ''), nullif(p_addon ->> 'icon', ''),
            (p_addon ->> 'is_active')::boolean, coalesce(nullif(p_addon ->> 'sort', '')::int, 0))
    on conflict (code) do nothing
    returning * into v_new;
    if v_new.code is null then raise exception 'addon_exists' using errcode = 'PT409'; end if;
    perform public._admin_audit('addon.create', 'addon', p_code, to_jsonb(v_new));
  else
    select * into v_old from public.addons where code = p_code for update;
    if not found then raise exception 'addon_not_found' using errcode = 'PT404'; end if;
    update public.addons set
      name_bn = btrim(p_addon ->> 'name_bn'), name_en = btrim(p_addon ->> 'name_en'),
      description_bn = nullif(btrim(coalesce(p_addon ->> 'description_bn', '')), ''),
      description_en = nullif(btrim(coalesce(p_addon ->> 'description_en', '')), ''),
      features = v_feats, price_bdt = (p_addon ->> 'price_bdt')::numeric,
      period_days = (p_addon ->> 'period_days')::int, trial_days = (p_addon ->> 'trial_days')::int,
      badge = nullif(btrim(coalesce(p_addon ->> 'badge', '')), ''), color = nullif(p_addon ->> 'color', ''),
      icon = nullif(p_addon ->> 'icon', ''), is_active = (p_addon ->> 'is_active')::boolean,
      sort = coalesce(nullif(p_addon ->> 'sort', '')::int, sort)
    where code = p_code
    returning * into v_new;
    perform public._admin_audit('addon.update', 'addon', p_code, public._jsonb_diff(to_jsonb(v_old), to_jsonb(v_new)));
  end if;
  return to_jsonb(v_new);
end $$;

create or replace function public.admin_save_feature(p_code text, p_patch jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   public.features;
  v_new   public.features;
begin
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'invalid_feature' using errcode = 'PT400'; end if;
  if exists (select 1 from jsonb_object_keys(p_patch) k
              where k not in ('name_bn', 'name_en', 'description_bn', 'description_en', 'is_free', 'free_daily_quota', 'sort')) then
    raise exception 'invalid_feature' using errcode = 'PT400', detail = 'unknown field';
  end if;
  if p_patch ? 'is_free' and jsonb_typeof(p_patch -> 'is_free') <> 'boolean' then
    raise exception 'invalid_feature' using errcode = 'PT400', detail = 'is_free';
  end if;
  if p_patch ? 'free_daily_quota' and jsonb_typeof(p_patch -> 'free_daily_quota') <> 'null'
     and (coalesce(p_patch ->> 'free_daily_quota', '') !~ '^\d{1,4}$' or (p_patch ->> 'free_daily_quota')::int > 1000) then
    raise exception 'invalid_feature' using errcode = 'PT400', detail = 'free_daily_quota: empty or 0-1000';
  end if;
  if (p_patch ? 'name_bn' and char_length(btrim(coalesce(p_patch ->> 'name_bn', ''))) not between 1 and 80)
     or (p_patch ? 'name_en' and char_length(btrim(coalesce(p_patch ->> 'name_en', ''))) not between 1 and 80) then
    raise exception 'invalid_feature' using errcode = 'PT400', detail = 'name';
  end if;
  if char_length(coalesce(p_patch ->> 'description_bn', '')) > 500 or char_length(coalesce(p_patch ->> 'description_en', '')) > 500 then
    raise exception 'invalid_feature' using errcode = 'PT400', detail = 'description';
  end if;
  if p_patch ? 'sort' and coalesce(p_patch ->> 'sort', '') !~ '^-?\d{1,4}$' then
    raise exception 'invalid_feature' using errcode = 'PT400', detail = 'sort';
  end if;
  select * into v_old from public.features where code = p_code for update;
  if not found then raise exception 'feature_not_found' using errcode = 'PT404'; end if;
  update public.features set
    name_bn = case when p_patch ? 'name_bn' then btrim(p_patch ->> 'name_bn') else name_bn end,
    name_en = case when p_patch ? 'name_en' then btrim(p_patch ->> 'name_en') else name_en end,
    description_bn = case when p_patch ? 'description_bn' then nullif(btrim(coalesce(p_patch ->> 'description_bn', '')), '') else description_bn end,
    description_en = case when p_patch ? 'description_en' then nullif(btrim(coalesce(p_patch ->> 'description_en', '')), '') else description_en end,
    is_free = case when p_patch ? 'is_free' then (p_patch ->> 'is_free')::boolean else is_free end,
    free_daily_quota = case when p_patch ? 'free_daily_quota' then nullif(p_patch ->> 'free_daily_quota', '')::int else free_daily_quota end,
    sort = case when p_patch ? 'sort' then (p_patch ->> 'sort')::int else sort end
  where code = p_code
  returning * into v_new;
  perform public._admin_audit('feature.update', 'feature', p_code, public._jsonb_diff(to_jsonb(v_old), to_jsonb(v_new)));
  return to_jsonb(v_new);
end $$;

create or replace function public.admin_list_promos(
  p_search text default null, p_limit int default 50,
  p_after_created timestamptz default null, p_after_code text default null
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_q text := nullif(btrim(p_search), '');
begin
  perform public._console_assert_admin();
  if v_q is not null and char_length(v_q) > 40 then raise exception 'search_too_long' using errcode = 'PT400'; end if;
  if (p_after_created is null) <> (p_after_code is null) then
    raise exception 'invalid_cursor' using errcode = 'PT400';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'code', p.code::text, 'addon_code', p.addon_code, 'addon_name', a.name_en, 'days', p.days,
             'max_redemptions', p.max_redemptions, 'redeemed_count', p.redeemed_count,
             'expires_at', p.expires_at, 'is_active', p.is_active, 'created_at', p.created_at,
             'state', case when not p.is_active then 'inactive'
                           when p.expires_at is not null and p.expires_at < now() then 'expired'
                           when p.max_redemptions is not null and p.redeemed_count >= p.max_redemptions then 'exhausted'
                           else 'live' end)
             order by p.created_at desc, p.code::text desc), '[]'::jsonb)
      from (select * from public.promo_codes c
             where (v_q is null or c.code::text ilike public._like_pattern(v_q))
               and (p_after_created is null or (c.created_at, c.code::text) < (p_after_created, p_after_code))
             order by c.created_at desc, c.code::text desc
             limit least(greatest(coalesce(p_limit, 50), 1), 200)) p
      left join public.addons a on a.code = p.addon_code);
end $$;

create or replace function public.admin_save_promo(p_code text, p_promo jsonb, p_create boolean default false)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor  uuid := public._console_assert_admin();
  v_code   text := btrim(coalesce(p_code, ''));
  v_old    public.promo_codes;
  v_new    public.promo_codes;
  v_max    int;
  v_exp    timestamptz;
begin
  if p_promo is null or jsonb_typeof(p_promo) <> 'object' then raise exception 'invalid_promo' using errcode = 'PT400'; end if;
  if v_code !~ '^[A-Za-z0-9_-]{3,40}$' then raise exception 'invalid_promo' using errcode = 'PT400', detail = 'code'; end if;
  if not exists (select 1 from public.addons where code = p_promo ->> 'addon_code') then
    raise exception 'invalid_promo' using errcode = 'PT400', detail = 'addon_code';
  end if;
  if coalesce(p_promo ->> 'days', '') !~ '^\d{1,4}$' or (p_promo ->> 'days')::int not between 1 and 3650 then
    raise exception 'invalid_promo' using errcode = 'PT400', detail = 'days';
  end if;
  if nullif(p_promo ->> 'max_redemptions', '') is not null then
    if (p_promo ->> 'max_redemptions') !~ '^\d{1,7}$' or (p_promo ->> 'max_redemptions')::int < 1 then
      raise exception 'invalid_promo' using errcode = 'PT400', detail = 'max_redemptions';
    end if;
    v_max := (p_promo ->> 'max_redemptions')::int;
  end if;
  if nullif(p_promo ->> 'expires_at', '') is not null then
    begin
      v_exp := (p_promo ->> 'expires_at')::timestamptz;
    exception when others then
      raise exception 'invalid_promo' using errcode = 'PT400', detail = 'expires_at';
    end;
  end if;
  if jsonb_typeof(p_promo -> 'is_active') is distinct from 'boolean' then
    raise exception 'invalid_promo' using errcode = 'PT400', detail = 'is_active';
  end if;

  if coalesce(p_create, false) then
    if v_exp is not null and v_exp <= now() then
      raise exception 'invalid_promo' using errcode = 'PT400', detail = 'expires_at must be in the future';
    end if;
    insert into public.promo_codes (code, addon_code, days, max_redemptions, expires_at, is_active)
    values (v_code::extensions.citext, p_promo ->> 'addon_code', (p_promo ->> 'days')::int, v_max, v_exp,
            (p_promo ->> 'is_active')::boolean)
    on conflict (code) do nothing
    returning * into v_new;
    if v_new.code is null then raise exception 'promo_exists' using errcode = 'PT409'; end if;
    perform public._admin_audit('promo.create', 'promo_code', v_code, to_jsonb(v_new));
  else
    select * into v_old from public.promo_codes where code operator(extensions.=) v_code::extensions.citext for update;
    if not found then raise exception 'promo_not_found' using errcode = 'PT404'; end if;
    if v_max is not null and v_max < v_old.redeemed_count then
      raise exception 'invalid_promo' using errcode = 'PT400', detail = 'max_redemptions below redeemed_count';
    end if;
    update public.promo_codes set
      addon_code = p_promo ->> 'addon_code', days = (p_promo ->> 'days')::int, max_redemptions = v_max,
      expires_at = v_exp, is_active = (p_promo ->> 'is_active')::boolean
    where code operator(extensions.=) v_old.code
    returning * into v_new;
    perform public._admin_audit('promo.update', 'promo_code', v_code, public._jsonb_diff(to_jsonb(v_old), to_jsonb(v_new)));
  end if;
  return to_jsonb(v_new);
end $$;

create or replace function public.admin_delete_promo(p_code text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   public.promo_codes;
begin
  select * into v_old from public.promo_codes
   where code operator(extensions.=) btrim(coalesce(p_code, ''))::extensions.citext for update;
  if not found then raise exception 'promo_not_found' using errcode = 'PT404'; end if;
  if v_old.redeemed_count > 0 then
    raise exception 'promo_in_use' using errcode = 'PT409', hint = 'Deactivate it instead to keep redemption history';
  end if;
  delete from public.promo_codes where code operator(extensions.=) v_old.code;
  perform public._admin_audit('promo.delete', 'promo_code', v_old.code::text, to_jsonb(v_old));
end $$;

-- ===========================================================================
-- Remote config (admin)
-- ===========================================================================
create or replace function public.admin_list_config()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public._console_assert_admin();
  return (select coalesce(jsonb_agg(to_jsonb(c) order by c.key), '[]'::jsonb) from public.app_config c);
end $$;

-- Upsert one key. p_expected_updated_at enables optimistic concurrency: the
-- save fails with PT409 when someone changed the row since it was loaded.
create or replace function public.admin_set_config(
  p_key text, p_value jsonb, p_description text default null, p_is_public boolean default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := public._console_assert_admin();
  v_old   public.app_config;
  v_new   public.app_config;
  v_err   text;
begin
  if coalesce(p_key, '') !~ '^[a-z][a-z0-9_]{1,63}$' then raise exception 'invalid_key' using errcode = 'PT400'; end if;
  if p_value is null then raise exception 'invalid_value' using errcode = 'PT400', detail = 'value is required'; end if;
  if pg_column_size(p_value) > 65536 then raise exception 'invalid_value' using errcode = 'PT400', detail = 'value too large'; end if;
  if p_description is not null and char_length(p_description) > 300 then
    raise exception 'invalid_value' using errcode = 'PT400', detail = 'description too long';
  end if;
  v_err := public._admin_config_error(p_key, p_value);
  if v_err is not null then raise exception 'invalid_value' using errcode = 'PT400', detail = v_err; end if;

  select * into v_old from public.app_config where key = p_key for update;
  if found then
    if p_expected_updated_at is not null and v_old.updated_at <> p_expected_updated_at then
      raise exception 'config_conflict' using errcode = 'PT409', detail = 'changed by someone else; reload';
    end if;
    update public.app_config set
      value = p_value,
      description = coalesce(p_description, description),
      is_public = coalesce(p_is_public, is_public)
    where key = p_key
    returning * into v_new;
    perform public._admin_audit('config.update', 'app_config', p_key,
      public._jsonb_diff(to_jsonb(v_old) - 'updated_at', to_jsonb(v_new) - 'updated_at'));
  else
    insert into public.app_config (key, value, description, is_public)
    values (p_key, p_value, p_description, coalesce(p_is_public, true))
    returning * into v_new;
    perform public._admin_audit('config.create', 'app_config', p_key, to_jsonb(v_new) - 'updated_at');
  end if;
  return to_jsonb(v_new);
end $$;

-- ===========================================================================
-- Broadcast (admin): one set-based insert, locale-aware push, rate-limited.
-- ===========================================================================
create or replace function public.admin_broadcast_segments()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public._console_assert_admin();
  return jsonb_build_object(
    'total', (select count(*) from public.profiles where not is_banned),
    'districts', (select coalesce(jsonb_agg(jsonb_build_object('district', d.district, 'users', d.n)
                                            order by d.n desc, d.district), '[]'::jsonb)
                    from (select district, count(*) n from public.profiles
                           where not is_banned and nullif(btrim(district), '') is not null group by district) d),
    'target_exams', (select coalesce(jsonb_agg(jsonb_build_object('code', e.code, 'name_en', e.name_en,
                                                                  'users', (select count(*) from public.profiles p
                                                                             where not p.is_banned and p.target_exams @> array[e.code]))
                                               order by e.sort), '[]'::jsonb)
                       from public.exam_types e),
    'locales', (select coalesce(jsonb_object_agg(l.locale, l.n), '{}'::jsonb)
                  from (select locale, count(*) n from public.profiles where not is_banned group by locale) l));
end $$;

-- p_segment: {"target_exam"?: code, "district"?: text, "locale"?: "bn"|"en", "active_days"?: 1-365}
-- p_dry_run = true only counts recipients. p_client_key makes a send idempotent.
create or replace function public.admin_broadcast(
  p_title text, p_body text, p_title_en text default null, p_body_en text default null,
  p_route text default null, p_segment jsonb default '{}'::jsonb, p_send_push boolean default true,
  p_dry_run boolean default false, p_client_key uuid default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor    uuid := public._console_assert_admin();
  v_seg      jsonb := coalesce(p_segment, '{}'::jsonb);
  v_title    text := btrim(coalesce(p_title, ''));
  v_body     text := btrim(coalesce(p_body, ''));
  v_title_en text := nullif(btrim(coalesce(p_title_en, '')), '');
  v_body_en  text := nullif(btrim(coalesce(p_body_en, '')), '');
  v_route    text := nullif(btrim(coalesce(p_route, '')), '');
  v_exam     text;
  v_district text;
  v_locale   text;
  v_days     int;
  v_data     jsonb;
  v_n        int;
  v_push     int;
begin
  if char_length(v_title) not between 1 and 120 then raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'title: 1-120 characters'; end if;
  if char_length(v_body) not between 1 and 1000 then raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'body: 1-1000 characters'; end if;
  if char_length(coalesce(v_title_en, '')) > 120 or char_length(coalesce(v_body_en, '')) > 1000 then
    raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'english text too long';
  end if;
  if (v_title_en is null) <> (v_body_en is null) then
    raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'give both English title and body, or neither';
  end if;
  if v_route is not null and (v_route !~ '^/[A-Za-z0-9/_\-]*(\?[A-Za-z0-9=&_\-]*)?$' or char_length(v_route) > 200) then
    raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'route must be an app path like /notes';
  end if;
  if jsonb_typeof(v_seg) <> 'object'
     or exists (select 1 from jsonb_object_keys(v_seg) k where k not in ('target_exam', 'district', 'locale', 'active_days')) then
    raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'segment';
  end if;
  v_exam := nullif(btrim(coalesce(v_seg ->> 'target_exam', '')), '');
  if v_exam is not null and not exists (select 1 from public.exam_types where code = v_exam) then
    raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'target_exam';
  end if;
  v_district := nullif(btrim(coalesce(v_seg ->> 'district', '')), '');
  if v_district is not null and char_length(v_district) > 60 then
    raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'district';
  end if;
  v_locale := nullif(v_seg ->> 'locale', '');
  if v_locale is not null and v_locale not in ('bn', 'en') then
    raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'locale';
  end if;
  if nullif(v_seg ->> 'active_days', '') is not null then
    if (v_seg ->> 'active_days') !~ '^\d{1,3}$' or (v_seg ->> 'active_days')::int not between 1 and 365 then
      raise exception 'invalid_broadcast' using errcode = 'PT400', detail = 'active_days: 1-365';
    end if;
    v_days := (v_seg ->> 'active_days')::int;
  end if;

  if coalesce(p_dry_run, false) then
    select count(*), count(*) filter (where t.wants_push) into v_n, v_push
      from public._admin_broadcast_targets(v_exam, v_district, v_locale, v_days) t;
    return jsonb_build_object('dry_run', true, 'recipients', v_n,
                              'pushes', case when coalesce(p_send_push, true) then v_push else 0 end);
  end if;

  if p_client_key is not null and not public.claim_pipeline_run('admin_broadcast:' || p_client_key::text) then
    raise exception 'duplicate_broadcast' using errcode = 'PT409';
  end if;
  perform public.enforce_rate_limit('admin_broadcast', 5, 3600);

  v_data := jsonb_build_object('broadcast', true)
            || case when v_route is not null then jsonb_build_object('route', v_route) else '{}'::jsonb end;
  with targets as (
    select * from public._admin_broadcast_targets(v_exam, v_district, v_locale, v_days)
  ), n as (
    insert into public.notifications (user_id, type, title, body, title_en, body_en, data)
    select t.id, 'announcement', v_title, v_body, v_title_en, v_body_en, v_data from targets t
    returning 1
  ), q as (
    insert into public.push_outbox (user_id, title, body, data)
    select t.id,
           case when t.locale = 'en' and v_title_en is not null then v_title_en else v_title end,
           case when t.locale = 'en' and v_body_en is not null then v_body_en else v_body end,
           v_data || jsonb_build_object('type', 'announcement')
      from targets t
     where coalesce(p_send_push, true) and t.wants_push
    returning 1
  )
  select (select count(*) from n), (select count(*) from q) into v_n, v_push;

  perform public._admin_audit('broadcast.send', 'broadcast', p_client_key::text,
                              jsonb_build_object('title', v_title, 'body', v_body, 'title_en', v_title_en,
                                                 'body_en', v_body_en, 'route', v_route, 'segment', v_seg,
                                                 'recipients', v_n, 'pushes', v_push));
  return jsonb_build_object('dry_run', false, 'recipients', v_n, 'pushes', v_push);
end $$;

-- ===========================================================================
-- Monitoring: client errors (table from 0019) grouped by fingerprint.
-- `events` counts occurrences (0019 merges repeats within an hour per user).
-- ===========================================================================
create or replace function public.admin_list_client_errors(
  p_hours int default 24, p_platform text default null, p_fatal_only boolean default false,
  p_search text default null, p_limit int default 50,
  p_after_last_seen timestamptz default null, p_after_fingerprint text default null
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_hours int := coalesce(p_hours, 24);
  v_q     text := nullif(btrim(p_search), '');
begin
  perform public._console_assert_admin();
  if v_hours not between 1 and 720 then raise exception 'invalid_hours' using errcode = 'PT400'; end if;
  if v_q is not null and char_length(v_q) > 200 then raise exception 'search_too_long' using errcode = 'PT400'; end if;
  if (p_after_last_seen is null) <> (p_after_fingerprint is null) then
    raise exception 'invalid_cursor' using errcode = 'PT400';
  end if;
  if to_regclass('public.client_errors') is null then return '[]'::jsonb; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'fingerprint', g.fp, 'events', g.events, 'reports', g.reports, 'users', g.users,
             'first_seen', g.first_seen, 'last_seen', g.last_seen, 'fatal', g.fatal,
             'platforms', to_jsonb(g.platforms), 'versions', to_jsonb(g.versions), 'error', g.error,
             'route', g.route, 'app_version', g.app_version)
             order by g.last_seen desc, g.fp desc), '[]'::jsonb)
      from (select a.* from (
              select e.fingerprint as fp,
                     sum(e.occurrences) as events, count(*) as reports, count(distinct e.user_id) as users,
                     min(e.created_at) as first_seen, max(e.last_seen_at) as last_seen,
                     bool_or(e.fatal) as fatal,
                     array_agg(distinct e.platform) filter (where e.platform is not null) as platforms,
                     (array_agg(distinct e.app_version) filter (where e.app_version is not null))[1:5] as versions,
                     (array_agg(left(e.error, 500) order by e.last_seen_at desc))[1] as error,
                     (array_agg(e.route order by e.last_seen_at desc))[1] as route,
                     (array_agg(e.app_version order by e.last_seen_at desc))[1] as app_version
                from public.client_errors e
               -- created_at is indexed; merged repeats stay within one hour of it
               where e.created_at >= now() - make_interval(hours => v_hours + 1)
                 and e.last_seen_at >= now() - make_interval(hours => v_hours)
                 and (p_platform is null or e.platform = p_platform)
                 and (not coalesce(p_fatal_only, false) or e.fatal)
                 and (v_q is null or e.error ilike public._like_pattern(v_q)
                      or e.fingerprint = v_q or e.route ilike public._like_pattern(v_q))
               group by e.fingerprint) a
             where p_after_last_seen is null or (a.last_seen, a.fp) < (p_after_last_seen, p_after_fingerprint)
             order by a.last_seen desc, a.fp desc
             limit least(greatest(coalesce(p_limit, 50), 1), 200)) g);
end $$;

-- Individual reports of one fingerprint, newest first (keyset on created_at, id).
create or replace function public.admin_client_error_events(
  p_fingerprint text, p_limit int default 20,
  p_before_created timestamptz default null, p_before_id bigint default null
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public._console_assert_admin();
  if p_fingerprint is null or char_length(p_fingerprint) > 64 then
    raise exception 'invalid_fingerprint' using errcode = 'PT400';
  end if;
  if (p_before_created is null) <> (p_before_id is null) then
    raise exception 'invalid_cursor' using errcode = 'PT400';
  end if;
  if to_regclass('public.client_errors') is null then return '[]'::jsonb; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', e.id, 'created_at', e.created_at, 'last_seen_at', e.last_seen_at, 'occurrences', e.occurrences,
             'user_id', e.user_id, 'username', p.username, 'app_version', e.app_version,
             'build_number', e.build_number, 'platform', e.platform, 'os', e.os, 'locale', e.locale,
             'route', e.route, 'context', e.context, 'error', e.error, 'stack', e.stack, 'fatal', e.fatal,
             'fingerprint', e.fingerprint)
             order by e.created_at desc, e.id desc), '[]'::jsonb)
      from (select * from public.client_errors x
             where x.fingerprint = p_fingerprint
               and (p_before_created is null or (x.created_at, x.id) < (p_before_created, p_before_id))
             order by x.created_at desc, x.id desc
             limit least(greatest(coalesce(p_limit, 20), 1), 100)) e
      left join public.profiles p on p.id = e.user_id);
end $$;

-- ---------------------------------------------------------------------------
-- Privileges: console RPCs are for signed-in users only (the functions
-- themselves check the role).
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.admin_console_stats()',
    'public.admin_ai_usage_summary(int)',
    'public.admin_list_users(text, text, boolean, int, timestamptz, uuid)',
    'public.admin_get_user(uuid)',
    'public.admin_change_role(uuid, text)',
    'public.admin_set_ban(uuid, boolean, text)',
    'public.admin_user_grant_addon(uuid, text, int)',
    'public.admin_revoke_entitlement(bigint, text)',
    'public.admin_reset_onboarding(uuid, text)',
    'public.admin_search_questions(smallint, int, text, text, text, text, bigint, text, int, bigint)',
    'public.admin_get_question(bigint)',
    'public.admin_save_question(bigint, jsonb)',
    'public.admin_set_question_status(bigint[], text, text)',
    'public.admin_find_duplicate_questions(text[])',
    'public.admin_import_questions(jsonb, text, text)',
    'public.admin_export_questions(smallint, int, text, text, text, text, bigint, text, int, bigint)',
    'public.admin_moderate_report(bigint, text, text)',
    'public.admin_get_report_target(text, text)',
    'public.admin_list_note_days(date, int)',
    'public.admin_list_notes(date)',
    'public.admin_update_note(bigint, jsonb)',
    'public.admin_delete_note(bigint)',
    'public.admin_get_daily_exam(date)',
    'public.admin_list_news_sources()',
    'public.admin_save_news_source(smallint, jsonb)',
    'public.admin_trigger_pipeline(text)',
    'public.admin_pipeline_result(bigint)',
    'public.admin_list_schedules()',
    'public.admin_save_schedule(bigint, jsonb)',
    'public.admin_delete_schedule(bigint)',
    'public.admin_list_exam_tracks()',
    'public.admin_save_exam_track(text, jsonb)',
    'public.admin_list_addons()',
    'public.admin_save_addon(text, jsonb, boolean)',
    'public.admin_save_feature(text, jsonb)',
    'public.admin_list_promos(text, int, timestamptz, text)',
    'public.admin_save_promo(text, jsonb, boolean)',
    'public.admin_delete_promo(text)',
    'public.admin_list_config()',
    'public.admin_set_config(text, jsonb, text, boolean, timestamptz)',
    'public.admin_broadcast_segments()',
    'public.admin_broadcast(text, text, text, text, text, jsonb, boolean, boolean, uuid)',
    'public.admin_list_client_errors(int, text, boolean, text, int, timestamptz, text)',
    'public.admin_client_error_events(text, int, timestamptz, bigint)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
