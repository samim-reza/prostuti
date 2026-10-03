-- ============================================================================
-- 0003 · Social: friends, blocks, posts, reactions, comments, reports
-- All list endpoints use keyset (cursor) pagination; counters are maintained
-- by triggers so lists never need COUNT(*) per row.
-- ============================================================================

-- Functions may reference tables created by later migrations.
set check_function_bodies = off;

create type public.post_visibility as enum ('public', 'friends', 'only_me');
create type public.reaction_type   as enum ('like', 'love', 'haha', 'wow', 'sad', 'angry');

-- ---------------------------------------------------------------------------
-- Friendships (one canonical row per pair: user_a < user_b)
-- ---------------------------------------------------------------------------
create table public.friendships (
  user_a     uuid not null references public.profiles (id) on delete cascade,
  user_b     uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index friendships_user_b_idx on public.friendships (user_b);
alter table public.friendships enable row level security;
create policy "friendships: readable" on public.friendships for select to authenticated using (true);
revoke insert, update, delete on public.friendships from anon, authenticated;

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id);
alter table public.blocks enable row level security;
create policy "blocks: owner reads" on public.blocks for select to authenticated using (blocker_id = (select auth.uid()));
revoke insert, update, delete on public.blocks from anon, authenticated;

create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.friendships where user_a = least(a, b) and user_b = greatest(a, b));
$$;

create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.blocks
                  where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;

create table public.friend_requests (
  id           bigint generated always as identity primary key,
  sender_id    uuid not null references public.profiles (id) on delete cascade,
  receiver_id  uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (sender_id <> receiver_id)
);
create unique index friend_requests_pending_pair
  on public.friend_requests (least(sender_id, receiver_id), greatest(sender_id, receiver_id))
  where status = 'pending';
create index friend_requests_receiver_idx on public.friend_requests (receiver_id, status, created_at desc);
create index friend_requests_sender_idx   on public.friend_requests (sender_id, status, created_at desc);
alter table public.friend_requests enable row level security;
create policy "friend_requests: parties read" on public.friend_requests for select to authenticated
  using ((select auth.uid()) in (sender_id, receiver_id));
revoke insert, update, delete on public.friend_requests from anon, authenticated;

create or replace function public._make_friends(a uuid, b uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.friendships (user_a, user_b) values (least(a, b), greatest(a, b))
  on conflict do nothing;
  if found then
    update public.profiles set friends_count = friends_count + 1 where id in (a, b);
  end if;
end $$;
revoke execute on function public._make_friends(uuid, uuid) from public, anon, authenticated;

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

  -- They already asked me → accept instead of creating a duplicate.
  select * into v_reverse from public.friend_requests
   where sender_id = p_target and receiver_id = v_uid and status = 'pending' for update;
  if found then
    update public.friend_requests set status = 'accepted', responded_at = now() where id = v_reverse.id;
    perform public._make_friends(v_uid, p_target);
    select coalesce(full_name, username::text) into v_name from public.profiles where id = v_uid;
    perform public.notify_user(p_target, 'friend_accept', 'বন্ধুত্বের অনুরোধ গৃহীত',
      v_name || ' আপনার বন্ধুত্বের অনুরোধ গ্রহণ করেছেন', jsonb_build_object('user_id', v_uid), v_uid, 'social');
    return jsonb_build_object('status', 'friends');
  end if;

  insert into public.friend_requests (sender_id, receiver_id) values (v_uid, p_target)
  on conflict do nothing
  returning id into v_id;
  if v_id is null then
    return jsonb_build_object('status', 'request_sent');
  end if;

  select coalesce(full_name, username::text) into v_name from public.profiles where id = v_uid;
  perform public.notify_user(p_target, 'friend_request', 'নতুন বন্ধুত্বের অনুরোধ',
    v_name || ' আপনাকে বন্ধুত্বের অনুরোধ পাঠিয়েছেন', jsonb_build_object('request_id', v_id, 'user_id', v_uid), v_uid, 'social');
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
      v_name || ' আপনার বন্ধুত্বের অনুরোধ গ্রহণ করেছেন', jsonb_build_object('user_id', v_uid), v_uid, 'social');
    return jsonb_build_object('status', 'friends');
  end if;
  return jsonb_build_object('status', 'none');
end $$;

create or replace function public.cancel_friend_request(p_request bigint)
returns void
language sql security definer
set search_path = ''
as $$
  update public.friend_requests set status = 'cancelled', responded_at = now()
   where id = p_request and sender_id = auth.uid() and status = 'pending';
