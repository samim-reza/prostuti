-- ============================================================================
-- 0018 · Daily AI advice ("প্রস্তুতি এআই-এর পরামর্শ")
--
-- The study plan used to carry tips written ONCE when the plan was created.
-- Advice is now fresh every Bangladesh day and built from the learner's data:
--
-- • ai_daily_advice        one row per learner · BD day · language, written
--                          only by the `daily-advice` Edge Function (service
--                          role). Owners can read their own rows.
-- • daily_advice_signals() everything the advice is based on, in one call
--                          (weak topics, last-7-day exams/practice/routine,
--                          streak, days left, today's routine/notes/daily
--                          exam). Service role only.
-- • get_daily_advice()     the client's fast path: today's row or null.
-- • purge_daily_advice()   nightly: rows older than 14 days are deleted.
-- ============================================================================

-- Functions may reference tables created by other migrations.
set check_function_bodies = off;

create table public.ai_daily_advice (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  advice_date date not null default public.bd_today(),
  locale      text not null check (locale in ('bn', 'en')),
  -- [{ "title": text, "body": text, "action_route"?: text }]
  tips        jsonb not null default '[]'::jsonb check (jsonb_typeof(tips) = 'array'),
  -- the signals the tips were built from (+ signature, source: ai|cache|fallback)
  stats       jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  primary key (user_id, advice_date, locale)
);
create index ai_daily_advice_date_idx on public.ai_daily_advice (advice_date);
alter table public.ai_daily_advice enable row level security;
create policy "ai_daily_advice: owner reads" on public.ai_daily_advice for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete on public.ai_daily_advice from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Signals for one learner. Every lookup is an indexed range on the user's own
-- rows (mastery by (user_id, mastery), sessions/attempts by (user_id,
-- created_at), plan days by (plan_id, day_date)), so it stays cheap however
-- large the tables grow. Returns null for an unknown user.
-- ---------------------------------------------------------------------------
create or replace function public.daily_advice_signals(p_user uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  with bd as (
    select public.bd_today() as today,
           (public.bd_today() - 6)::timestamp at time zone 'Asia/Dhaka'  as since7,
           (public.bd_today() - 13)::timestamp at time zone 'Asia/Dhaka' as since14
  ), prof as (
    select p.id, p.locale, p.streak_count, p.longest_streak, p.last_active_date, p.target_schedule_id
      from public.profiles p
     where p.id = p_user
  ), plan as (
    select sp.id, sp.exam_date
      from public.study_plans sp
     where sp.user_id = p_user and sp.status = 'active'
  ), weak as (
    -- Ties (placement priors are equal within a subject) break by weight and
    -- id, so the same data always yields the same topics (stable signature).
    select m.topic_id, t.name_bn, t.name_en, s.name_bn as subject_bn, s.name_en as subject_en,
           round(m.mastery * 100)::int as mastery, m.attempts, m.is_prior,
           row_number() over (order by m.mastery, m.attempts desc, t.weight desc, t.id) as rank
      from public.user_topic_mastery m
      join public.topics t on t.id = m.topic_id
      join public.subjects s on s.id = t.subject_id
     where m.user_id = p_user and s.bcs_marks > 0
     order by m.mastery, m.attempts desc, t.weight desc, t.id
     limit 3
  ), ex as (
    select count(*) filter (where es.submitted_at >= bd.since7)                                as exams_7d,
           sum(es.correct) filter (where es.submitted_at >= bd.since7)                         as c7,
           sum(coalesce(es.correct, 0) + coalesce(es.wrong, 0)) filter (where es.submitted_at >= bd.since7) as a7,
           sum(es.correct) filter (where es.submitted_at < bd.since7)                          as cp,
           sum(coalesce(es.correct, 0) + coalesce(es.wrong, 0)) filter (where es.submitted_at < bd.since7)  as ap
      from public.exam_sessions es, bd
     where es.user_id = p_user
       and es.created_at >= bd.since14 - interval '1 day'   -- index range; sessions last hours
       and es.status = 'submitted' and es.kind <> 'placement'
       and es.submitted_at >= bd.since14
  ), att as (
    select count(*) filter (where a.mode = 'practice')                                   as practice_7d,
           count(*) filter (where a.is_correct = false and a.mode in ('exam', 'practice')) as wrong_7d
      from public.question_attempts a, bd
     where a.user_id = p_user and a.created_at >= bd.since7
  ), routine as (
    select count(*)                                   as days,
           count(*) filter (where d.status = 'done')  as done_days,
           coalesce(sum(d.completed_items), 0)        as completed_items,
           coalesce(sum(d.total_items), 0)            as total_items
      from public.study_plan_days d
      join plan p on p.id = d.plan_id, bd
     where d.day_date between bd.today - 7 and bd.today - 1 and d.kind <> 'rest'
  ), today_day as (
    select d.id, d.kind, d.status, d.completed_items, d.total_items,
           (select bool_or(coalesce((it ->> 'done')::boolean, false))
              from jsonb_array_elements(d.items) it
             where it ->> 'route' = '/notes') as notes_done
      from public.study_plan_days d
      join plan p on p.id = d.plan_id, bd
     where d.day_date = bd.today
  ), dx as (
    select e.id
      from public.daily_exams e, bd
     where e.exam_date = bd.today and e.status = 'published'
  ), target as (
    select coalesce(
             (select p.exam_date from plan p),
             (select s.expected_date from public.exam_schedules s join prof on s.id = prof.target_schedule_id),
             (select s.expected_date from public.exam_schedules s
               where s.id = (select case when (c.value #>> '{}') ~ '^\d+$' then (c.value #>> '{}')::bigint end
                               from public.app_config c where c.key = 'default_schedule_id'))
           ) as exam_date
  )
  select jsonb_build_object(
    'date', bd.today,
    'locale', prof.locale,
    'has_data', exists (select 1 from public.user_topic_mastery where user_id = p_user)
                or exists (select 1 from plan)
                or exists (select 1 from public.question_attempts where user_id = p_user)
                or exists (select 1 from public.exam_sessions where user_id = p_user and status = 'submitted'),
    'weak_topics', coalesce((select jsonb_agg(to_jsonb(w) - 'rank' order by w.rank) from weak w), '[]'::jsonb),
    'exams_7d', ex.exams_7d,
    'accuracy_7d', case when ex.a7 > 0 then round(100.0 * ex.c7 / ex.a7)::int end,
    'accuracy_prev_7d', case when ex.ap > 0 then round(100.0 * ex.cp / ex.ap)::int end,
    'practice_7d', att.practice_7d,
    'wrong_7d', att.wrong_7d,
    'routine_7d', jsonb_build_object('days', routine.days, 'done_days', routine.done_days,
                                     'completed_items', routine.completed_items,
                                     'total_items', routine.total_items),
    'streak', case when prof.last_active_date >= bd.today - 1 then prof.streak_count else 0 end,
    'longest_streak', prof.longest_streak,
    'active_today', prof.last_active_date = bd.today,
    'days_left', (select t.exam_date - bd.today from target t),
    'has_plan', exists (select 1 from plan),
    'today', (select jsonb_build_object('day_id', t.id, 'kind', t.kind, 'status', t.status,
                                        'completed_items', t.completed_items, 'total_items', t.total_items,
                                        'notes_done', t.notes_done)
                from today_day t),
    'notes_available', exists (select 1 from public.daily_notes n
                                where n.note_date = bd.today and n.status = 'published'),
    'daily_exam_available', exists (select 1 from dx),
    'daily_exam_done', exists (select 1 from public.exam_sessions es
                                where es.user_id = p_user and es.daily_exam_id = (select id from dx)
                                  and es.status = 'submitted'),
    'daily_exam_unlocked', public.user_has_feature(p_user, 'daily_exam'))
    from bd, prof, ex, att, routine;
$$;
revoke execute on function public.daily_advice_signals(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Client fast path: today's advice in the requested language, or null (the
-- app then calls the `daily-advice` function once). RLS: own rows only.
-- ---------------------------------------------------------------------------
create or replace function public.get_daily_advice(p_locale text default 'bn')
returns jsonb
language sql stable security invoker
set search_path = ''
as $$
  select jsonb_build_object('advice_date', a.advice_date, 'locale', a.locale, 'tips', a.tips,
                            'stats', a.stats, 'created_at', a.created_at)
    from public.ai_daily_advice a
   where a.user_id = (select auth.uid())
     and a.advice_date = public.bd_today()
     and a.locale = case when p_locale = 'en' then 'en' else 'bn' end;
$$;
revoke execute on function public.get_daily_advice(text) from public, anon;
grant execute on function public.get_daily_advice(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Housekeeping: advice is only ever shown for "today"; keep two weeks for
-- support/debugging. Own cron job so the shared housekeeping() stays as is.
-- ---------------------------------------------------------------------------
create or replace function public.purge_daily_advice()
returns void
language sql security definer
set search_path = ''
as $$
  delete from public.ai_daily_advice where advice_date < public.bd_today() - 14;
$$;
revoke execute on function public.purge_daily_advice() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'prostuti-daily-advice-purge') then
    perform cron.unschedule('prostuti-daily-advice-purge');
  end if;
end $$;
-- 00:20 BD (18:20 UTC), after the nightly rollover.
select cron.schedule('prostuti-daily-advice-purge', '20 18 * * *', $$select public.purge_daily_advice()$$);
