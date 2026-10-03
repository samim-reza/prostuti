-- ============================================================================
-- 0001 · Foundation
-- Extensions, shared helpers, remote config, profiles, roles, rate limiting,
-- notifications. Everything else builds on this file.
-- ============================================================================

-- Functions may reference tables created by later migrations.
set check_function_bodies = off;

create extension if not exists citext   with schema extensions;
create extension if not exists pg_trgm  with schema extensions;
create extension if not exists vector   with schema extensions;
create extension if not exists pg_net   with schema extensions;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------
-- Time helpers. The whole product runs on Bangladesh time (UTC+6, no DST):
-- "today's notes", streaks, routines and reminders all use these.
-- ---------------------------------------------------------------------------
create or replace function public.bd_now()
returns timestamp
language sql stable
set search_path = ''
as $$ select (now() at time zone 'Asia/Dhaka') $$;

create or replace function public.bd_today()
returns date
language sql stable
set search_path = ''
as $$ select (now() at time zone 'Asia/Dhaka')::date $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Remote config (feature flags, min app version, schedule times …).
-- Public rows are readable by everyone, including signed-out clients.
-- ---------------------------------------------------------------------------
create table public.app_config (
  key         text primary key,
  value       jsonb not null,
  description text,
  is_public   boolean not null default true,
  updated_at  timestamptz not null default now()
);
alter table public.app_config enable row level security;
create policy "app_config: public rows readable"
  on public.app_config for select to anon, authenticated using (is_public);
create trigger app_config_updated_at before update on public.app_config
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('user', 'moderator', 'admin');

create table public.profiles (
  id                    uuid primary key references auth.users (id) on delete cascade,
  username              extensions.citext unique,
  full_name             text,
  avatar_url            text,
  bio                   text,
  district              text,
  education             jsonb not null default '{}'::jsonb,
  occupation            text,
  target_exams          text[] not null default array['bcs'],
  target_schedule_id    bigint,
  daily_study_minutes   int not null default 120,
  onboarding_step       text not null default 'profile',
  role                  public.user_role not null default 'user',
  reminder_time         time not null default '20:00',
  reminder_enabled      boolean not null default true,
  notification_settings jsonb not null default
    '{"social": true, "daily_notes": true, "routine": true, "exam": true, "chat": true}'::jsonb,
  locale                text not null default 'bn',
  allow_messages_from   text not null default 'friends',
  streak_count          int not null default 0,
  longest_streak        int not null default 0,
  last_active_date      date,
  friends_count         int not null default 0,
  posts_count           int not null default 0,
  exams_taken           int not null default 0,
  is_banned             boolean not null default false,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint profiles_username_format check (username is null or username ~ '^[a-zA-Z0-9_.]{3,24}$'),
  constraint profiles_full_name_len  check (full_name is null or char_length(full_name) <= 80),
  constraint profiles_bio_len        check (bio is null or char_length(bio) <= 300),
  constraint profiles_minutes_range  check (daily_study_minutes between 15 and 960),
  constraint profiles_onboarding     check (onboarding_step in ('profile', 'interview', 'placement', 'plan', 'done')),
  constraint profiles_locale         check (locale in ('bn', 'en')),
  constraint profiles_allow_messages check (allow_messages_from in ('friends', 'everyone'))
);
create index profiles_username_trgm on public.profiles using gin (username extensions.gin_trgm_ops);
create index profiles_full_name_trgm on public.profiles using gin (full_name extensions.gin_trgm_ops);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
create policy "profiles: readable by signed-in users"
  on public.profiles for select to authenticated using (true);
create policy "profiles: owner can update"
  on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Column-level privileges: users may only edit their own *editable* columns.
-- Counters, role and streaks are maintained by triggers / security-definer RPCs.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (username, full_name, avatar_url, bio, district, education, occupation,
              target_exams, target_schedule_id, daily_study_minutes, onboarding_step,
              reminder_time, reminder_enabled, notification_settings, locale,
              allow_messages_from)
  on public.profiles to authenticated;

