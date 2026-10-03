-- ============================================================================
-- 0015 · Model tests contain exactly the requested number of questions.
-- Rounding each subject's share separately could produce 26 questions for a
-- 25-mark test; the largest-remainder method fixes the total.
-- ============================================================================

set check_function_bodies = off;

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
    -- Largest-remainder apportionment: per-subject counts proportional to the
    -- BCS marks that always add up to exactly v_size.
    for r in
      with s as (
        select id, sort, bcs_marks * v_size / 200.0 as exact from public.subjects where bcs_marks > 0
      ), b as (
        select id, sort, floor(exact)::int as base, exact - floor(exact) as frac from s
      ), ranked as (
        select id, sort, base, row_number() over (order by frac desc, sort) as rn from b
      )
      select id, base + case when rn <= v_size - (select sum(base) from b) then 1 else 0 end as cnt
        from ranked order by sort
    loop
      if r.cnt > 0 then
        v_ids := v_ids || public.pick_questions(v_uid, array[r.id], null, r.cnt, v_ids);
      end if;
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
