-- ============================================================================
-- 0013 · Offline-first support
--   • get_offline_pack: download a subject's questions (with answers) for
--     offline self-practice. Today's live daily-exam questions are excluded;
--     answers are already obtainable through reveal_answer, so exam
--     integrity (daily exam + leaderboard) is unaffected.
--   • sync_practice_attempts: idempotent upload of answers given offline
--     (graded again on the server — the client is never trusted).
--   • client-generated ids for posts/comments so replays never duplicate.
-- ============================================================================

set check_function_bodies = off;

alter table public.question_attempts add column if not exists client_id uuid;
create unique index if not exists question_attempts_client_id_uq on public.question_attempts (client_id) where client_id is not null;

grant insert (id) on public.posts to authenticated;
grant insert (id) on public.comments to authenticated;

create or replace function public.get_offline_pack(p_subject smallint, p_limit int default 200, p_after_id bigint default null)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  perform public.enforce_rate_limit('offline_pack', 40, 0);
  return (
    select coalesce(jsonb_agg(public.question_public_json(q) || jsonb_build_object(
             'correct_index', q.correct_index, 'explanation', q.explanation) order by q.id), '[]'::jsonb)
      from (select * from public.questions qq
             where qq.status = 'published' and qq.subject_id = p_subject
               and (p_after_id is null or qq.id > p_after_id)
               and not exists (select 1 from public.daily_exams d
                                where d.exam_date = public.bd_today() and qq.id = any (d.question_ids))
             order by qq.id
             limit least(greatest(coalesce(p_limit, 200), 1), 300)) q);
end $$;

-- p_attempts: [{ "client_id": uuid, "question_id": int, "selected_index": int, "answered_at": iso }]
create or replace function public.sync_practice_attempts(p_attempts jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_synced int := 0;
  r        record;
  v_ok     boolean;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  perform public.enforce_rate_limit('practice_sync', 60, 3600);

  for r in
    select (a ->> 'client_id')::uuid as client_id,
           (a ->> 'question_id')::bigint as question_id,
           (a ->> 'selected_index')::smallint as selected_index,
           least(coalesce((a ->> 'answered_at')::timestamptz, now()), now()) as answered_at
      from jsonb_array_elements(coalesce(p_attempts, '[]'::jsonb)) a
     limit 500
  loop
    continue when r.client_id is null or r.question_id is null or r.selected_index is null;
    continue when exists (select 1 from public.question_attempts where client_id = r.client_id);
    continue when public.is_live_daily_question(r.question_id);

    select (q.correct_index = r.selected_index) into v_ok
      from public.questions q where q.id = r.question_id and q.status = 'published';
    continue when v_ok is null;

    insert into public.question_attempts (user_id, question_id, selected_index, is_correct, mode, client_id, created_at)
    values (v_uid, r.question_id, r.selected_index, v_ok, 'practice', r.client_id, r.answered_at)
    on conflict do nothing;
    if found then
      v_synced := v_synced + 1;
      update public.questions set times_answered = times_answered + 1,
             times_correct = times_correct + v_ok::int where id = r.question_id;
      perform public.update_mastery(v_uid, (select topic_id from public.questions where id = r.question_id), v_ok, 0.15);
    end if;
  end loop;

  if v_synced > 0 then
    perform public.touch_streak(v_uid);
    perform public.snapshot_readiness(v_uid);
  end if;
  return jsonb_build_object('synced', v_synced);
end $$;