-- Private, owner-only personal data collected during onboarding.
create table public.user_private (
  user_id       uuid primary key references public.profiles (id) on delete cascade,
  date_of_birth date,
  gender        text,
  phone         text,
  personal      jsonb not null default '{}'::jsonb,
  updated_at    timestamptz not null default now()
);
alter table public.user_private enable row level security;
create policy "user_private: owner all"
  on public.user_private for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create trigger user_private_updated_at before update on public.user_private
  for each row execute function public.set_updated_at();

-- Role helpers ---------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.is_staff()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'moderator'));
$$;

-- ---------------------------------------------------------------------------
-- Rate limiting (fixed window, per user + action).
-- Raises SQLSTATE PT429 → PostgREST answers HTTP 429 to the client.
-- Internal callers (cron / service role, auth.uid() is null) are not limited.
-- p_window_seconds = 0 means "one Bangladesh calendar day" (used for quotas).
-- The counter table is UNLOGGED: fast, and losing it on crash is harmless.
-- ---------------------------------------------------------------------------
create unlogged table public.rate_limit_counters (
  bucket       text not null,
  window_start timestamptz not null,
  hits         int not null default 0,
  primary key (bucket, window_start)
);
alter table public.rate_limit_counters enable row level security;

create or replace function public.enforce_rate_limit(
  p_action text, p_max int, p_window_seconds int, p_subject text default null
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_subject text := coalesce(p_subject, auth.uid()::text);
  v_window  timestamptz;
  v_end     timestamptz;
  v_hits    int;
begin
  if v_subject is null then
    return; -- internal call (cron, service role, migrations)
  end if;
  if p_window_seconds <= 0 then
    v_window := public.bd_today()::timestamp at time zone 'Asia/Dhaka';
    v_end    := v_window + interval '1 day';
  else
    v_window := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
    v_end    := v_window + make_interval(secs => p_window_seconds);
  end if;
  insert into public.rate_limit_counters as c (bucket, window_start, hits)
  values (p_action || ':' || v_subject, v_window, 1)
  on conflict (bucket, window_start) do update set hits = c.hits + 1
  returning c.hits into v_hits;
  if v_hits > p_max then
    raise exception 'rate_limited'
      using errcode = 'PT429',
            detail  = p_action,
            hint    = 'retry_after:' || ceil(extract(epoch from (v_end - now())))::int;
  end if;
end $$;

-- Generic trigger wrapper: execute function public.trg_rate_limit('action', 'max', 'window_seconds')
create or replace function public.trg_rate_limit()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  perform public.enforce_rate_limit(tg_argv[0], tg_argv[1]::int, tg_argv[2]::int);
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Add-ons & feature entitlements.
-- What is free vs. paid is DATA (features.is_free / addons.features), so the
-- business can repackage the product without shipping a new app build.
-- ---------------------------------------------------------------------------
create table public.features (
  code             text primary key,
  name_bn          text not null,
  name_en          text not null,
  description_bn   text,
  description_en   text,
  is_free          boolean not null default false,
  free_daily_quota int,
  sort             int not null default 0
);
alter table public.features enable row level security;
create policy "features: readable" on public.features for select to anon, authenticated using (true);

create table public.addons (
  code            text primary key,
  name_bn         text not null,
  name_en         text not null,
  description_bn  text,
  description_en  text,
  features        text[] not null,
  price_bdt       numeric(10, 2) not null check (price_bdt >= 0),
  period_days     int not null default 30 check (period_days > 0),
  trial_days      int not null default 7 check (trial_days >= 0),
  badge           text,
  color           text,
  icon            text,
  is_active       boolean not null default true,
  sort            int not null default 0,
  created_at      timestamptz not null default now()
);
alter table public.addons enable row level security;
create policy "addons: readable" on public.addons for select to anon, authenticated using (is_active or public.is_admin());

create table public.user_entitlements (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  addon_code  text not null references public.addons (code),
  source      text not null check (source in ('trial', 'purchase', 'promo', 'admin')),
  starts_at   timestamptz not null default now(),
  expires_at  timestamptz not null,
  payment_id  uuid,
  created_at  timestamptz not null default now(),
  check (expires_at > starts_at)
);
create index user_entitlements_user_idx on public.user_entitlements (user_id, expires_at desc);
alter table public.user_entitlements enable row level security;
create policy "user_entitlements: owner reads" on public.user_entitlements
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());

