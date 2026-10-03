-- ============================================================================
-- 0012 · Bilingual content (Bangla + English)
-- The app language is a user setting. Server-generated text therefore carries
-- both languages and the client shows the one matching the current locale:
--   • daily notes: *_en columns (filled by the AI pipeline)
--   • notifications: title_en / body_en
--   • study plan days: title_en (items carry title_en too)
-- Push notifications use the recipient's profiles.locale.
-- ============================================================================

set check_function_bodies = off;

alter table public.daily_notes
  add column if not exists title_en text,
  add column if not exists summary_en text,
  add column if not exists key_facts_en jsonb not null default '[]'::jsonb,
  add column if not exists probable_questions_en jsonb not null default '[]'::jsonb;
grant select (title_en, summary_en, key_facts_en, probable_questions_en) on public.daily_notes to authenticated;

alter table public.facts add column if not exists fact_en text;

alter table public.notifications
  add column if not exists title_en text,
  add column if not exists body_en text;

alter table public.study_plan_days add column if not exists title_en text;
alter table public.daily_exams add column if not exists title_en text;

-- Picks the text in the recipient's language (falls back to Bangla).
create or replace function public.pick_locale(p_user uuid, p_bn text, p_en text)
returns text
language sql stable security definer
set search_path = ''
as $$
  select case when p_en is not null and (select locale from public.profiles where id = p_user) = 'en'
              then p_en else p_bn end;
$$;
revoke execute on function public.pick_locale(uuid, text, text) from public, anon, authenticated;

