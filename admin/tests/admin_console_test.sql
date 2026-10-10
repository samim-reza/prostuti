-- ============================================================================
-- Admin console RPC regression test (migration 20261004000020).
-- Runs in ONE transaction that is rolled back: nothing is left behind.
--
--   tools/db.sh file admin/tests/admin_console_test.sql
--
-- Needs the two QA users (qa.rahim@ / qa.karim@prostuti.app), like
-- tools/rls_smoke_test.sql. Loads 0019 and 0020 (both idempotent) so it also
-- works before they are applied. Success prints "ALL ADMIN CONSOLE CHECKS PASSED".
-- ============================================================================
\set ON_ERROR_STOP on
begin;

-- exam_tracks comes from 0016; stub it on databases that predate it.
do $$
begin
  if to_regclass('public.exam_tracks') is null then
    create table public.exam_tracks (
      code text primary key check (code in ('bcs', 'bank', 'govt')),
      name_bn text not null, name_en text not null, description_bn text, description_en text,
      sizes int[] not null, full_marks int not null, negative_mark numeric(3, 2) not null,
      seconds_per_question int not null, distribution jsonb not null, sort int not null default 0,
      is_active boolean not null default true);
    alter table public.exam_tracks enable row level security;
    insert into public.exam_tracks values
      ('bcs', 'বিসিএস', 'BCS', null, null, '{25,50,100,200}', 200, 0.50, 36,
       '{"bangla": 30, "english": 30, "bd_affairs": 25, "international": 25, "geography": 10, "science": 15, "computer": 15, "math": 20, "mental_ability": 15, "ethics": 15}', 0, true),
      ('bank', 'ব্যাংক', 'Bank', null, null, '{25,50,100}', 100, 0.25, 36,
       '{"bangla": 20, "english": 30, "math": 30, "international": 20}', 1, true);
  end if;
end $$;

-- Load the migrations under test (idempotent; harmless when already applied).
\ir ../../supabase/migrations/20261004000019_client_errors.sql
\ir ../../supabase/migrations/20261004000020_admin_console.sql

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
create temp table t_ctx (k text primary key, v text);
grant select, insert, update on t_ctx to authenticated;
insert into t_ctx
select 'rahim', id::text from auth.users where email = 'qa.rahim@prostuti.app' union all
select 'karim', id::text from auth.users where email = 'qa.karim@prostuti.app' union all
select 'post',  (select id::text from public.posts order by created_at limit 1) union all
select 'note_date', (select max(note_date)::text from public.daily_notes) union all
select 'exam_date', (select max(exam_date)::text from public.daily_exams);
update public.profiles set role = 'admin' where id = (select v::uuid from t_ctx where k = 'rahim');
insert into public.reports (reporter_id, target_type, target_id, reason, details)
values ((select v::uuid from t_ctx where k = 'karim'), 'post', (select v from t_ctx where k = 'post'), 'spam', 'test report');
insert into public.client_errors (user_id, app_version, platform, os, route, error, stack, fatal, fingerprint,
                                  created_at, last_seen_at, occurrences)
select (select v::uuid from t_ctx where k = 'karim'), '1.0.' || g, case when g % 2 = 0 then 'android' else 'ios' end,
       'os', '/home', 'StateError: boom ' || (g % 2), 'stack line ' || g, g = 3, 'fp' || (g % 2),
       now() - make_interval(mins => g + 30), now() - make_interval(mins => g), g
  from generate_series(1, 5) g;

