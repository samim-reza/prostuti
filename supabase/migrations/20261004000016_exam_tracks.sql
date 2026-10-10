-- ============================================================================
-- 0016 · Exam tracks
-- The question bank and model tests come in three sections whose question
-- patterns differ: BCS, bank jobs and other govt jobs (primary teacher,
-- NTRCA, ministries…). A track defines its model-test pattern (sizes,
-- per-subject marks, negative marking, pace); a question belongs to a track
-- when `questions.exam_tags` contains the track code.
-- Patterns are approximate and admin-editable (web console).
-- ============================================================================

create table if not exists public.exam_tracks (
  code                 text primary key check (code in ('bcs', 'bank', 'govt')),
  name_bn              text not null,
  name_en              text not null,
  description_bn       text,
  description_en       text,
  -- Model-test sizes offered (marks = questions).
  sizes                int[] not null check (cardinality(sizes) between 1 and 6),
  -- `distribution` gives each subject's marks out of `full_marks`.
  full_marks           int not null check (full_marks between 10 and 300),
  negative_mark        numeric(3, 2) not null check (negative_mark between 0 and 1),
  seconds_per_question int not null check (seconds_per_question between 10 and 180),
  distribution         jsonb not null check (jsonb_typeof(distribution) = 'object'),
  sort                 int not null default 0,
  is_active            boolean not null default true,
  updated_at           timestamptz not null default now()
);
alter table public.exam_tracks enable row level security;
drop policy if exists "exam_tracks: readable" on public.exam_tracks;
create policy "exam_tracks: readable" on public.exam_tracks for select to anon, authenticated using (true);
drop policy if exists "exam_tracks: admin writes" on public.exam_tracks;
create policy "exam_tracks: admin writes" on public.exam_tracks for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
drop trigger if exists exam_tracks_updated_at on public.exam_tracks;
create trigger exam_tracks_updated_at before update on public.exam_tracks
  for each row execute function public.set_updated_at();

insert into public.exam_tracks
  (code, name_bn, name_en, description_bn, description_en, sizes, full_marks, negative_mark,
   seconds_per_question, distribution, sort)
values
  ('bcs', 'বিসিএস', 'BCS',
   'বিসিএস প্রিলিমিনারির ১০টি বিষয়, প্রতি ভুলে ০.৫ নম্বর কাটা।',
   'All 10 BCS preliminary subjects, −0.5 per wrong answer.',
   '{25,50,100,200}', 200, 0.50, 36,
   '{"bangla":30,"english":30,"bd_affairs":25,"international":25,"geography":10,"science":15,"computer":15,"math":20,"mental_ability":15,"ethics":15}',
   1),
  ('bank', 'ব্যাংক', 'Bank jobs',
   'ইংরেজি ও গণিতে বেশি জোর, সাথে ব্যাংকিং ও সাধারণ জ্ঞান; প্রতি ভুলে ০.২৫ নম্বর কাটা।',
   'English- and math-heavy with banking and general knowledge, −0.25 per wrong answer.',
   '{25,50,80,100}', 100, 0.25, 45,
   '{"bangla":15,"english":30,"math":20,"mental_ability":5,"bd_affairs":10,"international":10,"computer":10}',
   2),
  ('govt', 'অন্যান্য চাকরি', 'Other jobs',
   'প্রাথমিক শিক্ষক, শিক্ষক নিবন্ধন ও অন্যান্য সরকারি চাকরি: বাংলা, ইংরেজি, গণিত ও সাধারণ জ্ঞান।',
   'Primary teacher, NTRCA and other govt jobs: Bangla, English, math and general knowledge.',
   '{25,50,80,100}', 100, 0.25, 45,
   '{"bangla":25,"english":25,"math":25,"bd_affairs":10,"international":5,"science":5,"computer":5}',
   3)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Track membership of the existing bank (idempotent). The curated bank was
-- written for BCS; general subjects are also good practice for the other
-- tracks, except advanced English literature for bank exams.
-- ---------------------------------------------------------------------------
create index if not exists questions_exam_tags_idx on public.questions using gin (exam_tags);

update public.questions q set exam_tags = q.exam_tags || '{bcs}'
 where not ('bcs' = any (q.exam_tags)) and q.exam_tags <> '{bank}';

update public.questions q set exam_tags = q.exam_tags || '{bank}'
  from public.subjects s
 where s.id = q.subject_id and not ('bank' = any (q.exam_tags))
   and s.code in ('bangla', 'english', 'math', 'mental_ability', 'bd_affairs', 'international', 'computer')
   and coalesce((select t.code from public.topics t where t.id = q.topic_id), '')
       not in ('en_lit_early', 'en_lit_romantic_victorian', 'en_lit_modern', 'en_literary_terms');

