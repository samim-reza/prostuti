# Database

Postgres 17 on Supabase. Everything is defined in ordered migrations under
`supabase/migrations/`.

| Migration | Contents |
|-----------|----------|
| 0001 foundation | extensions, Bangladesh-time helpers, `app_config`, profiles (+ column privileges), roles, rate limiting, features / add-ons / entitlements / promo codes / payments, notifications, push outbox, streaks |
| 0002 catalog_questions | subjects, topics, exam types and schedules, sources, questions (answers hidden), attempts, bookmarks, practice RPCs |
| 0003 social | friendships, requests, blocks, posts, reactions, comments, comment likes, feed RPCs, reports (auto-hide at 5) |
| 0004 chat | conversations, members, messages, DM / group RPCs, unread counts |
| 0005 current_affairs | news sources and articles, **facts** (permanent, supersession), daily notes (today-only RLS), downloads, daily exams |
| 0006 exams_mastery | exam sessions, start/submit/review, topic mastery (EMA), readiness, leaderboard |
| 0007 study_plan | onboarding interview, plans, plan days (visible up to today + 2), routine RPCs, re-plan triggers |
| 0008 ai_platform | semantic cache, AI usage log, Edge-Function invoker (pg_net + Vault), housekeeping, admin RPCs |
| 0009 storage_realtime_cron | buckets and storage policies, Realtime publication, signup trigger, pg_cron schedules |
| 0010 reference_data | BCS syllabus (10 subjects / 88 topics), exam types and schedules, features, add-ons, news sources, remote config |
| 0011 pipeline_support | Bloom filter state, idempotency keys, set-based notification fan-out |
| 0012 bilingual | English columns for notes, notifications and plan days; locale-aware notifications |
| 0013 offline_sync | offline practice packs, idempotent attempt sync, client ids |
| 0014 chat_deleted_preview | soft-deleted messages no longer show in inbox previews |
| 0015 model_test_apportionment | exact model-test sizes (largest-remainder subject apportionment) |

## Conventions

* **RLS on every table.** Clients only use the anon key plus the user's JWT.
* **Business rules live in `security definer` RPCs** with `set search_path = ''`.
  Errors use machine codes: `raise exception 'promo_invalid'`, or HTTP-mapped
  SQLSTATEs (`PT401`, `PT402` feature locked, `PT403`, `PT404`, `PT409`,
  `PT429` rate limited).
* **Column privileges** protect sensitive columns: `questions.correct_index`,
  `profiles.role`, counters. Clients must select explicit columns.
* Every list has a composite index matching its keyset cursor.
* Time is Bangladesh time: `bd_today()` and `bd_now()`.

## Operating

```bash
tools/db.sh migrate                    # apply pending migrations (records versions like the Supabase CLI)
tools/db.sh psql                       # interactive session
tools/db.sh file tools/rls_smoke_test.sql   # security regression test (rolled back)
python3 tools/import_questions.py --apply   # (re)import question seed files, idempotent
```

Make someone an admin, from psql as the owner:

```sql
update public.profiles set role = 'admin'
 where id = (select id from auth.users where email = 'you@example.com');
```

Create a promo code:

```sql
insert into public.promo_codes (code, addon_code, days, max_redemptions)
values ('LAUNCH30', 'prostuti_pro', 30, 500);
```

Vault secrets used by pg_cron → Edge Functions (set once per project):

```sql
select vault.create_secret('https://<ref>.supabase.co', 'project_url');
select vault.create_secret('<random secret>', 'cron_secret');   -- same value as the CRON_SECRET function secret
```