$$;

create or replace function public.unfriend(p_user uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_uid uuid := auth.uid();
begin
  delete from public.friendships where user_a = least(v_uid, p_user) and user_b = greatest(v_uid, p_user);
  if found then
    update public.profiles set friends_count = greatest(friends_count - 1, 0) where id in (v_uid, p_user);
  end if;
end $$;

create or replace function public.block_user(p_user uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid = p_user then raise exception 'cannot_block_self'; end if;
  insert into public.blocks (blocker_id, blocked_id) values (v_uid, p_user) on conflict do nothing;
  perform public.unfriend(p_user);
  update public.friend_requests set status = 'cancelled', responded_at = now()
   where status = 'pending'
     and ((sender_id = v_uid and receiver_id = p_user) or (sender_id = p_user and receiver_id = v_uid));
end $$;

create or replace function public.unblock_user(p_user uuid)
returns void
language sql security definer
set search_path = ''
as $$ delete from public.blocks where blocker_id = auth.uid() and blocked_id = p_user; $$;

-- Relationship between the caller and another user, for profile buttons.
create or replace function public.get_relationship(p_user uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_req public.friend_requests;
begin
  if v_uid = p_user then return jsonb_build_object('status', 'self'); end if;
  if exists (select 1 from public.blocks where blocker_id = v_uid and blocked_id = p_user) then
    return jsonb_build_object('status', 'blocked');
  end if;
  if public.are_friends(v_uid, p_user) then return jsonb_build_object('status', 'friends'); end if;
  select * into v_req from public.friend_requests
   where status = 'pending'
     and ((sender_id = v_uid and receiver_id = p_user) or (sender_id = p_user and receiver_id = v_uid))
   limit 1;
  if found then
    return jsonb_build_object(
      'status', case when v_req.sender_id = v_uid then 'request_sent' else 'request_received' end,
      'request_id', v_req.id);
  end if;
  return jsonb_build_object('status', 'none');
end $$;

create or replace function public.get_friends(
  p_user uuid default null, p_limit int default 30, p_before timestamptz default null
)
returns table (id uuid, username text, full_name text, avatar_url text, bio text, friends_since timestamptz)
language sql stable security definer
set search_path = ''
as $$
  with me as (select coalesce(p_user, auth.uid()) as uid)
  select p.id, p.username::text, p.full_name, p.avatar_url, p.bio, f.created_at
    from public.friendships f
    cross join me
    join lateral (select case when f.user_a = me.uid then f.user_b else f.user_a end as other) o on true
    join public.profiles p on p.id = o.other
   where (f.user_a = me.uid or f.user_b = me.uid)
     and (p_before is null or f.created_at < p_before)
   order by f.created_at desc
   limit least(coalesce(p_limit, 30), 100);
$$;

create or replace function public.get_friend_requests(
  p_incoming boolean default true, p_limit int default 30, p_before timestamptz default null
)
returns table (request_id bigint, user_id uuid, username text, full_name text, avatar_url text,
               mutual_friends int, created_at timestamptz)
language sql stable security definer
set search_path = ''
as $$
  select r.id, p.id, p.username::text, p.full_name, p.avatar_url,
         (select count(*)::int from public.friendships f1
            join public.friendships f2
              on (case when f1.user_a = auth.uid() then f1.user_b else f1.user_a end)
               = (case when f2.user_a = p.id then f2.user_b else f2.user_a end)
           where (f1.user_a = auth.uid() or f1.user_b = auth.uid())
             and (f2.user_a = p.id or f2.user_b = p.id)),
         r.created_at
    from public.friend_requests r
    join public.profiles p on p.id = case when p_incoming then r.sender_id else r.receiver_id end
   where r.status = 'pending'
     and (case when p_incoming then r.receiver_id else r.sender_id end) = auth.uid()
     and (p_before is null or r.created_at < p_before)
   order by r.created_at desc
   limit least(coalesce(p_limit, 30), 100);
$$;

-- People you may know: mutual friends first, then same target exam / district.
create or replace function public.get_friend_suggestions(p_limit int default 20)
returns table (id uuid, username text, full_name text, avatar_url text, district text,
               mutual_friends int, reason text)
language sql stable security definer
set search_path = ''
as $$
  with me as (select id, district, target_exams from public.profiles where id = auth.uid()),
  my_friends as (
    select case when f.user_a = me.id then f.user_b else f.user_a end as fid
      from public.friendships f, me where me.id in (f.user_a, f.user_b)
  ),
  fof as (
    select case when f.user_a = mf.fid then f.user_b else f.user_a end as cand, count(*)::int as mutual
      from public.friendships f join my_friends mf on mf.fid in (f.user_a, f.user_b)
     group by 1
  ),
  candidates as (
    select p.id, coalesce(fof.mutual, 0) as mutual,
           (p.district is not null and p.district = me.district) as same_district,
           (p.target_exams && me.target_exams) as same_exam,
           p.updated_at
      from public.profiles p cross join me
      left join fof on fof.cand = p.id
     where p.id <> me.id
       and not p.is_banned
       and p.onboarding_step = 'done'
       and not exists (select 1 from my_friends where fid = p.id)
       and not public.is_blocked_between(me.id, p.id)
       and not exists (select 1 from public.friend_requests r
                        where r.status = 'pending'
                          and ((r.sender_id = me.id and r.receiver_id = p.id) or (r.sender_id = p.id and r.receiver_id = me.id)))
  )
  select p.id, p.username::text, p.full_name, p.avatar_url, p.district, c.mutual,
         case when c.mutual > 0 then 'mutual' when c.same_district then 'district'
              when c.same_exam then 'same_exam' else 'new' end
    from candidates c join public.profiles p on p.id = c.id
   order by c.mutual desc, c.same_district desc, c.same_exam desc, c.updated_at desc
   limit least(coalesce(p_limit, 20), 50);
$$;

create or replace function public.search_users(p_query text, p_limit int default 20)
returns table (id uuid, username text, full_name text, avatar_url text, district text)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if char_length(trim(coalesce(p_query, ''))) < 2 then return; end if;
  return query
    select p.id, p.username::text, p.full_name, p.avatar_url, p.district
      from public.profiles p
     where not p.is_banned
       and p.id <> auth.uid()
       and not public.is_blocked_between(auth.uid(), p.id)
       and (p.username::text ilike '%' || trim(p_query) || '%' or p.full_name ilike '%' || trim(p_query) || '%')
     order by greatest(extensions.similarity(p.username::text, p_query),
                       extensions.similarity(coalesce(p.full_name, ''), p_query)) desc
     limit least(coalesce(p_limit, 20), 50);
end $$;

-- ---------------------------------------------------------------------------
-- Posts
-- ---------------------------------------------------------------------------
create table public.posts (
  id               uuid primary key default gen_random_uuid(),
  author_id        uuid not null references public.profiles (id) on delete cascade,
  body             text,
  image_paths      text[] not null default '{}',
  visibility       public.post_visibility not null default 'public',
  kind             text not null default 'text' check (kind in ('text', 'exam_result', 'note_share', 'achievement')),
  meta             jsonb not null default '{}'::jsonb,
  reaction_count   int not null default 0,
  comment_count    int not null default 0,
  reaction_summary jsonb not null default '{}'::jsonb,
  report_count     int not null default 0,
  is_hidden        boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  edited_at        timestamptz,
  constraint posts_body_len   check (body is null or char_length(body) <= 5000),
  constraint posts_images_max check (cardinality(image_paths) <= 4),
  constraint posts_not_empty  check (kind <> 'text' or coalesce(char_length(btrim(body)), 0) > 0 or cardinality(image_paths) > 0)
);
create index posts_feed_idx   on public.posts (created_at desc, id desc) where not is_hidden;
create index posts_author_idx on public.posts (author_id, created_at desc, id desc);
create trigger posts_updated_at before update on public.posts
  for each row execute function public.set_updated_at();

create or replace function public.can_view_post(p_author uuid, p_visibility public.post_visibility, p_hidden boolean)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select case
    when p_author = auth.uid() then true
    when p_hidden then public.is_staff()
    when public.is_blocked_between(p_author, auth.uid()) then false
    when p_visibility = 'public' then true
    when p_visibility = 'friends' then public.are_friends(p_author, auth.uid())
    else false
  end;
$$;

alter table public.posts enable row level security;
create policy "posts: visible" on public.posts for select to authenticated
  using (public.can_view_post(author_id, visibility, is_hidden));
create policy "posts: author inserts" on public.posts for insert to authenticated
  with check (author_id = (select auth.uid()));
create policy "posts: author updates" on public.posts for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));
create policy "posts: author or staff deletes" on public.posts for delete to authenticated
  using (author_id = (select auth.uid()) or public.is_staff());

revoke insert, update on public.posts from anon, authenticated;
grant insert (author_id, body, image_paths, visibility) on public.posts to authenticated;
grant update (body, image_paths, visibility, edited_at) on public.posts to authenticated;

create trigger posts_rate_limit before insert on public.posts
  for each row execute function public.trg_rate_limit('post_create', '15', '3600');

create or replace function public.posts_after_change()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set posts_count = posts_count + 1 where id = new.author_id;
    -- async AI moderation (no-op until the edge function + vault secrets exist)
    perform public.invoke_edge_function('moderate-content',
      jsonb_build_object('type', 'post', 'id', new.id), 10000);
    return new;
  elsif tg_op = 'DELETE' then
    update public.profiles set posts_count = greatest(posts_count - 1, 0) where id = old.author_id;
    return old;
  end if;
  return null;
end $$;
create trigger posts_after_insert after insert on public.posts
  for each row execute function public.posts_after_change();
create trigger posts_after_delete after delete on public.posts
  for each row execute function public.posts_after_change();

-- ---------------------------------------------------------------------------
-- Reactions
-- ---------------------------------------------------------------------------
create table public.post_reactions (
  post_id    uuid not null references public.posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  type       public.reaction_type not null default 'like',
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index post_reactions_user_idx on public.post_reactions (user_id);
alter table public.post_reactions enable row level security;
create policy "post_reactions: visible with post" on public.post_reactions for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id));
revoke insert, update, delete on public.post_reactions from anon, authenticated;

