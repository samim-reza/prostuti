-- ============================================================================
-- 0004 · Chat: direct + group conversations, messages (Realtime-enabled)
-- Typing indicators / presence use Realtime broadcast channels (no tables).
-- ============================================================================

-- Functions may reference tables created by later migrations.
set check_function_bodies = off;

create table public.conversations (
  id                   uuid primary key default gen_random_uuid(),
  kind                 text not null default 'direct' check (kind in ('direct', 'group')),
  title                text check (title is null or char_length(title) <= 80),
  avatar_url           text,
  direct_key           text unique,
  created_by           uuid references public.profiles (id) on delete set null,
  last_message_at      timestamptz,
  last_message_preview text,
  last_message_sender  uuid,
  created_at           timestamptz not null default now(),
  check ((kind = 'direct') = (direct_key is not null))
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references public.profiles (id) on delete cascade,
  role            text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at       timestamptz not null default now(),
  last_read_at    timestamptz not null default now(),
  muted           boolean not null default false,
  primary key (conversation_id, user_id)
);
create index conversation_members_user_idx on public.conversation_members (user_id);

create or replace function public.is_conversation_member(p_conversation uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.conversation_members
                  where conversation_id = p_conversation and user_id = auth.uid());
$$;

alter table public.conversations enable row level security;
create policy "conversations: members read" on public.conversations for select to authenticated
  using (public.is_conversation_member(id));
create policy "conversations: group admins update" on public.conversations for update to authenticated
  using (kind = 'group' and exists (select 1 from public.conversation_members m
                                     where m.conversation_id = id and m.user_id = (select auth.uid())
                                       and m.role in ('owner', 'admin')));
revoke insert, update, delete on public.conversations from anon, authenticated;
grant update (title, avatar_url) on public.conversations to authenticated;

alter table public.conversation_members enable row level security;
create policy "conversation_members: members read" on public.conversation_members for select to authenticated
  using (public.is_conversation_member(conversation_id));
create policy "conversation_members: own row update" on public.conversation_members for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "conversation_members: leave" on public.conversation_members for delete to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update on public.conversation_members from anon, authenticated;
grant update (last_read_at, muted) on public.conversation_members to authenticated;

create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id       uuid not null references public.profiles (id) on delete cascade,
  kind            text not null default 'text' check (kind in ('text', 'image', 'system')),
  body            text check (body is null or char_length(body) <= 4000),
  media_path      text,
  reply_to_id     uuid references public.messages (id) on delete set null,
  created_at      timestamptz not null default now(),
  edited_at       timestamptz,
  deleted_at      timestamptz,
  constraint messages_text_body  check (kind <> 'text' or coalesce(char_length(btrim(body)), 0) > 0),
  constraint messages_image_path check (kind <> 'image' or media_path is not null)
);
create index messages_conversation_idx on public.messages (conversation_id, created_at desc, id desc);

alter table public.messages enable row level security;
create policy "messages: members read" on public.messages for select to authenticated
  using (public.is_conversation_member(conversation_id));
create policy "messages: members send" on public.messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and kind <> 'system'
              and public.is_conversation_member(conversation_id));
create policy "messages: sender edits" on public.messages for update to authenticated
  using (sender_id = (select auth.uid())) with check (sender_id = (select auth.uid()));
revoke insert, update on public.messages from anon, authenticated;
grant insert (id, conversation_id, sender_id, kind, body, media_path, reply_to_id) on public.messages to authenticated;
grant update (body, edited_at, deleted_at) on public.messages to authenticated;

create trigger messages_rate_limit before insert on public.messages
  for each row execute function public.trg_rate_limit('message_send', '40', '60');

-- Direct messages between users who blocked each other are rejected.
create or replace function public.messages_before_insert()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare v_other uuid;
begin
  select m.user_id into v_other
    from public.conversations c
    join public.conversation_members m on m.conversation_id = c.id and m.user_id <> new.sender_id
   where c.id = new.conversation_id and c.kind = 'direct'
   limit 1;
  if v_other is not null and public.is_blocked_between(new.sender_id, v_other) then
    raise exception 'user_unavailable' using errcode = 'PT403';
  end if;
  return new;
end $$;
create trigger messages_before_insert before insert on public.messages
  for each row execute function public.messages_before_insert();

create or replace function public.messages_after_insert()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_preview text := case new.kind when 'image' then '📷 ছবি' else left(coalesce(new.body, ''), 120) end;
  v_name    text;
  v_conv    public.conversations;