drop function if exists public.notify_user(uuid, text, text, text, jsonb, uuid, text);
create or replace function public.notify_user(
  p_user uuid, p_type text, p_title text, p_body text default null,
  p_data jsonb default '{}'::jsonb, p_actor uuid default null, p_category text default 'social',
  p_title_en text default null, p_body_en text default null
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_settings jsonb;
begin
  if p_user is null or p_user = p_actor then return; end if;
  select notification_settings into v_settings from public.profiles where id = p_user;
  insert into public.notifications (user_id, type, title, body, title_en, body_en, data, actor_id)
  values (p_user, p_type, p_title, p_body, p_title_en, p_body_en, p_data, p_actor);
  if coalesce((v_settings ->> p_category)::boolean, true) then
    insert into public.push_outbox (user_id, title, body, data)
    values (p_user, public.pick_locale(p_user, p_title, p_title_en), public.pick_locale(p_user, p_body, p_body_en),
            p_data || jsonb_build_object('type', p_type));
  end if;
end $$;
revoke execute on function public.notify_user(uuid, text, text, text, jsonb, uuid, text, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Re-create notification producers with English text.
-- ---------------------------------------------------------------------------
create or replace function public.send_friend_request(p_target uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_reverse public.friend_requests;
  v_id      bigint;
  v_name    text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  if v_uid = p_target then raise exception 'cannot_friend_self'; end if;
  if public.is_blocked_between(v_uid, p_target) then raise exception 'user_unavailable' using errcode = 'PT403'; end if;
  if public.are_friends(v_uid, p_target) then return jsonb_build_object('status', 'friends'); end if;
  perform public.enforce_rate_limit('friend_request', 40, 86400);

  select coalesce(full_name, username::text) into v_name from public.profiles where id = v_uid;
  select * into v_reverse from public.friend_requests
   where sender_id = p_target and receiver_id = v_uid and status = 'pending' for update;
  if found then
    update public.friend_requests set status = 'accepted', responded_at = now() where id = v_reverse.id;
    perform public._make_friends(v_uid, p_target);
    perform public.notify_user(p_target, 'friend_accept', 'বন্ধুত্বের অনুরোধ গৃহীত',
      v_name || ' আপনার বন্ধুত্বের অনুরোধ গ্রহণ করেছেন', jsonb_build_object('user_id', v_uid), v_uid, 'social',
      'Friend request accepted', v_name || ' accepted your friend request');
    return jsonb_build_object('status', 'friends');
  end if;

  insert into public.friend_requests (sender_id, receiver_id) values (v_uid, p_target)
  on conflict do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('status', 'request_sent'); end if;

  perform public.notify_user(p_target, 'friend_request', 'নতুন বন্ধুত্বের অনুরোধ',
    v_name || ' আপনাকে বন্ধুত্বের অনুরোধ পাঠিয়েছেন', jsonb_build_object('request_id', v_id, 'user_id', v_uid), v_uid, 'social',
    'New friend request', v_name || ' sent you a friend request');
  return jsonb_build_object('status', 'request_sent', 'request_id', v_id);
end $$;

create or replace function public.respond_friend_request(p_request bigint, p_accept boolean)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_req public.friend_requests;
  v_name text;
begin
  select * into v_req from public.friend_requests
   where id = p_request and receiver_id = v_uid and status = 'pending' for update;
  if not found then raise exception 'request_not_found' using errcode = 'PT404'; end if;
  update public.friend_requests
     set status = case when p_accept then 'accepted' else 'declined' end, responded_at = now()
   where id = p_request;
  if p_accept then
    perform public._make_friends(v_req.sender_id, v_uid);
    select coalesce(full_name, username::text) into v_name from public.profiles where id = v_uid;
    perform public.notify_user(v_req.sender_id, 'friend_accept', 'বন্ধুত্বের অনুরোধ গৃহীত',
      v_name || ' আপনার বন্ধুত্বের অনুরোধ গ্রহণ করেছেন', jsonb_build_object('user_id', v_uid), v_uid, 'social',
      'Friend request accepted', v_name || ' accepted your friend request');
    return jsonb_build_object('status', 'friends');
  end if;
  return jsonb_build_object('status', 'none');
end $$;

create or replace function public.react_to_post(p_post uuid, p_type public.reaction_type)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_new  boolean;
  v_name text;
  v_post public.posts;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  perform public.enforce_rate_limit('react', 120, 60);
  select * into v_post from public.posts where id = p_post;
  if not found or not public.can_view_post(v_post.author_id, v_post.visibility, v_post.is_hidden) then
    raise exception 'post_not_found' using errcode = 'PT404';
  end if;

  if p_type is null then
    delete from public.post_reactions where post_id = p_post and user_id = v_uid;
  else
    v_new := not exists (select 1 from public.post_reactions where post_id = p_post and user_id = v_uid);
    insert into public.post_reactions (post_id, user_id, type) values (p_post, v_uid, p_type)
    on conflict (post_id, user_id) do update set type = excluded.type;
    if v_new then
      select coalesce(full_name, username::text) into v_name from public.profiles where id = v_uid;
      perform public.notify_user(v_post.author_id, 'post_reaction', 'নতুন প্রতিক্রিয়া',
        v_name || ' আপনার পোস্টে প্রতিক্রিয়া জানিয়েছেন', jsonb_build_object('post_id', p_post), v_uid, 'social',
        'New reaction', v_name || ' reacted to your post');
    end if;
  end if;

  perform public._refresh_post_reactions(p_post);
  return (select jsonb_build_object('reaction_count', reaction_count, 'reaction_summary', reaction_summary,
                                    'my_reaction', p_type)
            from public.posts where id = p_post);
end $$;

create or replace function public.comments_after_change()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_post_author   uuid;
  v_parent_author uuid;
  v_name          text;
begin
  if tg_op = 'INSERT' then
    update public.posts set comment_count = comment_count + 1 where id = new.post_id
      returning author_id into v_post_author;
    select coalesce(full_name, username::text) into v_name from public.profiles where id = new.author_id;
    if new.parent_id is not null then
      update public.comments set reply_count = reply_count + 1 where id = new.parent_id
        returning author_id into v_parent_author;
      perform public.notify_user(v_parent_author, 'comment_reply', 'নতুন উত্তর',
        v_name || ' আপনার মন্তব্যের উত্তর দিয়েছেন',
        jsonb_build_object('post_id', new.post_id, 'comment_id', new.id), new.author_id, 'social',
        'New reply', v_name || ' replied to your comment');
    end if;
    if v_post_author is distinct from v_parent_author then
      perform public.notify_user(v_post_author, 'post_comment', 'নতুন মন্তব্য',
        v_name || ' আপনার পোস্টে মন্তব্য করেছেন: ' || left(new.body, 80),
        jsonb_build_object('post_id', new.post_id, 'comment_id', new.id), new.author_id, 'social',
        'New comment', v_name || ' commented on your post: ' || left(new.body, 80));
    end if;
    perform public.invoke_edge_function('moderate-content',
      jsonb_build_object('type', 'comment', 'id', new.id), 10000);
    return new;
  elsif tg_op = 'DELETE' then
    update public.posts set comment_count = greatest(comment_count - 1 - old.reply_count, 0) where id = old.post_id;
    if old.parent_id is not null then
      update public.comments set reply_count = greatest(reply_count - 1, 0) where id = old.parent_id;
    end if;
    return old;
  end if;
  return null;
end $$;

create or replace function public.on_exam_schedule_changed()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare r record;
begin
  if new.expected_date is distinct from old.expected_date then
    for r in select distinct user_id from public.study_plans
              where status = 'active' and schedule_id = new.id loop
      insert into public.plan_replan_jobs (user_id, reason) values (r.user_id, 'exam_date_changed');
      perform public.notify_user(r.user_id, 'plan_update', 'পরীক্ষার তারিখ পরিবর্তিত হয়েছে',
        new.title_bn || ' এর নতুন সম্ভাব্য তারিখ ' || to_char(new.expected_date, 'DD-MM-YYYY') ||
        '। আপনার রুটিন নতুন তারিখ অনুযায়ী আপডেট করা হচ্ছে।',
        jsonb_build_object('schedule_id', new.id), null, 'routine',
        'Exam date changed',
        new.title_en || ' is now expected on ' || to_char(new.expected_date, 'DD Mon YYYY') ||
        '. Your routine is being updated for the new date.');
    end loop;
    perform public.invoke_edge_function('generate-study-plan', jsonb_build_object('mode', 'jobs'), 120000);
  end if;
  return new;
end $$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_username text := lower(nullif(btrim(new.raw_user_meta_data ->> 'username'), ''));
  v_name     text := nullif(btrim(new.raw_user_meta_data ->> 'full_name'), '');
  v_locale   text := case when new.raw_user_meta_data ->> 'locale' = 'en' then 'en' else 'bn' end;
begin
  if v_username is null or v_username !~ '^[a-z0-9_.]{3,24}$'
     or exists (select 1 from public.profiles where username = v_username::extensions.citext) then
    v_username := 'user_' || substr(replace(new.id::text, '-', ''), 1, 10);
  end if;

  insert into public.profiles (id, username, full_name, locale)
  values (new.id, v_username, coalesce(v_name, split_part(new.email, '@', 1)), v_locale);
  insert into public.user_private (user_id) values (new.id);

  insert into public.user_entitlements (user_id, addon_code, source, starts_at, expires_at)
  select new.id, a.code, 'trial', now(), now() + make_interval(days => a.trial_days)
    from public.addons a where a.is_active and a.trial_days > 0;

  insert into public.notifications (user_id, type, title, body, title_en, body_en)
  values (new.id, 'system', 'প্রস্তুতিতে স্বাগতম! 🎉',
          'আপনার জন্য সব প্রিমিয়াম ফিচার ৭ দিনের জন্য ফ্রি। চলুন লেভেল নির্ধারণী পরীক্ষা দিয়ে শুরু করি।',
          'Welcome to Prostuti! 🎉',
          'Every premium feature is free for you for 7 days. Let''s start with the level test.');
  return new;
end $$;

drop function if exists public.broadcast_notification(text, text, text, jsonb, text, int);
create or replace function public.broadcast_notification(
  p_type text, p_title text, p_body text, p_data jsonb, p_category text, p_active_days int default 30,
  p_title_en text default null, p_body_en text default null
)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare v_count int;
begin
  with targets as (
    select p.id, p.locale, coalesce((p.notification_settings ->> p_category)::boolean, true) as wants_push
      from public.profiles p
     where not p.is_banned
       and (p.last_active_date >= public.bd_today() - p_active_days or p.created_at >= now() - make_interval(days => p_active_days))
  ), n as (
    insert into public.notifications (user_id, type, title, body, title_en, body_en, data)
    select id, p_type, p_title, p_body, p_title_en, p_body_en, coalesce(p_data, '{}'::jsonb) from targets
    returning user_id
  ), q as (
    insert into public.push_outbox (user_id, title, body, data)
    select id,
           case when locale = 'en' and p_title_en is not null then p_title_en else p_title end,
           case when locale = 'en' and p_body_en is not null then p_body_en else p_body end,
           coalesce(p_data, '{}'::jsonb) || jsonb_build_object('type', p_type)
      from targets where wants_push
    returning 1
  )
  select count(*) into v_count from n;
  return v_count;
end $$;
revoke execute on function public.broadcast_notification(text, text, text, jsonb, text, int, text, text) from public, anon, authenticated;

create or replace function public.queue_morning_routines()
returns int
language plpgsql security definer
set search_path = ''
as $$
declare v_count int;
begin
  with today as (
    select d.user_id, d.id as day_id, d.title_bn, coalesce(d.title_en, d.title_bn) as title_en, d.total_items
      from public.study_plan_days d
      join public.study_plans sp on sp.id = d.plan_id and sp.status = 'active'
     where d.day_date = public.bd_today()
  ), n as (
    insert into public.notifications (user_id, type, title, body, title_en, body_en, data)
    select t.user_id, 'routine', 'আজকের রুটিন তৈরি ☀️',
           t.title_bn || ' · ' || t.total_items || 'টি কাজ। চলুন শুরু করি!',
           'Your routine for today is ready ☀️',
           t.title_en || ' · ' || t.total_items || ' tasks. Let''s get started!',
           jsonb_build_object('day_id', t.day_id, 'route', '/plan/day/' || t.day_id)
      from today t
    returning user_id, title, body, title_en, body_en, data
  ), q as (
    insert into public.push_outbox (user_id, title, body, data)
    select n.user_id,
           case when p.locale = 'en' then n.title_en else n.title end,
           case when p.locale = 'en' then n.body_en else n.body end,
           n.data || jsonb_build_object('type', 'routine')
      from n join public.profiles p on p.id = n.user_id
     where coalesce((p.notification_settings ->> 'routine')::boolean, true)
    returning 1
  )
  select count(*) into v_count from n;
  return v_count;
end $$;
revoke execute on function public.queue_morning_routines() from public, anon, authenticated;

-- Today's notes now include English fields.
create or replace function public.get_today_notes()
returns jsonb
language sql stable security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'note_date', public.bd_today(),
    'notes', coalesce((select jsonb_agg(jsonb_build_object(
                'id', n.id, 'category', n.category, 'title', n.title, 'summary', n.summary,
                'key_facts', n.key_facts, 'probable_questions', n.probable_questions,
                'title_en', n.title_en, 'summary_en', n.summary_en,
                'key_facts_en', n.key_facts_en, 'probable_questions_en', n.probable_questions_en,
                'importance', n.importance, 'source_links', n.source_links, 'created_at', n.created_at)
              order by n.importance desc, n.id)
              from public.daily_notes n
             where n.note_date = public.bd_today() and n.status = 'published'), '[]'::jsonb),
    'downloaded', exists (select 1 from public.note_downloads d
                           where d.user_id = auth.uid() and d.note_date = public.bd_today()),
    'daily_exam', (select jsonb_build_object('id', e.id, 'title_bn', e.title_bn, 'title_en', e.title_en,
                          'question_count', cardinality(e.question_ids),
                          'duration_minutes', e.duration_minutes)
                     from public.daily_exams e
                    where e.exam_date = public.bd_today() and e.status = 'published'));
$$;