create function pg_temp.expect_err(p_sql text, p_state text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate <> p_state then
      raise exception 'FAIL: expected % but got % (%) for: %', p_state, sqlstate, sqlerrm, p_sql;
    end if;
    return;
  end;
  raise exception 'FAIL: expected % but the call succeeded: %', p_state, p_sql;
end $$;

-- Cross-user check (RLS would only show the caller's own notifications).
create function pg_temp.count_announcements()
returns bigint language sql security definer as $$
  select count(*) from public.notifications
   where type = 'announcement' and title = 'শিরোনাম' and data ->> 'route' = '/notes' and title_en = 'Title';
$$;

create function pg_temp.ok(p_cond boolean, p_msg text)
returns void language plpgsql as $$
begin
  if p_cond is distinct from true then raise exception 'FAIL: %', p_msg; end if;
end $$;

-- ===========================================================================
-- As an ADMIN (rahim)
-- ===========================================================================
select set_config('request.jwt.claims', json_build_object('sub', (select v from t_ctx where k = 'rahim'), 'role', 'authenticated')::text, true);
set local role authenticated;

do $$
declare
  j jsonb; j2 jsonb; n int; qid bigint; qid2 bigint; nid bigint; sid smallint; sch bigint; rid bigint;
  karim uuid := (select v::uuid from t_ctx where k = 'karim');
  rahim uuid := (select v::uuid from t_ctx where k = 'rahim');
  ts timestamptz;
begin
  -- Dashboard ---------------------------------------------------------------
  j := public.admin_console_stats();
  perform pg_temp.ok((j -> 'users' ->> 'total')::int >= 4, 'stats users.total');
  perform pg_temp.ok(jsonb_array_length(j -> 'series') = 14, 'stats series has 14 days');
  perform pg_temp.ok((j -> 'reports' ->> 'open')::int >= 1, 'stats open reports');
  perform pg_temp.ok((j -> 'client_errors_24h' ->> 'groups')::int = 2 and (j -> 'client_errors_24h' ->> 'events')::int = 15, 'stats client errors');
  perform pg_temp.ok(jsonb_typeof(j -> 'pipeline' -> 'cron') = 'array', 'stats cron array');
  perform pg_temp.ok((j -> 'ai_7d' ->> 'calls') is not null, 'stats ai_7d');
  raise notice 'stats: users=% ai_7d=% cron_jobs=%', j -> 'users', j -> 'ai_7d' ->> 'cost_usd', jsonb_array_length(j -> 'pipeline' -> 'cron');

  j := public.admin_ai_usage_summary(30);
  perform pg_temp.ok(jsonb_typeof(j -> 'by_function') = 'array', 'ai summary by_function');
  perform pg_temp.expect_err('select public.admin_ai_usage_summary(0)', 'PT400');

  -- Users ---------------------------------------------------------------------
  j := public.admin_list_users(null, null, null, 2, null, null);
  perform pg_temp.ok(jsonb_array_length(j) = 2, 'users page 1 size');
  j2 := public.admin_list_users(null, null, null, 2, (j -> 1 ->> 'created_at')::timestamptz, (j -> 1 ->> 'id')::uuid);
  perform pg_temp.ok(jsonb_array_length(j2) >= 1 and (j2 -> 0 ->> 'id') <> (j -> 0 ->> 'id') and (j2 -> 0 ->> 'id') <> (j -> 1 ->> 'id'), 'users keyset page 2');
  j := public.admin_list_users('qa_', null, null, 25, null, null);
  perform pg_temp.ok(jsonb_array_length(j) = 2, 'users search qa_ (escaped underscore)');
  j := public.admin_list_users('qa.karim@prostuti', null, null, 25, null, null);
  perform pg_temp.ok(jsonb_array_length(j) = 1 and (j -> 0 ->> 'email') = 'qa.karim@prostuti.app', 'users search by email');
  j := public.admin_list_users(karim::text, null, null, 25, null, null);
  perform pg_temp.ok(jsonb_array_length(j) = 1, 'users search by uuid');
  j := public.admin_list_users(null, 'admin', null, 25, null, null);
  perform pg_temp.ok(exists (select 1 from jsonb_array_elements(j) x where (x ->> 'id')::uuid = rahim), 'users role filter');
  perform pg_temp.expect_err('select public.admin_list_users(null, ''root'')', 'PT400');

  j := public.admin_get_user(karim);
  perform pg_temp.ok((j -> 'auth' ->> 'email') = 'qa.karim@prostuti.app', 'get_user email');
  perform pg_temp.ok(jsonb_typeof(j -> 'entitlements') = 'array', 'get_user entitlements');
  perform pg_temp.expect_err(format('select public.admin_get_user(%L)', gen_random_uuid()), 'PT404');

  perform public.admin_change_role(karim, 'moderator');
  perform pg_temp.ok((select role::text from public.profiles where id = karim) = 'moderator', 'role changed');
  perform pg_temp.expect_err(format('select public.admin_change_role(%L, ''user'')', rahim), 'PT409');
  perform pg_temp.expect_err(format('select public.admin_change_role(%L, ''owner'')', karim), 'PT400');
  perform public.admin_change_role(karim, 'user');

  j := public.admin_set_ban(karim, true, 'spam');
  perform pg_temp.ok((j ->> 'auth_enforced')::boolean, 'ban enforced in auth');
  perform pg_temp.ok((select is_banned from public.profiles where id = karim), 'profile banned');
  perform pg_temp.ok((public.admin_get_user(karim) -> 'auth' ->> 'banned_until')::timestamptz > now() + interval '50 years', 'auth banned_until');
  perform public.admin_set_ban(karim, false);
  perform pg_temp.ok((public.admin_get_user(karim) -> 'auth' ->> 'banned_until') is null, 'auth unbanned');
  perform pg_temp.expect_err(format('select public.admin_set_ban(%L, true)', rahim), 'PT409');

  j := public.admin_user_grant_addon(karim, 'prostuti_pro', 30);
  perform pg_temp.ok((j ->> 'expires_at')::timestamptz > now() + interval '29 days', 'grant addon expiry');
  perform pg_temp.expect_err(format('select public.admin_user_grant_addon(%L, ''prostuti_pro'', 0)', karim), 'PT400');
  perform pg_temp.expect_err(format('select public.admin_user_grant_addon(%L, ''nope'', 5)', karim), 'PT404');
  -- revoke the newest admin grant (it may be stacked → deleted, or running → ended)
  perform public.admin_revoke_entitlement((j ->> 'id')::bigint, 'test');
  perform pg_temp.ok(not exists (select 1 from public.user_entitlements where id = (j ->> 'id')::bigint and expires_at > now()), 'entitlement revoked');
  perform pg_temp.expect_err(format('select public.admin_revoke_entitlement(%s)', (j ->> 'id')::bigint), case when exists (select 1 from public.user_entitlements where id = (j ->> 'id')::bigint) then 'PT409' else 'PT404' end);

  perform public.admin_reset_onboarding(karim, 'interview');
  perform pg_temp.ok((select onboarding_step from public.profiles where id = karim) = 'interview', 'onboarding reset');
  perform pg_temp.expect_err(format('select public.admin_reset_onboarding(%L, ''nowhere'')', karim), 'PT400');

  -- Questions -----------------------------------------------------------------
  j := public.admin_search_questions(p_limit => 5);
  perform pg_temp.ok(jsonb_array_length(j) = 5, 'questions page size');
  qid := (j -> 4 ->> 'id')::bigint;
  j2 := public.admin_search_questions(p_limit => 5, p_after_id => qid);
  perform pg_temp.ok((j2 -> 0 ->> 'id')::bigint < qid, 'questions keyset');
  j := public.admin_search_questions(p_search => '#' || qid);
  perform pg_temp.ok(jsonb_array_length(j) = 1 and (j -> 0 ->> 'id')::bigint = qid, 'questions search by id');
  j := public.admin_search_questions(p_tag => 'bank', p_limit => 50);
  perform pg_temp.ok(not exists (select 1 from jsonb_array_elements(j) x where not (x -> 'exam_tags') ? 'bank'), 'questions tag filter');
  j := public.admin_search_questions(p_source_kind => 'curated', p_status => 'published', p_review => 'unverified', p_limit => 3);
  perform pg_temp.ok(not exists (select 1 from jsonb_array_elements(j) x where x ->> 'source_kind' <> 'curated'), 'questions source kind filter');
  j := public.admin_search_questions(p_search => 'বাংলা', p_limit => 3);
  perform pg_temp.ok(jsonb_typeof(j) = 'array', 'questions text search');
  perform pg_temp.expect_err('select public.admin_search_questions(p_tag => ''xyz'')', 'PT400');

  j := public.admin_get_question(qid);
  perform pg_temp.ok(j ? 'correct_index' and j ? 'answer_stats' and not j ? 'embedding', 'get_question shape');

  j := public.admin_save_question(null, jsonb_build_object(
         'subject_id', 1, 'stem', 'ADMIN-CONSOLE-TEST stem one?', 'options', jsonb_build_array('ক', 'খ', 'গ', 'ঘ'),
         'correct_index', 2, 'explanation', 'because', 'difficulty', 3, 'language', 'bn',
         'exam_tags', jsonb_build_array('bcs', 'bank', 'bcs'), 'source_kind', 'book', 'source_name', 'ADMIN TEST BOOK',
         'source_url', 'https://example.com/x', 'year', 2024, 'status', 'draft'));
  qid := (j ->> 'id')::bigint;
  j := public.admin_get_question(qid);
  perform pg_temp.ok(j -> 'exam_tags' = '["bank", "bcs"]'::jsonb and j ->> 'status' = 'draft' and (j ->> 'created_by')::uuid = rahim
                     and j -> 'topic_id' <> 'null'::jsonb and (j -> 'source' ->> 'kind') = 'book', 'question created with default topic + dedup tags');
  perform pg_temp.expect_err($q$select public.admin_save_question(null, '{"subject_id": 1, "stem": "ADMIN-CONSOLE-TEST   stem one?", "options": ["a","b"], "correct_index": 0}')$q$, 'PT409');
  perform pg_temp.expect_err($q$select public.admin_save_question(null, '{"subject_id": 1, "stem": "x valid stem", "options": ["a"], "correct_index": 0}')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_save_question(null, '{"subject_id": 1, "stem": "x valid stem", "options": ["a","a"], "correct_index": 0}')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_save_question(null, '{"subject_id": 1, "topic_id": 201, "stem": "x valid stem", "options": ["a","b"], "correct_index": 0}')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_save_question(null, '{"subject_id": 1, "stem": "x valid stem", "options": ["a","b"], "correct_index": 5}')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_save_question(null, '{"subject_id": 1, "stem": "x valid stem", "options": ["a","b"], "correct_index": 0, "exam_tags": ["army"]}')$q$, 'PT400');

  perform public.admin_save_question(qid, jsonb_build_object(
         'subject_id', 1, 'stem', 'ADMIN-CONSOLE-TEST stem one edited?', 'options', jsonb_build_array('ক', 'খ', 'গ'),
         'correct_index', 0, 'status', 'published', 'review_status', 'verified', 'source_id', null));
  j := public.admin_get_question(qid);
  perform pg_temp.ok((j ->> 'correct_index')::int = 0 and j ->> 'status' = 'published' and j -> 'source_id' = 'null'::jsonb
                     and jsonb_array_length(j -> 'options') = 3, 'question updated');
  perform pg_temp.ok(exists (select 1 from public.admin_audit_log where action = 'question.update' and target_id = qid::text
                              and details ? 'correct_index' and details ? 'stem'), 'question update audited with diff');
  perform pg_temp.expect_err(format('select public.admin_save_question(%s, %L)', 999999999,
                             '{"subject_id": 1, "stem": "x valid stem", "options": ["a","b"], "correct_index": 0}'), 'PT404');

  n := public.admin_set_question_status(array[qid], 'archived', null);
  perform pg_temp.ok(n = 1 and (select status from public.questions where id = qid) = 'archived', 'bulk status');
  n := public.admin_set_question_status(array[qid], 'archived', null);
  perform pg_temp.ok(n = 0, 'bulk status idempotent');
  perform pg_temp.expect_err('select public.admin_set_question_status(array[1]::bigint[], null, null)', 'PT400');

  j := public.admin_find_duplicate_questions(array['ADMIN-CONSOLE-TEST stem one   edited?', 'nothing like this exists 123']);
  perform pg_temp.ok(jsonb_array_length(j) = 1 and (j -> 0 ->> 'index')::int = 0 and (j -> 0 ->> 'id')::bigint = qid, 'duplicate finder');

  j := public.admin_import_questions(jsonb_build_array(
         jsonb_build_object('subject', 'bangla', 'topic', 'bn_samas', 'stem', 'ADMIN-CONSOLE-TEST import A?',
                            'options', jsonb_build_array('1', '2', '3', '4'), 'correct_index', 1, 'exam_tags', jsonb_build_array('govt'),
                            'source_kind', 'previous_exam', 'source_name', 'ADMIN TEST 99th BCS', 'source_year', 2020),
         jsonb_build_object('subject', 'bangla', 'stem', 'ADMIN-CONSOLE-TEST stem one edited?',
                            'options', jsonb_build_array('1', '2'), 'correct_index', 0),
         jsonb_build_object('subject', 'klingon', 'stem', 'ADMIN-CONSOLE-TEST import C?',
                            'options', jsonb_build_array('1', '2'), 'correct_index', 0),
         jsonb_build_object('subject', 'english', 'stem', 'ADMIN-CONSOLE-TEST import  A?',
                            'options', jsonb_build_array('1', '2'), 'correct_index', 0),
         jsonb_build_object('subject', 'english', 'topic', 'bn_samas', 'stem', 'ADMIN-CONSOLE-TEST import D?',
                            'options', jsonb_build_array('1', '2'), 'correct_index', 0)));
  raise notice 'import result: %', j;
  perform pg_temp.ok(jsonb_array_length(j -> 'inserted') = 1 and (j -> 'inserted' -> 0 ->> 'index')::int = 0, 'import inserted');
  perform pg_temp.ok(j -> 'duplicates' = '[1, 3]'::jsonb, 'import duplicates');
  perform pg_temp.ok(j -> 'invalid' = '[{"error": "subject_unknown", "index": 2}, {"error": "topic_subject_mismatch", "index": 4}]'::jsonb, 'import invalid');
  qid2 := (j -> 'inserted' -> 0 ->> 'id')::bigint;
  perform pg_temp.ok((select s.kind::text = 'previous_exam' and s.exam_type = 'govt' and q.year = 2020 and q.exam_tags = '{govt}'
                        from public.questions q join public.sources s on s.id = q.source_id where q.id = qid2), 'import provenance');
  perform pg_temp.expect_err('select public.admin_import_questions(''{}''::jsonb)', 'PT400');

  j := public.admin_export_questions(p_search => 'ADMIN-CONSOLE-TEST');
  perform pg_temp.ok(jsonb_array_length(j) = 2 and (j -> 0) ? 'subject' and (j -> 0) ? 'source_kind', 'export seed format');

  -- Moderation ------------------------------------------------------------------
  j := public.admin_list_reports('open', 30, null);
  rid := (select (x ->> 'id')::bigint from jsonb_array_elements(j) x where x ->> 'details' = 'test report');
  perform pg_temp.ok(rid is not null, 'existing admin_list_reports sees the report');
  j := public.admin_get_report_target('post', (select v from t_ctx where k = 'post'));
  perform pg_temp.ok(j -> 'content' is not null and jsonb_array_length(j -> 'reports') >= 1 and j -> 'author' is not null, 'report target');
  perform pg_temp.expect_err('select public.admin_get_report_target(''post'', ''not-a-uuid'')', 'PT400');
  perform pg_temp.expect_err('select public.admin_get_report_target(''question'', ''abc'')', 'PT400');
  perform pg_temp.expect_err(format('select public.admin_moderate_report(%s, ''nuke'')', rid), 'PT400');
  j := public.admin_moderate_report(rid, 'dismiss', 'not spam');
  perform pg_temp.ok((j ->> 'closed_reports')::int = 1 and (select status from public.reports where id = rid) = 'dismissed', 'report dismissed');

  -- Current affairs ---------------------------------------------------------------
  j := public.admin_list_note_days(null, 3);
  perform pg_temp.ok(jsonb_array_length(j) between 1 and 3, 'note days');
  j2 := public.admin_list_note_days((j -> 0 ->> 'date')::date, 3);
  perform pg_temp.ok(jsonb_array_length(j2) = 0 or (j2 -> 0 ->> 'date')::date < (j -> 0 ->> 'date')::date, 'note days keyset');
  j := public.admin_list_notes((select v::date from t_ctx where k = 'note_date'));
  perform pg_temp.ok(jsonb_array_length(j) >= 1, 'notes by date');
  nid := (j -> 0 ->> 'id')::bigint;
  perform public.admin_update_note(nid, '{"title_en": "Edited EN title", "importance": 5, "status": "archived", "key_facts_en": [{"fact": "x"}]}');
  perform pg_temp.ok((select title_en = 'Edited EN title' and importance = 5 and status = 'archived' from public.daily_notes where id = nid), 'note updated');
  perform pg_temp.expect_err(format('select public.admin_update_note(%s, ''{"embedding": 1}'')', nid), 'PT400');
  perform pg_temp.expect_err(format('select public.admin_update_note(%s, ''{"key_facts": [1]}'')', nid), 'PT400');
  perform pg_temp.expect_err(format('select public.admin_update_note(%s, ''{"title": ""}'')', nid), 'PT400');
  perform public.admin_delete_note(nid);
  perform pg_temp.ok(not exists (select 1 from public.daily_notes where id = nid), 'note deleted');
  perform pg_temp.expect_err(format('select public.admin_delete_note(%s)', nid), 'PT404');

  j := public.admin_get_daily_exam((select v::date from t_ctx where k = 'exam_date'));
  perform pg_temp.ok(jsonb_array_length(j -> 'questions') = cardinality((select question_ids from public.daily_exams where exam_date = (select v::date from t_ctx where k = 'exam_date'))), 'daily exam questions in order');
  perform pg_temp.ok(public.admin_get_daily_exam('1999-01-01') is null, 'no daily exam → null');

  j := public.admin_list_news_sources();
  perform pg_temp.ok(jsonb_array_length(j) >= 1 and (j -> 0) ? 'articles_7d', 'news sources');
  j := public.admin_save_news_source(null, '{"name": "Admin Test Feed", "rss_url": "https://example.com/rss.xml", "language": "en", "region": "INT", "priority": 3}');
  sid := (j ->> 'id')::smallint;
  j := public.admin_save_news_source(sid, '{"name": "Admin Test Feed", "rss_url": "https://example.com/rss2.xml", "language": "en", "region": "INT", "priority": 3, "enabled": false}');
  perform pg_temp.ok((j ->> 'enabled')::boolean = false, 'news source disabled');
  perform pg_temp.expect_err(format('select public.admin_save_news_source(null, %L)', (select format('{"name": "Dup", "rss_url": "%s"}', rss_url) from public.news_sources where id <> sid limit 1)), 'PT409');
  perform pg_temp.expect_err('select public.admin_save_news_source(null, ''{"name": "Bad", "rss_url": "ftp://x"}'')', 'PT400');

  perform pg_temp.expect_err('select public.admin_trigger_pipeline(''rm -rf'')', 'PT400');
  j := public.admin_pipeline_result(-1);
  perform pg_temp.ok(j ? 'pending' or j ? 'available', 'pipeline result');

  -- Schedules ---------------------------------------------------------------------
  j := public.admin_list_schedules();
  perform pg_temp.ok(jsonb_array_length(j) >= 1 and (j -> 0) ? 'active_plans', 'schedules list');
  j := public.admin_save_schedule(null, '{"exam_type": "bcs", "title_bn": "পরীক্ষা", "title_en": "Test exam", "expected_date": "2027-01-01"}');
  sch := (j ->> 'id')::bigint;
  j := public.admin_save_schedule(sch, '{"exam_type": "bcs", "title_bn": "পরীক্ষা", "title_en": "Test exam", "expected_date": "2027-02-01", "is_confirmed": true}');
  perform pg_temp.ok((j ->> 'date_changed')::boolean, 'schedule date change detected');
  perform pg_temp.expect_err('select public.admin_save_schedule(null, ''{"exam_type": "nope", "title_bn": "aa", "title_en": "bb", "expected_date": "2027-01-01"}'')', 'PT400');
  perform pg_temp.expect_err('select public.admin_save_schedule(null, ''{"exam_type": "bcs", "title_bn": "aa", "title_en": "bb", "expected_date": "soon"}'')', 'PT400');
  perform public.admin_delete_schedule(sch);
  perform pg_temp.expect_err(format('select public.admin_delete_schedule(%s)', (select value #>> '{}' from public.app_config where key = 'default_schedule_id')), 'PT409');

  -- Exam tracks ---------------------------------------------------------------------
  j := public.admin_list_exam_tracks();
  perform pg_temp.ok(jsonb_array_length(j) >= 1 and (j -> 0) ? 'available', 'tracks list');
  perform pg_temp.expect_err($q$select public.admin_save_exam_track('bcs', '{"name_bn": "বিসিএস", "name_en": "BCS", "sizes": [25, 50], "full_marks": 200, "negative_mark": 0.5, "seconds_per_question": 36, "distribution": {"bangla": 100, "english": 50}}')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_save_exam_track('bcs', '{"name_bn": "বিসিএস", "name_en": "BCS", "sizes": [25, 25], "full_marks": 150, "negative_mark": 0.5, "seconds_per_question": 36, "distribution": {"bangla": 100, "english": 50}}')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_save_exam_track('bcs', '{"name_bn": "বিসিএস", "name_en": "BCS", "sizes": [25], "full_marks": 150, "negative_mark": 0.5, "seconds_per_question": 36, "distribution": {"klingon": 150}}')$q$, 'PT400');
  j := public.admin_save_exam_track('bcs', '{"name_bn": "বিসিএস", "name_en": "BCS", "sizes": [200, 25, 50], "full_marks": 150, "negative_mark": 0.25, "seconds_per_question": 40, "distribution": {"bangla": 100, "english": 50}}');
  perform pg_temp.ok((j ->> 'full_marks')::int = 150 and j -> 'sizes' = '[25, 50, 200]'::jsonb, 'track saved (sizes sorted)');

  -- Monetization ---------------------------------------------------------------------
  j := public.admin_list_addons();
  perform pg_temp.ok(jsonb_array_length(j -> 'addons') >= 1 and jsonb_array_length(j -> 'features') >= 1, 'addons list');
  j := public.admin_save_addon('prostuti_pro', '{"name_bn": "প্রস্তুতি প্রো", "name_en": "Prostuti Pro", "features": ["daily_exam", "model_test"], "price_bdt": 199.5, "period_days": 30, "trial_days": 7, "is_active": true, "color": "#F42A41"}');
  perform pg_temp.ok((j ->> 'price_bdt')::numeric = 199.5, 'addon updated');
  perform pg_temp.expect_err($q$select public.admin_save_addon('prostuti_pro', '{"name_bn": "x", "name_en": "x", "features": ["teleport"], "price_bdt": 1, "period_days": 30, "trial_days": 0, "is_active": true}')$q$, 'PT400');
  j := public.admin_save_addon('admin_test_addon', '{"name_bn": "টেস্ট", "name_en": "Test", "features": ["ad_free"], "price_bdt": 10, "period_days": 7, "trial_days": 0, "is_active": false}', true);
  perform pg_temp.expect_err($q$select public.admin_save_addon('admin_test_addon', '{"name_bn": "টেস্ট", "name_en": "Test", "features": ["ad_free"], "price_bdt": 10, "period_days": 7, "trial_days": 0, "is_active": false}', true)$q$, 'PT409');
  j := public.admin_save_feature('model_test', '{"free_daily_quota": 2, "is_free": false}');
  perform pg_temp.ok((j ->> 'free_daily_quota')::int = 2, 'feature saved');
  perform pg_temp.expect_err($q$select public.admin_save_feature('model_test', '{"code": "x"}')$q$, 'PT400');

  j := public.admin_save_promo('AdminTest30', '{"addon_code": "prostuti_pro", "days": 30, "max_redemptions": 10, "is_active": true}', true);
  perform pg_temp.expect_err($q$select public.admin_save_promo('admintest30', '{"addon_code": "prostuti_pro", "days": 30, "is_active": true}', true)$q$, 'PT409');
  j := public.admin_save_promo('ADMINTEST30', '{"addon_code": "exam_pro", "days": 15, "max_redemptions": null, "is_active": false}');
  perform pg_temp.ok((j ->> 'addon_code') = 'exam_pro' and (j ->> 'days')::int = 15, 'promo updated case-insensitively');
  j := public.admin_list_promos('admintest', 10, null, null);
  perform pg_temp.ok(jsonb_array_length(j) = 1 and (j -> 0 ->> 'state') = 'inactive', 'promo list + state');
  update public.promo_codes set redeemed_count = 1 where code::text = 'AdminTest30';
  perform pg_temp.expect_err($q$select public.admin_delete_promo('admintest30')$q$, 'PT409');
  update public.promo_codes set redeemed_count = 0 where code::text = 'AdminTest30';
  perform public.admin_delete_promo('ADMINTEST30');
  perform pg_temp.ok(not exists (select 1 from public.promo_codes where code::text = 'AdminTest30'), 'promo deleted');
  perform pg_temp.expect_err($q$select public.admin_save_promo('x', '{"addon_code": "prostuti_pro", "days": 30, "is_active": true}', true)$q$, 'PT400');

  -- Config -------------------------------------------------------------------------
  j := public.admin_list_config();
  perform pg_temp.ok(exists (select 1 from jsonb_array_elements(j) x where x ->> 'key' = 'ai_pricing' and not (x ->> 'is_public')::boolean), 'config list incl. private');
  perform pg_temp.expect_err($q$select public.admin_set_config('morning_routine_time', '"25:00"')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_set_config('min_app_version', '"latest"')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_set_config('default_schedule_id', '999999')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_set_config('placement', '{"per_group": 99, "duration_minutes": 25}')$q$, 'PT400');
  ts := (select updated_at from public.app_config where key = 'morning_routine_time');
  j := public.admin_set_config('morning_routine_time', '"06:45"', null, null, ts);
  perform pg_temp.ok((j -> 'value') = '"06:45"'::jsonb, 'config saved');
  perform pg_temp.expect_err(format('select public.admin_set_config(''morning_routine_time'', ''"07:00"'', null, null, %L)', ts - interval '1 hour'), 'PT409');
  j := public.admin_set_config('admin_test_flag', '{"on": true}', 'test', false);
  perform pg_temp.ok((j ->> 'is_public')::boolean = false, 'config created');

  -- Broadcast ------------------------------------------------------------------------
  j := public.admin_broadcast_segments();
  perform pg_temp.ok((j ->> 'total')::int >= 1 and jsonb_typeof(j -> 'districts') = 'array', 'broadcast segments');
  j := public.admin_broadcast('শিরোনাম', 'বার্তা', 'Title', 'Body', '/notes', '{"target_exam": "bcs"}', true, true);
  perform pg_temp.ok((j ->> 'dry_run')::boolean and (j ->> 'recipients')::int >= 1, 'broadcast dry run');
  n := (j ->> 'recipients')::int;
  j := public.admin_broadcast('শিরোনাম', 'বার্তা', 'Title', 'Body', '/notes', '{"target_exam": "bcs"}', true, false, '00000000-0000-4000-8000-00000000abcd');
  perform pg_temp.ok((j ->> 'recipients')::int = n, 'broadcast sent to the dry-run count');
  perform pg_temp.ok(pg_temp.count_announcements() = n, 'notifications inserted');
  perform pg_temp.expect_err($q$select public.admin_broadcast('a', 'b', null, null, null, '{}', true, false, '00000000-0000-4000-8000-00000000abcd')$q$, 'PT409');
  perform pg_temp.expect_err($q$select public.admin_broadcast('a', 'b', null, null, 'https://evil.example')$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_broadcast('a', 'b', 'only title', null)$q$, 'PT400');
  perform pg_temp.expect_err($q$select public.admin_broadcast('a', 'b', null, null, null, '{"role": "admin"}')$q$, 'PT400');

  -- Monitoring -----------------------------------------------------------------------
  j := public.admin_list_client_errors(24, null, false, null, 1, null, null);
  perform pg_temp.ok(jsonb_array_length(j) = 1 and (j -> 0 ->> 'fingerprint') = 'fp1' and (j -> 0 ->> 'events')::int = 9
                     and (j -> 0 ->> 'reports')::int = 3, 'client error groups page 1 (occurrences summed)');
  j2 := public.admin_list_client_errors(24, null, false, null, 1, (j -> 0 ->> 'last_seen')::timestamptz, j -> 0 ->> 'fingerprint');
  perform pg_temp.ok(jsonb_array_length(j2) = 1 and (j2 -> 0 ->> 'fingerprint') = 'fp0', 'client error groups keyset');
  j := public.admin_list_client_errors(24, null, true, null, 50, null, null);
  perform pg_temp.ok(jsonb_array_length(j) = 1 and (j -> 0 ->> 'fatal')::boolean, 'client errors fatal filter');
  j := public.admin_client_error_events('fp1', 2, null, null);
  perform pg_temp.ok(jsonb_array_length(j) = 2 and (j -> 0) ? 'stack', 'client error events');
  j2 := public.admin_client_error_events('fp1', 2, (j -> 1 ->> 'created_at')::timestamptz, (j -> 1 ->> 'id')::bigint);
  perform pg_temp.ok(jsonb_array_length(j2) = 1, 'client error events keyset');
  perform pg_temp.ok((select count(*) from public.client_errors) = 5, 'admin reads client_errors via RLS');

  select count(*) into n from public.admin_audit_log;
  perform pg_temp.ok(n >= 25, 'audit rows written: ' || n);
  raise notice 'audit actions: %', (select string_agg(distinct action, ', ' order by action) from public.admin_audit_log);
end $$;

-- Rate limit on pipeline runs (3 per stage per 10 minutes). The calls are
-- queued through pg_net inside this transaction and discarded by the rollback.
do $$
begin
  perform public.admin_trigger_pipeline('dispatch-notifications');
  perform public.admin_trigger_pipeline('dispatch-notifications');
  perform public.admin_trigger_pipeline('dispatch-notifications');
  perform pg_temp.expect_err('select public.admin_trigger_pipeline(''dispatch-notifications'')', 'PT429');
end $$;

-- ===========================================================================
-- As a regular USER (karim)
-- ===========================================================================
reset role;
select set_config('request.jwt.claims', json_build_object('sub', (select v from t_ctx where k = 'karim'), 'role', 'authenticated')::text, true);
set local role authenticated;

do $$
declare n int;
begin
  perform pg_temp.expect_err('select public.admin_console_stats()', 'PT403');
  perform pg_temp.expect_err('select public.admin_list_users()', 'PT403');
  perform pg_temp.expect_err('select public.admin_search_questions()', 'PT403');
  perform pg_temp.expect_err('select public.admin_moderate_report(1, ''dismiss'')', 'PT403');
  perform pg_temp.expect_err('select public.admin_broadcast(''a'', ''b'')', 'PT403');
  perform pg_temp.expect_err('select public.admin_set_config(''x_key'', ''1'')', 'PT403');
  perform pg_temp.expect_err('select public.admin_list_client_errors()', 'PT403');
  perform pg_temp.expect_err('select public._admin_audit(''x.y'', null, null)', '42501');
  perform pg_temp.expect_err('select public._console_assert_admin()', '42501');
  perform pg_temp.expect_err('insert into public.admin_audit_log (action) values (''x.y'')', '42501');
  select count(*) into n from public.admin_audit_log;
  perform pg_temp.ok(n = 0, 'user cannot read the audit log');
  select count(*) into n from public.client_errors;
  perform pg_temp.ok(n = 0, 'user cannot read client errors');
end $$;

-- ===========================================================================
-- As a MODERATOR (karim promoted): moderation + question review only
-- ===========================================================================
reset role;
update public.profiles set role = 'moderator' where id = (select v::uuid from t_ctx where k = 'karim');
select set_config('request.jwt.claims', json_build_object('sub', (select v from t_ctx where k = 'karim'), 'role', 'authenticated')::text, true);
set local role authenticated;

do $$
declare j jsonb;
begin
  j := public.admin_search_questions(p_limit => 2);
  perform pg_temp.ok(jsonb_array_length(j) = 2, 'moderator can review questions');
  j := public.admin_get_report_target('post', (select v from t_ctx where k = 'post'));
  perform pg_temp.ok(j ? 'content', 'moderator can preview reports');
  perform pg_temp.expect_err('select public.admin_console_stats()', 'PT403');
  perform pg_temp.expect_err('select public.admin_list_users()', 'PT403');
  perform pg_temp.expect_err('select public.admin_import_questions(''[]'')', 'PT403');
  perform pg_temp.expect_err('select public.admin_list_config()', 'PT403');
  perform pg_temp.expect_err(format('select public.admin_change_role(%L, ''admin'')', (select v from t_ctx where k = 'karim')), 'PT403');
end $$;

-- ===========================================================================
-- As ANON: no execute privilege at all
-- ===========================================================================
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.expect_err('select public.admin_console_stats()', '42501');
  perform pg_temp.expect_err('select public.admin_broadcast(''a'', ''b'')', '42501');
end $$;

reset role;
select 'ALL ADMIN CONSOLE CHECKS PASSED' as result;
rollback;
