-- ============================================================================
-- Row-Level-Security smoke test. Runs entirely inside a transaction that is
-- rolled back, so it never leaves data behind.
--
--   tools/db.sh file tools/rls_smoke_test.sql
--
-- Needs the two QA users (qa.rahim@ / qa.karim@prostuti.app). Every check
-- raises an exception on failure; success prints "ALL RLS CHECKS PASSED".
-- ============================================================================
\set ON_ERROR_STOP on
begin;

-- ---------------------------------------------------------------------------
-- Fixtures (as the table owner)
-- ---------------------------------------------------------------------------
create temp table t_users as
select (select id from auth.users where email = 'qa.rahim@prostuti.app') as rahim,
       (select id from auth.users where email = 'qa.karim@prostuti.app') as karim;
grant select on t_users to authenticated;

do $$
declare r uuid := (select rahim from t_users); k uuid := (select karim from t_users); c uuid;
begin
  if r is null or k is null then raise exception 'QA users missing'; end if;
  -- a past note that must stay invisible to users
  insert into public.daily_notes (note_date, category, title, summary)
  values (public.bd_today() - 1, 'misc', 'yesterday', 'old');
  -- a private conversation between karim and nobody else rahim can see
  insert into public.conversations (kind, title, created_by) values ('group', 'karim only', k) returning id into c;
  insert into public.conversation_members (conversation_id, user_id) values (c, k);
  insert into public.messages (conversation_id, sender_id, body) values (c, k, 'secret');
  insert into public.notifications (user_id, type, title) values (k, 'system', 'karim private');
end $$;

-- ---------------------------------------------------------------------------
-- Act as rahim
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', (select rahim from t_users), 'role', 'authenticated')::text, true);
set local role authenticated;

do $$
declare n int; ok boolean;
begin
  -- 1. Correct answers cannot be read directly.
  begin
    perform correct_index from public.questions limit 1;
    raise exception 'FAIL: correct_index readable';
  exception when insufficient_privilege then null;
  end;

  -- 2. Only today's notes are visible.
  select count(*) into n from public.daily_notes where note_date < public.bd_today();
  if n <> 0 then raise exception 'FAIL: % past notes visible', n; end if;

  -- 3. Study plan only up to today + 2.
  select count(*) into n from public.study_plan_days where day_date > public.bd_today() + 2;
  if n <> 0 then raise exception 'FAIL: % future plan days visible', n; end if;

  -- 4. Someone else's chat and notifications are invisible.
  select count(*) into n from public.messages where body = 'secret';
  if n <> 0 then raise exception 'FAIL: foreign messages visible'; end if;
  select count(*) into n from public.notifications where title = 'karim private';
  if n <> 0 then raise exception 'FAIL: foreign notifications visible'; end if;

  -- 5. Cannot promote yourself to admin (column privilege).
  begin
    update public.profiles set role = 'admin' where id = auth.uid();
    raise exception 'FAIL: role column writable';
  exception when insufficient_privilege then null;
  end;

  -- 6. Cannot edit another user's profile (RLS → 0 rows).
  update public.profiles set bio = 'hacked' where id = (select karim from t_users);
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: edited someone else''s profile'; end if;

  -- 7. Cannot create exam sessions or entitlements directly.
  begin
    insert into public.user_entitlements (user_id, addon_code, source, expires_at)
    values (auth.uid(), 'prostuti_pro', 'admin', now() + interval '1 year');
    raise exception 'FAIL: self-granted entitlement';
  exception when insufficient_privilege or check_violation then null;
           when others then if sqlstate = '42501' then null; else raise; end if;
  end;

  -- 8. Rate limit on posts: 15/hour, the 16th must fail with PT429.
  begin
    for i in 1..16 loop
      insert into public.posts (author_id, body) values (auth.uid(), 'rate limit probe ' || i);
    end loop;
    raise exception 'FAIL: post rate limit not enforced';
  exception when sqlstate 'PT429' then null;
  end;

  raise notice 'rahim checks passed';
end $$;

-- ---------------------------------------------------------------------------
-- Paywall: remove rahim's entitlements (as owner), then a paid feature must
-- raise PT402 while free features keep working.
-- ---------------------------------------------------------------------------
reset role;
delete from public.user_entitlements where user_id = (select rahim from t_users);
set local role authenticated;

do $$
begin
  if not public.has_feature('daily_notes') then raise exception 'FAIL: free feature locked'; end if;
  begin
    perform public.require_feature('daily_exam');
    raise exception 'FAIL: paid feature not locked';
  exception when sqlstate 'PT402' then null;
  end;
  raise notice 'paywall checks passed';
end $$;

reset role;
do $$ begin raise notice 'ALL RLS CHECKS PASSED'; end $$;
rollback;