create or replace function public._refresh_post_reactions(p_post uuid)
returns void
language sql security definer
set search_path = ''
as $$
  update public.posts p
     set reaction_count = s.total, reaction_summary = s.summary
    from (select count(*)::int as total,
                 coalesce(jsonb_object_agg(t.type, t.c) filter (where t.type is not null), '{}'::jsonb) as summary
            from (select r.type, count(*) as c from public.post_reactions r
                   where r.post_id = p_post group by r.type) t) s
   where p.id = p_post;
$$;
revoke execute on function public._refresh_post_reactions(uuid) from public, anon, authenticated;

-- Set / change / remove (p_type = null) my reaction. Returns the new summary.
create or replace function public.react_to_post(p_post uuid, p_type public.reaction_type)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_author uuid;
  v_new    boolean;
  v_name   text;
  v_post   public.posts;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  perform public.enforce_rate_limit('react', 120, 60);
  select * into v_post from public.posts where id = p_post;
  if not found or not public.can_view_post(v_post.author_id, v_post.visibility, v_post.is_hidden) then
    raise exception 'post_not_found' using errcode = 'PT404';
  end if;
  v_author := v_post.author_id;

  if p_type is null then
    delete from public.post_reactions where post_id = p_post and user_id = v_uid;
  else
    v_new := not exists (select 1 from public.post_reactions where post_id = p_post and user_id = v_uid);
    insert into public.post_reactions (post_id, user_id, type) values (p_post, v_uid, p_type)
    on conflict (post_id, user_id) do update set type = excluded.type;
    if v_new then
      select coalesce(full_name, username::text) into v_name from public.profiles where id = v_uid;
      perform public.notify_user(v_author, 'post_reaction', 'নতুন প্রতিক্রিয়া',
        v_name || ' আপনার পোস্টে প্রতিক্রিয়া জানিয়েছেন', jsonb_build_object('post_id', p_post), v_uid, 'social');
    end if;
  end if;

  perform public._refresh_post_reactions(p_post);
  return (select jsonb_build_object('reaction_count', reaction_count, 'reaction_summary', reaction_summary,
                                    'my_reaction', p_type)
            from public.posts where id = p_post);
