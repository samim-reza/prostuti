-- ============================================================================
-- 0006 · Exam engine, topic mastery & readiness
--
-- start_exam   → server picks questions (no answers sent), creates a session
-- submit_exam  → server scores (BCS rule: −0.5 per wrong answer), records
--                attempts, updates topic mastery (EMA), streak and readiness
-- get_exam_review → answers + explanations, only after submission
-- ============================================================================

-- Functions may reference tables created by later migrations.
set check_function_bodies = off;

create table public.exam_sessions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.profiles (id) on delete cascade,
  kind               text not null check (kind in ('placement', 'model_test', 'daily', 'subject', 'topic',
                                                   'weak_topic', 'previous_year', 'custom')),
  title              text not null,
  daily_exam_id      bigint references public.daily_exams (id) on delete set null,
  config             jsonb not null default '{}'::jsonb,
  question_ids       bigint[] not null,
  duration_seconds   int not null check (duration_seconds > 0),
  negative_mark      numeric(3, 2) not null default 0.5,
  status             text not null default 'in_progress' check (status in ('in_progress', 'submitted', 'expired')),
  started_at         timestamptz not null default now(),
  deadline_at        timestamptz not null,
  submitted_at       timestamptz,
  answers            jsonb,
  total              int not null,
  correct            int,
  wrong              int,
  skipped            int,
  score              numeric(6, 2),
  max_score          numeric(6, 2),
  per_subject        jsonb,
  time_taken_seconds int,
  created_at         timestamptz not null default now()
);
create unique index exam_sessions_daily_once on public.exam_sessions (user_id, daily_exam_id) where daily_exam_id is not null;
create index exam_sessions_user_idx  on public.exam_sessions (user_id, created_at desc);
create index exam_sessions_daily_idx on public.exam_sessions (daily_exam_id, score desc, time_taken_seconds) where status = 'submitted';
create index exam_sessions_stale_idx on public.exam_sessions (deadline_at) where status = 'in_progress';
alter table public.exam_sessions enable row level security;
create policy "exam_sessions: owner reads" on public.exam_sessions for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete on public.exam_sessions from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Mastery model
-- ---------------------------------------------------------------------------
create table public.user_topic_mastery (
  user_id           uuid not null references public.profiles (id) on delete cascade,
  topic_id          int not null references public.topics (id) on delete cascade,
  mastery           real not null default 0.15 check (mastery between 0 and 1),
  attempts          int not null default 0,
  correct           int not null default 0,
  is_prior          boolean not null default true,
  last_practiced_at timestamptz,
  updated_at        timestamptz not null default now(),
  primary key (user_id, topic_id)
);
create index user_topic_mastery_weak_idx on public.user_topic_mastery (user_id, mastery);
alter table public.user_topic_mastery enable row level security;
create policy "user_topic_mastery: owner reads" on public.user_topic_mastery for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete on public.user_topic_mastery from anon, authenticated;

create table public.user_subject_levels (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  subject_id  smallint not null references public.subjects (id) on delete cascade,
  score_pct   real not null,
  level       text not null check (level in ('beginner', 'intermediate', 'advanced')),
  assessed_at timestamptz not null default now(),
  primary key (user_id, subject_id)
);
alter table public.user_subject_levels enable row level security;
create policy "user_subject_levels: owner reads" on public.user_subject_levels for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete on public.user_subject_levels from anon, authenticated;

create table public.readiness_snapshots (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  snap_date   date not null,
  readiness   int not null,
  coverage    int not null,
  per_subject jsonb not null default '[]'::jsonb,
  primary key (user_id, snap_date)
);
alter table public.readiness_snapshots enable row level security;
create policy "readiness_snapshots: owner reads" on public.readiness_snapshots for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete on public.readiness_snapshots from anon, authenticated;

