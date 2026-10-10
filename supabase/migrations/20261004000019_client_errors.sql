-- ============================================================================
-- 0019 · Client error reports (crash reporting without a third-party SDK)
--
-- Release builds of the app send uncaught errors through log_client_error().
-- The table is write-only for clients: RLS is on and there is no policy, so
-- only the dashboard / service role can read it. Rows live for 30 days.
--
--   * inputs are truncated server-side (the client truncates too);
--   * signed-in callers: 30 reports per user per hour (enforce_rate_limit);
--     signed-out callers share one global bucket of 60 per minute;
--   * the same fingerprint from the same user within an hour only bumps
--     `occurrences` on the existing row instead of adding a new one.
-- ============================================================================

create table if not exists public.client_errors (
  id           bigint generated always as identity primary key,
  user_id      uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  occurrences  int not null default 1,
  app_version  text,
  build_number text,
  platform     text,
  os           text,
  locale       text,
  route        text,
  context      text,
  error        text not null,
  stack        text,
  fatal        boolean not null default false,
  fingerprint  text not null,
  constraint client_errors_error_len   check (char_length(error) <= 1000),
  constraint client_errors_stack_len   check (stack is null or char_length(stack) <= 8000),
  constraint client_errors_fp_len      check (char_length(fingerprint) between 1 and 64),
  constraint client_errors_meta_len    check (
    coalesce(char_length(app_version), 0) <= 32 and coalesce(char_length(build_number), 0) <= 16 and
    coalesce(char_length(platform), 0) <= 16 and coalesce(char_length(os), 0) <= 160 and
    coalesce(char_length(locale), 0) <= 16 and coalesce(char_length(route), 0) <= 200 and
    coalesce(char_length(context), 0) <= 300)
);

-- Dedupe lookup (fingerprint within the last hour) and the 30-day purge.
create index if not exists client_errors_fingerprint_idx on public.client_errors (fingerprint, created_at desc);
create index if not exists client_errors_created_idx on public.client_errors (created_at);

alter table public.client_errors enable row level security;
-- No policies: clients can neither read nor write the table directly.
revoke all on public.client_errors from anon, authenticated;

-- ---------------------------------------------------------------------------
-- log_client_error(...) → true when a new row was stored, false when the
-- report was merged into a recent duplicate, rate-limited or empty.
-- Never raises for rate limits, so the app's fire-and-forget call stays quiet.
-- ---------------------------------------------------------------------------
create or replace function public.log_client_error(
  p_error        text,
  p_fingerprint  text,
  p_stack        text default null,
  p_fatal        boolean default false,
  p_app_version  text default null,
  p_build_number text default null,
  p_platform     text default null,
  p_os           text default null,
  p_locale       text default null,
  p_route        text default null,
  p_context      text default null
)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_error text := nullif(btrim(left(p_error, 1000)), '');
  v_fp    text := nullif(btrim(left(p_fingerprint, 64)), '');
  v_dup   bigint;
begin
  if v_error is null then
    return false;
  end if;
  v_fp := coalesce(v_fp, md5(v_error));

  begin
    if v_uid is null then
      -- Signed-out (or pre-login) crashes: one small shared bucket.
      perform public.enforce_rate_limit('client_error_anon', 60, 60, 'anon');
    else
      perform public.enforce_rate_limit('client_error', 30, 3600);
    end if;
  exception when sqlstate 'PT429' then
    return false;
  end;

  select id into v_dup
    from public.client_errors
   where fingerprint = v_fp
     and created_at > now() - interval '1 hour'
     and (user_id = v_uid or (v_uid is null and user_id is null))
   order by created_at desc
   limit 1;

  if v_dup is not null then
    update public.client_errors
       set occurrences = occurrences + 1, last_seen_at = now(), fatal = fatal or coalesce(p_fatal, false)
     where id = v_dup;
    return false;
  end if;

  insert into public.client_errors (user_id, app_version, build_number, platform, os, locale, route, context,
                                    error, stack, fatal, fingerprint)
  values (v_uid,
          nullif(left(p_app_version, 32), ''),
          nullif(left(p_build_number, 16), ''),
          nullif(left(p_platform, 16), ''),
          nullif(left(p_os, 160), ''),
          nullif(left(p_locale, 16), ''),
          nullif(left(p_route, 200), ''),
          nullif(left(p_context, 300), ''),
          v_error,
          nullif(left(p_stack, 8000), ''),
          coalesce(p_fatal, false),
          v_fp);
  return true;
end $$;

revoke execute on function public.log_client_error(text, text, text, boolean, text, text, text, text, text, text, text)
  from public;
grant execute on function public.log_client_error(text, text, text, boolean, text, text, text, text, text, text, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 30-day retention (daily, 03:17 Bangladesh time). A separate job instead of
-- editing housekeeping(), so this migration never overwrites that function.
-- ---------------------------------------------------------------------------
create or replace function public.purge_client_errors()
returns void
language sql security definer
set search_path = ''
as $$
  delete from public.client_errors where created_at < now() - interval '30 days';
$$;
revoke execute on function public.purge_client_errors() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'prostuti-client-errors-purge') then
    perform cron.unschedule('prostuti-client-errors-purge');
  end if;
end $$;
select cron.schedule('prostuti-client-errors-purge', '17 21 * * *', $$select public.purge_client_errors()$$);