end $$;

-- ---------------------------------------------------------------------------
-- Comments (one level of replies) + comment likes
-- ---------------------------------------------------------------------------
create table public.comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts (id) on delete cascade,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  parent_id   uuid references public.comments (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 2000),
  like_count  int not null default 0,
  reply_count int not null default 0,
  is_hidden   boolean not null default false,
  created_at  timestamptz not null default now(),
  edited_at   timestamptz
);
create index comments_post_idx   on public.comments (post_id, created_at, id) where parent_id is null;
create index comments_parent_idx on public.comments (parent_id, created_at, id) where parent_id is not null;
create index comments_author_idx on public.comments (author_id);

alter table public.comments enable row level security;
create policy "comments: visible with post" on public.comments for select to authenticated
  using ((not is_hidden or author_id = (select auth.uid()) or public.is_staff())
         and exists (select 1 from public.posts p where p.id = post_id));
create policy "comments: author inserts" on public.comments for insert to authenticated
  with check (author_id = (select auth.uid()) and exists (select 1 from public.posts p where p.id = post_id));
create policy "comments: author updates" on public.comments for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));
create policy "comments: author, post owner or staff deletes" on public.comments for delete to authenticated
  using (author_id = (select auth.uid()) or public.is_staff()
         or exists (select 1 from public.posts p where p.id = post_id and p.author_id = (select auth.uid())));