create table public.payments (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  addon_code   text not null references public.addons (code),
  amount_bdt   numeric(10, 2) not null,
  provider     text not null,
  provider_ref text,
  status       text not null default 'initiated' check (status in ('initiated', 'success', 'failed', 'refunded')),
  raw          jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index payments_user_idx on public.payments (user_id, created_at desc);
alter table public.payments enable row level security;
create policy "payments: owner reads" on public.payments
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
create trigger payments_updated_at before update on public.payments
  for each row execute function public.set_updated_at();

create table public.promo_codes (
  code             extensions.citext primary key,
  addon_code       text not null references public.addons (code),
  days             int not null check (days > 0),
  max_redemptions  int,
  redeemed_count   int not null default 0,
  expires_at       timestamptz,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);
alter table public.promo_codes enable row level security;
create policy "promo_codes: admin only" on public.promo_codes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create table public.promo_redemptions (
  code        extensions.citext not null references public.promo_codes (code) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  primary key (code, user_id)
);
alter table public.promo_redemptions enable row level security;
create policy "promo_redemptions: owner reads" on public.promo_redemptions
  for select to authenticated using (user_id = (select auth.uid()));

-- Internal: does a given user have a feature right now?
create or replace function public.user_has_feature(p_user uuid, p_feature text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce((select f.is_free from public.features f where f.code = p_feature), false)
      or exists (
           select 1
             from public.user_entitlements e
             join public.addons a on a.code = e.addon_code
            where e.user_id = p_user
              and e.starts_at <= now() and e.expires_at > now()
              and p_feature = any (a.features))
      or exists (select 1 from public.profiles p where p.id = p_user and p.role = 'admin');
$$;
revoke execute on function public.user_has_feature(uuid, text) from public, anon, authenticated;

-- Client-facing: checks the *calling* user only.
create or replace function public.has_feature(p_feature text)
returns boolean
language sql stable security definer
set search_path = ''
as $$ select public.user_has_feature(auth.uid(), p_feature); $$;

-- Raises PT402 (HTTP 402 "payment required") when the feature is locked.
-- Free users of a quota'd feature get `free_daily_quota` uses per BD day.
create or replace function public.require_feature(p_feature text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_quota int;
begin
  if auth.uid() is null or public.user_has_feature(auth.uid(), p_feature) then
    return;
  end if;
  select free_daily_quota into v_quota from public.features where code = p_feature;
  if v_quota is not null and v_quota > 0 then
    -- Window 0 = one Bangladesh calendar day.
    perform public.enforce_rate_limit('quota:' || p_feature, v_quota, 0);
    return;
  end if;
  raise exception 'feature_locked' using errcode = 'PT402', detail = p_feature;
end $$;

-- One round-trip for the client: { feature_code: true/false, … }
create or replace function public.get_feature_access()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(f.code, public.user_has_feature(auth.uid(), f.code)), '{}'::jsonb)
    from public.features f;
$$;

create or replace function public.redeem_promo(p_code text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_promo  public.promo_codes;
  v_start  timestamptz;
  v_expiry timestamptz;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = 'PT401'; end if;
  perform public.enforce_rate_limit('redeem_promo', 10, 3600);

  select * into v_promo from public.promo_codes
   where code = trim(p_code)::extensions.citext and is_active
   for update;
  if not found or (v_promo.expires_at is not null and v_promo.expires_at < now()) then
    raise exception 'promo_invalid';
  end if;
  if v_promo.max_redemptions is not null and v_promo.redeemed_count >= v_promo.max_redemptions then
    raise exception 'promo_exhausted';
  end if;

  insert into public.promo_redemptions (code, user_id) values (v_promo.code, v_uid)
  on conflict do nothing;
  if not found then raise exception 'promo_already_used'; end if;

  update public.promo_codes set redeemed_count = redeemed_count + 1 where code = v_promo.code;

  -- Stack on top of any running entitlement for the same add-on.
  select greatest(now(), coalesce(max(expires_at), now())) into v_start
    from public.user_entitlements where user_id = v_uid and addon_code = v_promo.addon_code;
  v_expiry := v_start + make_interval(days => v_promo.days);

  insert into public.user_entitlements (user_id, addon_code, source, starts_at, expires_at)
  values (v_uid, v_promo.addon_code, 'promo', v_start, v_expiry);

  return jsonb_build_object('addon_code', v_promo.addon_code, 'expires_at', v_expiry, 'days', v_promo.days);
end $$;

create or replace function public.admin_grant_addon(p_user uuid, p_addon text, p_days int)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_start timestamptz;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = 'PT403'; end if;
  select greatest(now(), coalesce(max(expires_at), now())) into v_start
    from public.user_entitlements where user_id = p_user and addon_code = p_addon;
  insert into public.user_entitlements (user_id, addon_code, source, starts_at, expires_at)
  values (p_user, p_addon, 'admin', v_start, v_start + make_interval(days => p_days));
end $$;

-- ---------------------------------------------------------------------------
-- Notifications (in-app inbox, Realtime-enabled) + push outbox (FCM).
-- ---------------------------------------------------------------------------
create table public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  type       text not null,
  title      text not null,
  body       text,
  data       jsonb not null default '{}'::jsonb,
  actor_id   uuid references public.profiles (id) on delete set null,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx   on public.notifications (user_id, created_at desc, id desc);
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;
alter table public.notifications enable row level security;
create policy "notifications: owner reads"   on public.notifications for select to authenticated using (user_id = (select auth.uid()));
create policy "notifications: owner updates" on public.notifications for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "notifications: owner deletes" on public.notifications for delete to authenticated using (user_id = (select auth.uid()));
revoke insert, update on public.notifications from anon, authenticated;
grant update (read_at) on public.notifications to authenticated;

create table public.device_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  platform   text not null default 'android',
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
create policy "device_tokens: owner reads" on public.device_tokens for select to authenticated using (user_id = (select auth.uid()));
create policy "device_tokens: owner deletes" on public.device_tokens for delete to authenticated using (user_id = (select auth.uid()));

create table public.push_outbox (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  title      text not null,
  body       text,
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  attempts   int not null default 0,
  last_error text
);
create index push_outbox_pending_idx on public.push_outbox (created_at) where sent_at is null;
alter table public.push_outbox enable row level security; -- service role only

create or replace function public.register_device_token(p_token text, p_platform text default 'android')
returns void
language sql security definer
set search_path = ''
as $$
  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), p_platform, now())
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
$$;

-- Internal helper used by triggers / RPCs. Respects the user's notification
-- settings category and queues a push (sent only if FCM is configured).
create or replace function public.notify_user(
  p_user uuid, p_type text, p_title text, p_body text default null,
  p_data jsonb default '{}'::jsonb, p_actor uuid default null, p_category text default 'social'
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_settings jsonb;
begin
  if p_user is null or p_user = p_actor then return; end if;
  select notification_settings into v_settings from public.profiles where id = p_user;
  insert into public.notifications (user_id, type, title, body, data, actor_id)
  values (p_user, p_type, p_title, p_body, p_data, p_actor);
  if coalesce((v_settings ->> p_category)::boolean, true) then
    insert into public.push_outbox (user_id, title, body, data)
    values (p_user, p_title, p_body, p_data || jsonb_build_object('type', p_type));
  end if;
end $$;
revoke execute on function public.notify_user(uuid, text, text, text, jsonb, uuid, text) from public, anon, authenticated;

create or replace function public.mark_notifications_read(p_ids bigint[] default null)
returns void
language sql security definer
set search_path = ''
as $$
  update public.notifications set read_at = now()
   where user_id = auth.uid() and read_at is null
     and (p_ids is null or id = any (p_ids));
$$;

-- ---------------------------------------------------------------------------
-- Activity streak — called whenever the user studies (exam, plan item …).
-- ---------------------------------------------------------------------------
create or replace function public.touch_streak(p_user uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_today date := public.bd_today();
begin
  update public.profiles p
     set streak_count = case
                          when p.last_active_date = v_today then p.streak_count
                          when p.last_active_date = v_today - 1 then p.streak_count + 1
                          else 1 end,
         longest_streak = greatest(p.longest_streak, case
                          when p.last_active_date = v_today then p.streak_count
                          when p.last_active_date = v_today - 1 then p.streak_count + 1
                          else 1 end),
         last_active_date = v_today
   where p.id = p_user;
end $$;
revoke execute on function public.touch_streak(uuid) from public, anon, authenticated;