begin
  update public.conversations
     set last_message_at = new.created_at, last_message_preview = v_preview, last_message_sender = new.sender_id
   where id = new.conversation_id
  returning * into v_conv;

  update public.conversation_members set last_read_at = new.created_at
   where conversation_id = new.conversation_id and user_id = new.sender_id;

  -- Push only (chat does not flood the notification inbox).
  select coalesce(full_name, username::text) into v_name from public.profiles where id = new.sender_id;
  insert into public.push_outbox (user_id, title, body, data)
  select m.user_id,
         case when v_conv.kind = 'group' then coalesce(v_conv.title, 'গ্রুপ') || ' · ' || v_name else v_name end,
         v_preview,
         jsonb_build_object('type', 'message', 'conversation_id', new.conversation_id)
    from public.conversation_members m
    join public.profiles p on p.id = m.user_id
   where m.conversation_id = new.conversation_id
     and m.user_id <> new.sender_id
     and not m.muted
     and coalesce((p.notification_settings ->> 'chat')::boolean, true);
  return new;
end $$;
create trigger messages_after_insert after insert on public.messages
  for each row execute function public.messages_after_insert();

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------
create or replace function public.get_or_create_direct_conversation(p_other uuid)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_key   text;
  v_id    uuid;
  v_allow text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  if v_uid = p_other then raise exception 'cannot_message_self'; end if;
  if public.is_blocked_between(v_uid, p_other) then raise exception 'user_unavailable' using errcode = 'PT403'; end if;

  v_key := least(v_uid, p_other)::text || ':' || greatest(v_uid, p_other)::text;
  select id into v_id from public.conversations where direct_key = v_key;
  if v_id is not null then return v_id; end if;

  select allow_messages_from into v_allow from public.profiles where id = p_other;
  if v_allow is null then raise exception 'user_not_found' using errcode = 'PT404'; end if;
  if v_allow = 'friends' and not public.are_friends(v_uid, p_other) then
    raise exception 'messaging_friends_only' using errcode = 'PT403';
  end if;

  insert into public.conversations (kind, direct_key, created_by)
  values ('direct', v_key, v_uid)
  on conflict (direct_key) do update set direct_key = excluded.direct_key
  returning id into v_id;
  insert into public.conversation_members (conversation_id, user_id)
  values (v_id, v_uid), (v_id, p_other)
  on conflict do nothing;
  return v_id;
end $$;

create or replace function public.create_group_conversation(p_title text, p_members uuid[])
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_m   uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  if coalesce(char_length(btrim(p_title)), 0) = 0 then raise exception 'title_required'; end if;
  if cardinality(p_members) > 49 then raise exception 'too_many_members'; end if;
  perform public.enforce_rate_limit('group_create', 10, 86400);

  insert into public.conversations (kind, title, created_by) values ('group', btrim(p_title), v_uid)
  returning id into v_id;
  insert into public.conversation_members (conversation_id, user_id, role) values (v_id, v_uid, 'owner');
  foreach v_m in array p_members loop
    if v_m <> v_uid and public.are_friends(v_uid, v_m) then
      insert into public.conversation_members (conversation_id, user_id) values (v_id, v_m)
      on conflict do nothing;
    end if;
  end loop;
  insert into public.messages (conversation_id, sender_id, kind, body)
  values (v_id, v_uid, 'system', 'গ্রুপ তৈরি হয়েছে');
  return v_id;
end $$;

create or replace function public.get_conversations(p_limit int default 30, p_before timestamptz default null)
returns table (
  id uuid, kind text, title text, avatar_url text,
  other_user_id uuid, other_username text, other_full_name text, other_avatar_url text,
  last_message_at timestamptz, last_message_preview text, last_message_sender uuid,
  unread_count int, muted boolean, member_count int
)
language sql stable security definer
set search_path = ''
as $$
  select c.id, c.kind, c.title, c.avatar_url,
         o.id, o.username::text, o.full_name, o.avatar_url,
         c.last_message_at, c.last_message_preview, c.last_message_sender,
         (select count(*)::int from (
            select 1 from public.messages m
             where m.conversation_id = c.id and m.created_at > me.last_read_at
               and m.sender_id <> auth.uid() and m.deleted_at is null
             limit 100) u),
         me.muted,
         (select count(*)::int from public.conversation_members x where x.conversation_id = c.id)
    from public.conversation_members me
    join public.conversations c on c.id = me.conversation_id
    left join lateral (
      select p.* from public.conversation_members om
        join public.profiles p on p.id = om.user_id
       where c.kind = 'direct' and om.conversation_id = c.id and om.user_id <> auth.uid()
       limit 1) o on true
   where me.user_id = auth.uid()
     and c.last_message_at is not null
     and (p_before is null or c.last_message_at < p_before)
   order by c.last_message_at desc
   limit least(coalesce(p_limit, 30), 100);
$$;

create or replace function public.mark_conversation_read(p_conversation uuid)
returns void
language sql security definer
set search_path = ''
as $$
  update public.conversation_members set last_read_at = now()
   where conversation_id = p_conversation and user_id = auth.uid();
$$;

create or replace function public.get_unread_conversations_count()
returns int
language sql stable security definer
set search_path = ''
as $$
  select count(*)::int
    from public.conversation_members me
    join public.conversations c on c.id = me.conversation_id
   where me.user_id = auth.uid()
     and c.last_message_at > me.last_read_at
     and c.last_message_sender is distinct from auth.uid();
$$;