update public.questions q set exam_tags = q.exam_tags || '{govt}'
  from public.subjects s
 where s.id = q.subject_id and not ('govt' = any (q.exam_tags))
   and s.code in ('bangla', 'english', 'math', 'bd_affairs', 'international', 'science', 'computer', 'geography');

-- Current-affairs questions (daily AI pipeline) suit every track.
update public.questions q set exam_tags = array(select distinct unnest(q.exam_tags || '{bcs,bank,govt}'))
  from public.sources src
 where src.id = q.source_id and src.kind = 'ai_generated'
   and not (q.exam_tags @> '{bcs,bank,govt}');

-- ---------------------------------------------------------------------------
-- Picking: questions of the track first, topped up from the same subjects
-- when a track has too few (one query, no second pass).
-- ---------------------------------------------------------------------------
create or replace function public.pick_questions(
  p_user uuid, p_subjects smallint[], p_topics int[], p_count int, p_exclude bigint[], p_track text
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
     order by (p_track is not null and not (p_track = any (q.exam_tags))),
              exists (select 1 from public.question_attempts a
                       where a.user_id = p_user and a.question_id = q.id),
              random()
     limit greatest(p_count, 0)
  ) s;
$$;
revoke execute on function public.pick_questions(uuid, smallint[], int[], int, bigint[], text) from public, anon, authenticated;

-- A valid, active track code (null → no preference).
create or replace function public.valid_track(p_track text)
returns text
language sql stable security definer
set search_path = ''
as $$
  select code from public.exam_tracks where code = nullif(btrim(p_track), '') and is_active;
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
  v_track   text := public.valid_track(p_config ->> 'track');
  v_t       public.exam_tracks;
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
    select * into v_t from public.exam_tracks where code = coalesce(v_track, 'bcs');
    if not found then raise exception 'invalid_track' using errcode = 'PT404'; end if;
    v_size := coalesce((p_config ->> 'size')::int, v_t.sizes[cardinality(v_t.sizes)]);
    if not (v_size = any (v_t.sizes)) then v_size := v_t.sizes[cardinality(v_t.sizes)]; end if;
    v_title := 'মডেল টেস্ট · ' || v_size || ' নম্বর'
               || case when v_t.code = 'bcs' then '' else ' · ' || v_t.name_bn end;
    -- Largest-remainder apportionment of the track's marks (integer maths,
    -- ties by subject order) → exactly v_size questions.
    for r in
      with d as (
        select s.id, s.sort, (e.value)::int * v_size as scaled
          from jsonb_each_text(v_t.distribution) e
          join public.subjects s on s.code = e.key
         where (e.value)::int > 0
      ), b as (
        select id, sort, scaled / v_t.full_marks as base, scaled % v_t.full_marks as rem from d
      ), ranked as (
        select id, sort, base, row_number() over (order by rem desc, sort) as rn from b
      )
      select id, base + case when rn <= v_size - (select sum(base) from b) then 1 else 0 end as cnt
        from ranked order by sort
    loop
      if r.cnt > 0 then
        v_ids := v_ids || public.pick_questions(v_uid, array[r.id], null, r.cnt, v_ids, v_t.code);
      end if;
    end loop;
    v_neg := v_t.negative_mark;
    v_secs := cardinality(v_ids) * v_t.seconds_per_question;

  when 'subject' then
    select 'বিষয়ভিত্তিক পরীক্ষা · ' || name_bn into v_title
      from public.subjects where id = (p_config ->> 'subject_id')::smallint;
    if v_title is null then raise exception 'subject_not_found' using errcode = 'PT404'; end if;
    v_ids := public.pick_questions(v_uid, array[(p_config ->> 'subject_id')::smallint], null, v_count, '{}', v_track);
    v_secs := greatest(cardinality(v_ids) * 36, 300);

  when 'topic' then
    select 'টপিকভিত্তিক পরীক্ষা · ' || name_bn into v_title
      from public.topics where id = (p_config ->> 'topic_id')::int;
    if v_title is null then raise exception 'topic_not_found' using errcode = 'PT404'; end if;
    v_ids := public.pick_questions(v_uid, null, array[(p_config ->> 'topic_id')::int], v_count, '{}', v_track);
    v_secs := greatest(cardinality(v_ids) * 36, 300);

  when 'weak_topic' then
    perform public.require_feature('smart_practice');
    select array_agg(topic_id) into v_topics from (
      select topic_id from public.user_topic_mastery
       where user_id = v_uid order by mastery asc, attempts desc limit 4) w;
    v_title := 'দুর্বল টপিক পরীক্ষা';
    v_ids := public.pick_questions(v_uid, null, v_topics, v_count, '{}', v_track);
    if cardinality(v_ids) < v_count then
      v_ids := v_ids || public.pick_questions(v_uid, null, null, v_count - cardinality(v_ids), v_ids, v_track);
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
      v_count, '{}', v_track);
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

