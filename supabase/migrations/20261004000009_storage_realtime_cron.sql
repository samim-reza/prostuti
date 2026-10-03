-- ============================================================================
-- 0009 · Storage buckets, Realtime publication, cron schedules, signup hook
-- ============================================================================

-- Functions may reference tables created by later migrations.
set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- Storage. Object paths always start with a folder that proves ownership:
--   avatars/<user_id>/<file>      post-media/<user_id>/<file>
--   chat-media/<conversation_id>/<file>
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',    'avatars',    true,  2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('post-media', 'post-media', true,  5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('chat-media', 'chat-media', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.storage_conversation_member(p_folder text)
returns boolean
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if p_folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return public.is_conversation_member(p_folder::uuid);
end $$;

create policy "media: owner folder read" on storage.objects for select to authenticated
  using (bucket_id in ('avatars', 'post-media') and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "media: owner folder insert" on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars', 'post-media') and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "media: owner folder update" on storage.objects for update to authenticated
  using (bucket_id in ('avatars', 'post-media') and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "media: owner folder delete" on storage.objects for delete to authenticated
  using (bucket_id in ('avatars', 'post-media') and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "chat-media: members read" on storage.objects for select to authenticated
  using (bucket_id = 'chat-media' and public.storage_conversation_member((storage.foldername(name))[1]));
create policy "chat-media: members upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-media' and public.storage_conversation_member((storage.foldername(name))[1]));

-- ---------------------------------------------------------------------------
-- Realtime (RLS is enforced for postgres_changes subscribers).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
alter publication supabase_realtime add table public.messages, public.notifications, public.conversations;

-- ---------------------------------------------------------------------------
-- New user → profile, private row, free trial of every add-on, welcome note.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_username text := lower(nullif(btrim(new.raw_user_meta_data ->> 'username'), ''));
  v_name     text := nullif(btrim(new.raw_user_meta_data ->> 'full_name'), '');
begin
  if v_username is null or v_username !~ '^[a-z0-9_.]{3,24}$'
     or exists (select 1 from public.profiles where username = v_username::extensions.citext) then
    v_username := 'user_' || substr(replace(new.id::text, '-', ''), 1, 10);
  end if;

  insert into public.profiles (id, username, full_name)
  values (new.id, v_username, coalesce(v_name, split_part(new.email, '@', 1)));
  insert into public.user_private (user_id) values (new.id);

  insert into public.user_entitlements (user_id, addon_code, source, starts_at, expires_at)
  select new.id, a.code, 'trial', now(), now() + make_interval(days => a.trial_days)
    from public.addons a where a.is_active and a.trial_days > 0;

  insert into public.notifications (user_id, type, title, body)
  values (new.id, 'system', 'প্রস্তুতিতে স্বাগতম! 🎉',
          'আপনার জন্য সব প্রিমিয়াম ফিচার ৭ দিনের জন্য ফ্রি। চলুন লেভেল নির্ধারণী পরীক্ষা দিয়ে শুরু করি।');
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Schedules (UTC). Bangladesh = UTC+6.
-- ---------------------------------------------------------------------------
do $$
declare j text;
begin
  foreach j in array array['prostuti-ingest-news', 'prostuti-notes-morning', 'prostuti-notes-afternoon',
                           'prostuti-daily-exam', 'prostuti-dispatch', 'prostuti-replan',
                           'prostuti-housekeeping', 'prostuti-nightly'] loop
    if exists (select 1 from cron.job where jobname = j) then
      perform cron.unschedule(j);
    end if;
  end loop;
end $$;

-- every 3 hours: pull RSS feeds
select cron.schedule('prostuti-ingest-news', '10 */3 * * *',
  $$select public.invoke_edge_function('ingest-news', '{"mode":"cron"}'::jsonb, 150000)$$);
-- 05:20 BD: fresh ingest + morning notes (23:20 UTC previous day)
select cron.schedule('prostuti-notes-morning', '20 23 * * *',
  $$select public.invoke_edge_function('generate-daily-notes', '{"mode":"morning"}'::jsonb, 150000)$$);
-- 15:30 BD: afternoon top-up of the day's notes
select cron.schedule('prostuti-notes-afternoon', '30 9 * * *',
  $$select public.invoke_edge_function('generate-daily-notes', '{"mode":"append"}'::jsonb, 150000)$$);
-- 05:50 BD: daily exam from today's facts
select cron.schedule('prostuti-daily-exam', '50 23 * * *',
  $$select public.invoke_edge_function('generate-daily-exam', '{"mode":"cron"}'::jsonb, 150000)$$);
-- every 15 min: morning routine, reminders, push outbox
select cron.schedule('prostuti-dispatch', '*/15 * * * *',
  $$select public.invoke_edge_function('dispatch-notifications', '{"mode":"cron"}'::jsonb, 60000)$$);
-- every 30 min: process re-plan jobs (exam date changes etc.)
select cron.schedule('prostuti-replan', '*/30 * * * *',
  $$select public.invoke_edge_function('generate-study-plan', '{"mode":"jobs"}'::jsonb, 150000)$$);
select cron.schedule('prostuti-housekeeping', '7 * * * *', $$select public.housekeeping()$$);
-- 00:05 BD
select cron.schedule('prostuti-nightly', '5 18 * * *', $$select public.nightly_rollover()$$);
