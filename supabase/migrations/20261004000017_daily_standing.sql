-- ============================================================================
-- 0017 · Private daily-exam standing.
-- Users see only their own rank among all participants, the day's top score
-- and an anonymous "ladder" of the scores just above and below them. No
-- other user's id, name or avatar leaves the database.
--
-- get_daily_standing(p_date) → {
--   date, participants, total_marks (questions in that day's exam, null when
--   there was no exam), top_score,
--   me: {rank, score, time_taken_seconds, percentile} | null,
--   neighbors: [{rank, score}]   up to 3 rows above and 3 below me
-- }
-- `percentile` is the "Top N %" figure: the share of participants ranked at
-- or above the caller (1 of 340 → 0.3, 12 of 340 → 3.5, last → 100).
-- ============================================================================

-- Ranking matches the old leaderboard: rank() over score desc, time asc.
-- exam_sessions_daily_idx (daily_exam_id, score desc, time_taken_seconds)
-- where status = 'submitted' delivers the rows already in window order, so
-- one index scan feeds every window and aggregate below (no sort, no join).
create or replace function public.get_daily_standing(p_date date default null)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  with exam as (
    select e.id, cardinality(e.question_ids) as total_marks
      from public.daily_exams e
     where e.exam_date = coalesce(p_date, public.bd_today()) and e.status = 'published'
  ),
  ranked as (
    select s.user_id, s.score, s.time_taken_seconds,
           rank()       over w as rnk,
           row_number() over w as pos
      from public.exam_sessions s
     where s.daily_exam_id = (select id from exam) and s.status = 'submitted'
    window w as (order by s.score desc, s.time_taken_seconds asc)
  ),
  framed as (
    select r.*,
           count(*) over () as total,
           max(r.pos) filter (where r.user_id = (select auth.uid())) over () as my_pos
      from ranked r
  )
  select jsonb_build_object(
    'date', coalesce(p_date, public.bd_today()),
    'participants', count(*),
    'total_marks', (select total_marks from exam),
    'top_score', max(f.score),
    'me', (jsonb_agg(jsonb_build_object(
             'rank', f.rnk, 'score', f.score, 'time_taken_seconds', f.time_taken_seconds,
             'percentile', round(100.0 * f.rnk / f.total, 1)))
           filter (where f.pos = f.my_pos)) -> 0,
    'neighbors', coalesce(jsonb_agg(jsonb_build_object('rank', f.rnk, 'score', f.score) order by f.pos)
                   filter (where f.pos between f.my_pos - 3 and f.my_pos + 3 and f.pos <> f.my_pos), '[]'::jsonb))
    from framed f;
$$;

revoke execute on function public.get_daily_standing(date) from public, anon;
grant execute on function public.get_daily_standing(date) to authenticated;

-- The old public board no longer lists other users: `entries` holds only the
-- caller's own row. Same signature and JSON shape, so older app builds keep
-- working (they show the caller alone).
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
  ),
  mine as (
    select * from ranked where user_id = (select auth.uid())
  )
  select jsonb_build_object(
    'date', coalesce(p_date, public.bd_today()),
    'participants', (select count(*) from ranked),
    'entries', coalesce((select jsonb_agg(jsonb_build_object(
                  'rank', m.rnk, 'user_id', m.user_id, 'username', p.username, 'full_name', p.full_name,
                  'avatar_url', p.avatar_url, 'score', m.score, 'time_taken_seconds', m.time_taken_seconds))
                  from mine m join public.profiles p on p.id = m.user_id), '[]'::jsonb),
    'me', (select jsonb_build_object('rank', rnk, 'score', score, 'time_taken_seconds', time_taken_seconds)
             from mine));
$$;