-- ---------------------------------------------------------------------------
-- Question bank reads, filtered by track (p_track null → every question, so
-- older app builds keep working).
-- ---------------------------------------------------------------------------
drop function if exists public.get_practice_questions(smallint, int, bigint, int, bigint, boolean, text);
create or replace function public.get_practice_questions(
  p_subject smallint default null, p_topic int default null, p_source bigint default null,
  p_limit int default 20, p_after_id bigint default null, p_unseen_only boolean default false,
  p_search text default null, p_track text default null
)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(public.question_public_json(q) order by q.id), '[]'::jsonb)
    from (
      select q.* from public.questions q
       where q.status = 'published'
         and (p_subject is null or q.subject_id = p_subject)
         and (p_topic is null or q.topic_id = p_topic)
         and (p_source is null or q.source_id = p_source)
         and (p_track is null or p_track = any (q.exam_tags))
         and (p_after_id is null or q.id > p_after_id)
         and (p_search is null or q.stem ilike '%' || p_search || '%')
         and (not p_unseen_only or not exists (
               select 1 from public.question_attempts a
                where a.user_id = auth.uid() and a.question_id = q.id))
         -- never leak today's live daily-exam questions into practice
         and not exists (
               select 1 from public.daily_exams d
                where d.exam_date = public.bd_today() and q.id = any (d.question_ids))
       order by q.id
       limit least(coalesce(p_limit, 20), 50)
    ) q;
$$;

-- Subjects of a track (in its pattern, with its marks) and their track
-- question counts; without a track: every subject, as before.
drop function if exists public.get_subjects_overview();
create or replace function public.get_subjects_overview(p_track text default null)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  with t as (select * from public.exam_tracks where code = p_track)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'code', s.code, 'name_bn', s.name_bn, 'name_en', s.name_en,
           'bcs_marks', s.bcs_marks, 'icon', s.icon, 'color', s.color,
           'track_marks', (select (t.distribution ->> s.code)::int from t),
           'question_count', (select count(*) from public.questions q
                               where q.subject_id = s.id and q.status = 'published'
                                 and (p_track is null or p_track = any (q.exam_tags))),
           'mastery', (select round(avg(m.mastery)::numeric, 3) from public.user_topic_mastery m
                         join public.topics tp on tp.id = m.topic_id
                        where m.user_id = auth.uid() and tp.subject_id = s.id),
           'topics', (select coalesce(jsonb_agg(jsonb_build_object(
                         'id', tp.id, 'code', tp.code, 'name_bn', tp.name_bn, 'name_en', tp.name_en,
                         'mastery', (select m.mastery from public.user_topic_mastery m
                                      where m.user_id = auth.uid() and m.topic_id = tp.id))
                       order by tp.sort), '[]'::jsonb)
                        from public.topics tp where tp.subject_id = s.id))
         order by s.sort), '[]'::jsonb)
    from public.subjects s
   where p_track is null
      or exists (select 1 from t where (t.distribution ->> s.code) is not null);
$$;

drop function if exists public.get_offline_pack(smallint, int, bigint);
create or replace function public.get_offline_pack(
  p_subject smallint, p_limit int default 200, p_after_id bigint default null, p_track text default null
)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  perform public.enforce_rate_limit('offline_pack', 40, 0);
  -- exam_tags let downloaded packs filter by track while offline.
  return (
    select coalesce(jsonb_agg(public.question_public_json(q) || jsonb_build_object(
             'correct_index', q.correct_index, 'explanation', q.explanation, 'exam_tags', q.exam_tags)
             order by q.id), '[]'::jsonb)
      from (select * from public.questions qq
             where qq.status = 'published' and qq.subject_id = p_subject
               and (p_track is null or p_track = any (qq.exam_tags))
               and (p_after_id is null or qq.id > p_after_id)
               and not exists (select 1 from public.daily_exams d
                                where d.exam_date = public.bd_today() and qq.id = any (d.question_ids))
             order by qq.id
             limit least(greatest(coalesce(p_limit, 200), 1), 300)) q);
end $$;