-- Exponential moving average: mastery += α · (outcome − mastery)
create or replace function public.update_mastery(p_user uuid, p_topic int, p_correct boolean, p_alpha real)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_outcome real := case when p_correct then 1 else 0 end;
begin
  if p_topic is null or p_user is null then return; end if;
  insert into public.user_topic_mastery as m (user_id, topic_id, mastery, attempts, correct, is_prior, last_practiced_at)
  values (p_user, p_topic, 0.15 + p_alpha * (v_outcome - 0.15), 1, v_outcome::int, false, now())
  on conflict (user_id, topic_id) do update
     set mastery = least(1, greatest(0, m.mastery + p_alpha * (v_outcome - m.mastery))),
         attempts = m.attempts + 1,
         correct = m.correct + v_outcome::int,
         is_prior = false,
         last_practiced_at = now(),
         updated_at = now();
end $$;
revoke execute on function public.update_mastery(uuid, int, boolean, real) from public, anon, authenticated;

create or replace function public.compute_readiness(p_user uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  with t as (
    select s.id as subject_id, s.code, s.name_bn, s.name_en, s.bcs_marks, s.color, tp.weight,
           coalesce(m.mastery, 0.15) as mastery, coalesce(m.attempts, 0) as attempts
      from public.subjects s
      join public.topics tp on tp.subject_id = s.id
      left join public.user_topic_mastery m on m.topic_id = tp.id and m.user_id = p_user
     where s.bcs_marks > 0
  ), subj as (
    select subject_id, code, name_bn, name_en, bcs_marks, color,
           sum(weight * mastery) / sum(weight) as mastery,
           (count(*) filter (where attempts > 0))::real / count(*) as coverage
      from t group by subject_id, code, name_bn, name_en, bcs_marks, color
  )
  select jsonb_build_object(
    'readiness', round(((sum(bcs_marks * mastery) / sum(bcs_marks)) * 0.85
                       + (sum(bcs_marks * coverage) / sum(bcs_marks)) * 0.15) * 100)::int,
    'coverage', round(sum(bcs_marks * coverage) / sum(bcs_marks) * 100)::int,
    'estimated_score', round(sum(bcs_marks * mastery))::int,
    'subjects', jsonb_agg(jsonb_build_object(
                  'subject_id', subject_id, 'code', code, 'name_bn', name_bn, 'name_en', name_en,
                  'color', color, 'marks', bcs_marks,
                  'mastery', round(mastery * 100)::int, 'coverage', round(coverage * 100)::int)
                order by bcs_marks desc, subject_id))
    from subj;
$$;
revoke execute on function public.compute_readiness(uuid) from public, anon, authenticated;

create or replace function public.snapshot_readiness(p_user uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v jsonb := public.compute_readiness(p_user);
begin
  insert into public.readiness_snapshots (user_id, snap_date, readiness, coverage, per_subject)
  values (p_user, public.bd_today(), (v ->> 'readiness')::int, (v ->> 'coverage')::int, v -> 'subjects')
  on conflict (user_id, snap_date) do update
     set readiness = excluded.readiness, coverage = excluded.coverage, per_subject = excluded.per_subject;
end $$;
revoke execute on function public.snapshot_readiness(uuid) from public, anon, authenticated;

create or replace function public.get_readiness()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select public.compute_readiness(auth.uid()) || jsonb_build_object(
    'history', coalesce((select jsonb_agg(jsonb_build_object('date', snap_date, 'readiness', readiness) order by snap_date)
                           from (select * from public.readiness_snapshots
                                  where user_id = auth.uid() order by snap_date desc limit 60) h), '[]'::jsonb),
    'levels', coalesce((select jsonb_agg(jsonb_build_object('subject_id', l.subject_id, 'level', l.level,
                                                            'score_pct', l.score_pct))
                          from public.user_subject_levels l where l.user_id = auth.uid()), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- Question picking: unseen first, then random. Never today's daily-exam items.
-- ---------------------------------------------------------------------------
create or replace function public.pick_questions(
  p_user uuid, p_subjects smallint[], p_topics int[], p_count int, p_exclude bigint[]
)
returns bigint[]
language sql volatile security definer
set search_path = ''
as $$
  select coalesce(array_agg(id), '{}') from (
    select q.id
      from public.questions q
     where q.status = 'published'
       and (p_subjects is null or q.subject_id = any (p_subjects))
       and (p_topics is null or q.topic_id = any (p_topics))
       and not (q.id = any (coalesce(p_exclude, '{}')))
       and not exists (select 1 from public.daily_exams d
                        where d.exam_date = public.bd_today() and q.id = any (d.question_ids))
     order by exists (select 1 from public.question_attempts a
                       where a.user_id = p_user and a.question_id = q.id), random()
     limit greatest(p_count, 0)
  ) s;
$$;
revoke execute on function public.pick_questions(uuid, smallint[], int[], int, bigint[]) from public, anon, authenticated;

create or replace function public.exam_payload(p_session uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'session_id', s.id, 'kind', s.kind, 'title', s.title, 'status', s.status,
    'started_at', s.started_at, 'deadline_at', s.deadline_at,
    'duration_seconds', s.duration_seconds, 'negative_mark', s.negative_mark, 'total', s.total,
    'config', s.config,
    'questions', (select coalesce(jsonb_agg(public.question_public_json(q)
                                            order by array_position(s.question_ids, q.id)), '[]'::jsonb)
                    from public.questions q where q.id = any (s.question_ids)))
    from public.exam_sessions s
   where s.id = p_session and s.user_id = auth.uid();
$$;

create or replace function public.start_exam(p_kind text, p_config jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_ids     bigint[] := '{}';
  v_title   text;
  v_secs    int;
  v_neg     numeric := 0.5;
  v_daily   public.daily_exams;
  v_session uuid;
  v_status  text;
  v_size    int;
  v_count   int := least(greatest(coalesce((p_config ->> 'count')::int, 20), 5), 100);
  v_topics  int[];
  r         record;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  perform public.enforce_rate_limit('exam_start', 40, 3600);

  case p_kind
  when 'placement' then
    v_title := 'লেভেল নির্ধারণী পরীক্ষা';
    for r in select placement_group, array_agg(id) as subj
               from public.subjects where placement_group is not null
              group by placement_group order by placement_group loop
      v_ids := v_ids || public.pick_questions(v_uid, r.subj, null, 10, v_ids);
    end loop;
    v_secs := 25 * 60;

  when 'model_test' then
    perform public.require_feature('model_test');
    v_size := coalesce((p_config ->> 'size')::int, 100);
    if v_size not in (25, 50, 100, 200) then v_size := 100; end if;
    v_title := 'মডেল টেস্ট · ' || v_size || ' নম্বর';
    for r in select id, bcs_marks from public.subjects where bcs_marks > 0 order by sort loop
      v_ids := v_ids || public.pick_questions(v_uid, array[r.id], null,
                                              greatest(round(r.bcs_marks * v_size / 200.0)::int, 1), v_ids);
    end loop;
    v_secs := ceil(cardinality(v_ids) * 36);  -- BCS pace: 200 questions in 120 minutes

  when 'subject' then
    select 'বিষয়ভিত্তিক পরীক্ষা · ' || name_bn into v_title
      from public.subjects where id = (p_config ->> 'subject_id')::smallint;
    if v_title is null then raise exception 'subject_not_found' using errcode = 'PT404'; end if;
    v_ids := public.pick_questions(v_uid, array[(p_config ->> 'subject_id')::smallint], null, v_count, '{}');
    v_secs := greatest(cardinality(v_ids) * 36, 300);

  when 'topic' then
    select 'টপিকভিত্তিক পরীক্ষা · ' || name_bn into v_title
      from public.topics where id = (p_config ->> 'topic_id')::int;
    if v_title is null then raise exception 'topic_not_found' using errcode = 'PT404'; end if;
    v_ids := public.pick_questions(v_uid, null, array[(p_config ->> 'topic_id')::int], v_count, '{}');
    v_secs := greatest(cardinality(v_ids) * 36, 300);

  when 'weak_topic' then
    perform public.require_feature('smart_practice');
    select array_agg(topic_id) into v_topics from (
      select topic_id from public.user_topic_mastery
       where user_id = v_uid order by mastery asc, attempts desc limit 4) w;
    v_title := 'দুর্বল টপিক পরীক্ষা';
    v_ids := public.pick_questions(v_uid, null, v_topics, v_count, '{}');
    if cardinality(v_ids) < v_count then
      v_ids := v_ids || public.pick_questions(v_uid, null, null, v_count - cardinality(v_ids), v_ids);
    end if;
    v_secs := greatest(cardinality(v_ids) * 36, 300);

  when 'previous_year' then
    select coalesce(array_agg(q.id order by q.id), '{}'), max(s.name)
      into v_ids, v_title
      from public.questions q join public.sources s on s.id = q.source_id
     where q.source_id = (p_config ->> 'source_id')::bigint and q.status = 'published';
    v_ids := v_ids[1:200];
    v_secs := greatest(cardinality(v_ids) * 36, 300);

  when 'daily' then
    perform public.require_feature('daily_exam');
    select * into v_daily from public.daily_exams where exam_date = public.bd_today() and status = 'published';
    if not found then raise exception 'no_daily_exam' using errcode = 'PT404'; end if;
    select id, status into v_session, v_status from public.exam_sessions
     where user_id = v_uid and daily_exam_id = v_daily.id;
    if v_session is not null then
      if v_status = 'in_progress' then return public.exam_payload(v_session); end if;
      raise exception 'already_attempted' using errcode = 'PT409';
    end if;
    v_ids := v_daily.question_ids;
    v_title := v_daily.title_bn;
    v_secs := v_daily.duration_minutes * 60;
    v_neg := v_daily.negative_mark;

  when 'custom' then
    v_title := coalesce(nullif(p_config ->> 'title', ''), 'অনুশীলন পরীক্ষা');
    v_ids := public.pick_questions(
      v_uid,
      (select array_agg(x::smallint) from jsonb_array_elements_text(p_config -> 'subject_ids') x),
      (select array_agg(x::int) from jsonb_array_elements_text(p_config -> 'topic_ids') x),
      v_count, '{}');
    v_secs := greatest(cardinality(v_ids) * 36, 300);

  else
    raise exception 'invalid_exam_kind';
  end case;

  if coalesce(cardinality(v_ids), 0) = 0 then
    raise exception 'no_questions' using errcode = 'PT404';
  end if;

  insert into public.exam_sessions (user_id, kind, title, daily_exam_id, config, question_ids,
                                    duration_seconds, negative_mark, deadline_at, total)
  values (v_uid, p_kind, v_title, v_daily.id, coalesce(p_config, '{}'::jsonb), v_ids,
          v_secs, v_neg, now() + make_interval(secs => v_secs), cardinality(v_ids))
  returning id into v_session;

  return public.exam_payload(v_session);
end $$;

create or replace function public.exam_result_json(p_session uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'session_id', s.id, 'kind', s.kind, 'title', s.title, 'status', s.status,
    'score', s.score, 'max_score', s.max_score, 'correct', s.correct, 'wrong', s.wrong,
    'skipped', s.skipped, 'total', s.total, 'negative_mark', s.negative_mark,
    'time_taken_seconds', s.time_taken_seconds, 'submitted_at', s.submitted_at,
    'per_subject', (select coalesce(jsonb_agg(jsonb_build_object(
                       'subject_id', sub.id, 'name_bn', sub.name_bn, 'name_en', sub.name_en,
                       'total', (v ->> 'total')::int, 'correct', (v ->> 'correct')::int,
                       'wrong', (v ->> 'wrong')::int) order by sub.sort), '[]'::jsonb)
                      from jsonb_each(coalesce(s.per_subject, '{}'::jsonb)) e(k, v)
                      join public.subjects sub on sub.id = e.k::smallint),
    'rank', case when s.daily_exam_id is not null then (
               select count(*) + 1 from public.exam_sessions o
                where o.daily_exam_id = s.daily_exam_id and o.status = 'submitted'
                  and (o.score > s.score or (o.score = s.score and o.time_taken_seconds < s.time_taken_seconds)))
             end,
    'participants', case when s.daily_exam_id is not null then (
               select count(*) from public.exam_sessions o
                where o.daily_exam_id = s.daily_exam_id and o.status = 'submitted') end)
    from public.exam_sessions s
   where s.id = p_session and s.user_id = auth.uid();
$$;

create or replace function public.submit_exam(p_session uuid, p_answers jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_s     public.exam_sessions;
  v_per   jsonb;
  v_c     int;
  v_w     int;
  v_alpha real;
  r       record;
begin
  select * into v_s from public.exam_sessions where id = p_session and user_id = v_uid for update;
  if not found then raise exception 'session_not_found' using errcode = 'PT404'; end if;
  if v_s.status = 'submitted' then return public.exam_result_json(p_session); end if;
  if v_s.status = 'expired' then raise exception 'session_expired' using errcode = 'PT410'; end if;

  p_answers := coalesce(p_answers, '{}'::jsonb);
  v_alpha := case when v_s.kind = 'placement' then 0.35 else 0.25 end;

  -- Record every valid answer (out-of-range / non-numeric answers count as skipped).
  insert into public.question_attempts (user_id, question_id, session_id, selected_index, is_correct, mode)
  select v_uid, q.id, p_session, (p_answers ->> q.id::text)::smallint,
         (p_answers ->> q.id::text)::smallint = q.correct_index, 'exam'
    from public.questions q
   where q.id = any (v_s.question_ids)
     and jsonb_typeof(p_answers -> q.id::text) = 'number'
     and (p_answers ->> q.id::text)::numeric between 0 and jsonb_array_length(q.options) - 1;

  for r in select q.id, q.topic_id, a.is_correct
             from public.question_attempts a join public.questions q on q.id = a.question_id
            where a.session_id = p_session loop
    perform public.update_mastery(v_uid, r.topic_id, r.is_correct, v_alpha);
    update public.questions
       set times_answered = times_answered + 1, times_correct = times_correct + r.is_correct::int
     where id = r.id;
  end loop;

  select coalesce(jsonb_object_agg(subject_id, jsonb_build_object('total', total, 'correct', c, 'wrong', w)), '{}'::jsonb),
         coalesce(sum(c), 0), coalesce(sum(w), 0)
    into v_per, v_c, v_w
    from (select q.subject_id, count(*)::int as total,
                 (count(*) filter (where a.is_correct))::int as c,
                 (count(*) filter (where a.is_correct = false))::int as w
            from public.questions q
            left join public.question_attempts a on a.question_id = q.id and a.session_id = p_session
           where q.id = any (v_s.question_ids)
           group by q.subject_id) t;

  update public.exam_sessions
     set status = 'submitted', submitted_at = now(), answers = p_answers,
         correct = v_c, wrong = v_w, skipped = v_s.total - v_c - v_w,
         score = v_c - v_w * v_s.negative_mark, max_score = v_s.total, per_subject = v_per,
         time_taken_seconds = least(ceil(extract(epoch from now() - v_s.started_at))::int, v_s.duration_seconds + 60)
   where id = p_session;

  update public.profiles set exams_taken = exams_taken + 1 where id = v_uid;
  perform public.touch_streak(v_uid);

  if v_s.kind = 'placement' then
    perform public.apply_placement_result(v_uid, p_session);
  end if;
  if v_s.config ? 'plan_day_id' then
    perform public._complete_plan_item(v_uid, (v_s.config ->> 'plan_day_id')::bigint, v_s.config ->> 'plan_item_key');
  end if;
  perform public.snapshot_readiness(v_uid);

  return public.exam_result_json(p_session);
end $$;

-- Placement → per-subject level + mastery priors for every topic of the group.
create or replace function public.apply_placement_result(p_user uuid, p_session uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare r record;
begin
  for r in
    select s.placement_group,
           coalesce((count(*) filter (where a.is_correct))::real / nullif(count(*), 0), 0) as pct
      from public.exam_sessions es
      join public.questions q on q.id = any (es.question_ids)
      join public.subjects s on s.id = q.subject_id
      left join public.question_attempts a on a.question_id = q.id and a.session_id = es.id
     where es.id = p_session
     group by s.placement_group
  loop
    insert into public.user_subject_levels (user_id, subject_id, score_pct, level)
    select p_user, s.id, r.pct,
           case when r.pct >= 0.7 then 'advanced' when r.pct >= 0.4 then 'intermediate' else 'beginner' end
      from public.subjects s where s.placement_group = r.placement_group
    on conflict (user_id, subject_id) do update
       set score_pct = excluded.score_pct, level = excluded.level, assessed_at = now();

    insert into public.user_topic_mastery (user_id, topic_id, mastery, is_prior)
    select p_user, t.id, 0.1 + 0.7 * r.pct, true
      from public.topics t join public.subjects s on s.id = t.subject_id
     where s.placement_group = r.placement_group
    on conflict (user_id, topic_id) do update
       set mastery = excluded.mastery
     where public.user_topic_mastery.is_prior;
  end loop;

  update public.profiles set onboarding_step = 'plan'
   where id = p_user and onboarding_step in ('profile', 'interview', 'placement');
end $$;
revoke execute on function public.apply_placement_result(uuid, uuid) from public, anon, authenticated;

create or replace function public.get_exam_review(p_session uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(public.question_public_json(q) || jsonb_build_object(
           'correct_index', q.correct_index, 'explanation', q.explanation,
           'selected_index', case when jsonb_typeof(s.answers -> q.id::text) = 'number'
                                  then (s.answers ->> q.id::text)::int end)
         order by array_position(s.question_ids, q.id)), '[]'::jsonb)
    from public.exam_sessions s
    join public.questions q on q.id = any (s.question_ids)
   where s.id = p_session and s.user_id = auth.uid() and s.status = 'submitted';
$$;

create or replace function public.get_exam_history(p_limit int default 20, p_before timestamptz default null)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'session_id', s.id, 'kind', s.kind, 'title', s.title, 'score', s.score,
           'max_score', s.max_score, 'correct', s.correct, 'wrong', s.wrong, 'skipped', s.skipped,
           'total', s.total, 'submitted_at', s.submitted_at, 'time_taken_seconds', s.time_taken_seconds)
         order by s.submitted_at desc), '[]'::jsonb)
    from (select * from public.exam_sessions
           where user_id = auth.uid() and status = 'submitted'
             and (p_before is null or submitted_at < p_before)
           order by submitted_at desc
           limit least(coalesce(p_limit, 20), 50)) s;
$$;

-- Resume an unfinished exam after the app was killed.
create or replace function public.get_active_exam()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select public.exam_payload(id) from public.exam_sessions
   where user_id = auth.uid() and status = 'in_progress' and deadline_at > now()
   order by started_at desc limit 1;
$$;

create or replace function public.get_daily_leaderboard(p_date date default null, p_limit int default 50)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  with ranked as (
    select s.user_id, s.score, s.time_taken_seconds,
           rank() over (order by s.score desc, s.time_taken_seconds asc) as rnk
      from public.exam_sessions s
      join public.daily_exams d on d.id = s.daily_exam_id
     where d.exam_date = coalesce(p_date, public.bd_today()) and s.status = 'submitted'
  )
  select jsonb_build_object(
    'date', coalesce(p_date, public.bd_today()),
    'participants', (select count(*) from ranked),
    'entries', coalesce((select jsonb_agg(jsonb_build_object(
                  'rank', r.rnk, 'user_id', r.user_id, 'username', p.username, 'full_name', p.full_name,
                  'avatar_url', p.avatar_url, 'score', r.score, 'time_taken_seconds', r.time_taken_seconds)
                  order by r.rnk, r.time_taken_seconds)
                  from (select * from ranked order by rnk limit least(coalesce(p_limit, 50), 100)) r
                  join public.profiles p on p.id = r.user_id), '[]'::jsonb),
    'me', (select jsonb_build_object('rank', rnk, 'score', score, 'time_taken_seconds', time_taken_seconds)
             from ranked where user_id = auth.uid()));
$$;