revoke insert, update on public.comments from anon, authenticated;
grant insert (post_id, author_id, parent_id, body) on public.comments to authenticated;
grant update (body, edited_at) on public.comments to authenticated;

create trigger comments_rate_limit before insert on public.comments
  for each row execute function public.trg_rate_limit('comment_create', '60', '3600');

create or replace function public.comments_before_insert()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare v_parent public.comments;
begin
  if new.parent_id is not null then
    select * into v_parent from public.comments where id = new.parent_id;
    if not found or v_parent.post_id <> new.post_id then raise exception 'invalid_parent'; end if;
    -- flatten: replies to replies attach to the top-level comment
    if v_parent.parent_id is not null then new.parent_id := v_parent.parent_id; end if;
  end if;
  return new;
end $$;
create trigger comments_before_insert before insert on public.comments
  for each row execute function public.comments_before_insert();

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
        jsonb_build_object('post_id', new.post_id, 'comment_id', new.id), new.author_id, 'social');
    end if;
    if v_post_author is distinct from v_parent_author then
      perform public.notify_user(v_post_author, 'post_comment', 'নতুন মন্তব্য',
        v_name || ' আপনার পোস্টে মন্তব্য করেছেন: ' || left(new.body, 80),
        jsonb_build_object('post_id', new.post_id, 'comment_id', new.id), new.author_id, 'social');
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
create trigger comments_after_insert after insert on public.comments
  for each row execute function public.comments_after_change();
create trigger comments_after_delete after delete on public.comments
  for each row execute function public.comments_after_change();

create table public.comment_likes (
  comment_id uuid not null references public.comments (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
alter table public.comment_likes enable row level security;
create policy "comment_likes: readable" on public.comment_likes for select to authenticated using (true);
revoke insert, update, delete on public.comment_likes from anon, authenticated;

create or replace function public.toggle_comment_like(p_comment uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_liked boolean;
  v_count int;
begin
  perform public.enforce_rate_limit('react', 120, 60);
  delete from public.comment_likes where comment_id = p_comment and user_id = v_uid;
  if found then
    v_liked := false;
  else
    insert into public.comment_likes (comment_id, user_id) values (p_comment, v_uid);
    v_liked := true;
  end if;
  update public.comments
     set like_count = (select count(*) from public.comment_likes where comment_id = p_comment)
   where id = p_comment returning like_count into v_count;
  return jsonb_build_object('liked', v_liked, 'like_count', v_count);
end $$;

-- ---------------------------------------------------------------------------
-- Feed & comment listing RPCs (security invoker → RLS decides visibility)
-- ---------------------------------------------------------------------------
create or replace function public.get_feed(
  p_limit int default 20,
  p_before_created timestamptz default null,
  p_before_id uuid default null,
  p_author uuid default null,
  p_post uuid default null
)
returns table (
  id uuid, author_id uuid, author_username text, author_full_name text, author_avatar_url text,
  body text, image_paths text[], visibility public.post_visibility, kind text, meta jsonb,
  reaction_count int, comment_count int, reaction_summary jsonb, my_reaction public.reaction_type,
  created_at timestamptz, edited_at timestamptz
)
language sql stable security invoker
set search_path = ''
as $$
  select p.id, p.author_id, pr.username::text, pr.full_name, pr.avatar_url,
         p.body, p.image_paths, p.visibility, p.kind, p.meta,
         p.reaction_count, p.comment_count, p.reaction_summary,
         (select r.type from public.post_reactions r where r.post_id = p.id and r.user_id = auth.uid()),
         p.created_at, p.edited_at
    from public.posts p
    join public.profiles pr on pr.id = p.author_id
   where (p_post is null or p.id = p_post)
     and (p_author is null or p.author_id = p_author)
     and (p_post is not null or not p.is_hidden)
     and (p_before_created is null
          or (p.created_at, p.id) < (p_before_created, coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
   order by p.created_at desc, p.id desc
   limit least(coalesce(p_limit, 20), 50);
$$;

create or replace function public.get_comments(
  p_post uuid, p_parent uuid default null, p_limit int default 20,
  p_after_created timestamptz default null, p_after_id uuid default null
)
returns table (
  id uuid, post_id uuid, parent_id uuid, author_id uuid, author_username text,
  author_full_name text, author_avatar_url text, body text, like_count int, reply_count int,
  liked_by_me boolean, created_at timestamptz, edited_at timestamptz
)
language sql stable security invoker
set search_path = ''
as $$
  select c.id, c.post_id, c.parent_id, c.author_id, pr.username::text, pr.full_name, pr.avatar_url,
         c.body, c.like_count, c.reply_count,
         exists (select 1 from public.comment_likes l where l.comment_id = c.id and l.user_id = auth.uid()),
         c.created_at, c.edited_at
    from public.comments c
    join public.profiles pr on pr.id = c.author_id
   where c.post_id = p_post
     and ((p_parent is null and c.parent_id is null) or c.parent_id = p_parent)
     and (p_after_created is null
          or (c.created_at, c.id) > (p_after_created, coalesce(p_after_id, '00000000-0000-0000-0000-000000000000'::uuid)))
   order by c.created_at, c.id
   limit least(coalesce(p_limit, 20), 50);
$$;

-- ---------------------------------------------------------------------------
-- Reports (auto-hide content after 5 open reports)
-- ---------------------------------------------------------------------------
create table public.reports (
  id          bigint generated always as identity primary key,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_type text not null check (target_type in ('post', 'comment', 'user', 'message', 'question')),
  target_id   text not null,
  reason      text not null check (reason in ('spam', 'abuse', 'nudity', 'violence', 'misinformation', 'wrong_answer', 'other')),
  details     text check (details is null or char_length(details) <= 1000),
  status      text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  created_at  timestamptz not null default now(),
  unique (reporter_id, target_type, target_id)
);
create index reports_open_idx on public.reports (status, created_at desc);
alter table public.reports enable row level security;
create policy "reports: reporter inserts" on public.reports for insert to authenticated
  with check (reporter_id = (select auth.uid()));
create policy "reports: reporter or staff reads" on public.reports for select to authenticated
  using (reporter_id = (select auth.uid()) or public.is_staff());
create policy "reports: staff updates" on public.reports for update to authenticated
  using (public.is_staff()) with check (public.is_staff());
create trigger reports_rate_limit before insert on public.reports
  for each row execute function public.trg_rate_limit('report', '30', '86400');

create or replace function public.reports_after_insert()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare v_open int;
begin
  select count(*) into v_open from public.reports
   where target_type = new.target_type and target_id = new.target_id and status = 'open';
  if new.target_type = 'post' then
    update public.posts set report_count = v_open,
           is_hidden = is_hidden or v_open >= 5
     where id = new.target_id::uuid;
  elsif new.target_type = 'comment' and v_open >= 5 then
    update public.comments set is_hidden = true where id = new.target_id::uuid;
  elsif new.target_type = 'question' and v_open >= 3 then
    update public.questions set review_status = 'flagged' where id = new.target_id::bigint;
  end if;
  return new;
end $$;
create trigger reports_after_insert after insert on public.reports
  for each row execute function public.reports_after_insert();

-- Share an exam result to the feed (server builds the payload; can't be faked).
create or replace function public.share_exam_result(p_session uuid, p_body text default null)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_s  record;
  v_id uuid;
begin
  select * into v_s from public.exam_sessions where id = p_session and user_id = auth.uid() and status = 'submitted';
  if not found then raise exception 'session_not_found' using errcode = 'PT404'; end if;
  insert into public.posts (author_id, body, kind, meta, visibility)
  values (auth.uid(), nullif(btrim(p_body), ''), 'exam_result',
          jsonb_build_object('session_id', v_s.id, 'title', v_s.title, 'kind', v_s.kind,
                             'score', v_s.score, 'max_score', v_s.max_score, 'correct', v_s.correct,
                             'wrong', v_s.wrong, 'total', v_s.total),
          'public')
  returning id into v_id;
  return v_id;
end $$;
