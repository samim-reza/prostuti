# Admin console

`admin/` is a web console for Prostuti staff. It is a static single-page app (Vite + React 19 +
TypeScript + Tailwind CSS v4) that talks to Supabase directly. It holds no secrets: only the
public anon key and the signed-in staff member's JWT.

**Every rule is enforced in Postgres.** The console only hides what a role can't use. Each admin
RPC is `security definer` with `set search_path = ''`, checks `is_admin()` or `is_staff()` and raises
`PT403` otherwise, validates its input (`PT400`), and writes every change to `admin_audit_log`.
Lists use keyset pagination, never `OFFSET`.

## Roles

| Role | Can use |
|------|---------|
| `moderator` | Questions (review, edit, create, export) and Moderation (report queue) |
| `admin` | Everything, including users, current affairs, schedules, exam tracks, add-ons, promo codes, app config, broadcast and monitoring |
| `user` | Nothing. Users are signed out with a "not a staff account" notice. |

To make someone an admin from psql:

```sql
update public.profiles set role = 'admin'
 where id = (select id from auth.users where email = 'you@example.com');
```

After that, admins promote other staff from **Users → Actions → Role**. Admins can't change their own
role, and an admin must be demoted before they can be banned.

## Screens

| Screen | What it does |
|--------|--------------|
| Dashboard | Users (total, new, active), exams submitted today, the question bank by status and review, open reports, today's notes and daily exam, AI cost over 7 days, client errors over 24 h, cron job health and recent pipeline runs |
| Users | Search by username, name, e-mail or id. The detail drawer shows the profile, targets, onboarding step, entitlements, exams, payments and admin history. Actions: set role, ban or unban (blocks sign-in and revokes sessions), grant an add-on for N days, revoke an entitlement, set the onboarding step |
| Questions | Filter by subject, topic, track, status, review, source kind or text/`#id`. Detail view with the answer, the learners' answer distribution, source and fact. Create and edit questions, bulk verify, flag, publish, archive or reject. **Import** a JSON file in the seed format (validated, with a preview, duplicates skipped). **Export** the filtered set in the same format |
| Moderation | The report queue (open, actioned, dismissed) with a full preview of the content and every report on it. Hide, restore, dismiss or resolve, with an optional audit note |
| Current affairs | Notes by day (Bangla and English; edit, unpublish, delete), the daily exam with its answers, news sources (add, edit, enable or disable; editing resets the failure back-off) and manual pipeline runs with the live result |
| Exam schedules | CRUD. Changing `expected_date` re-plans every active study plan for that exam and notifies those learners. The console warns you and shows the number of affected plans. Schedules that are in use can only be deactivated |
| Exam tracks | Model-test patterns: sizes, full marks, negative mark, seconds per question, and marks per subject with a live sum check against full marks. Also shows the published question count per subject in each track |
| Add-ons / Promo codes | Price, period, trial, features and on-sale state; feature free quotas; promo code CRUD with redemption counts. Codes that have been redeemed can only be deactivated |
| App config | Every `app_config` row, including private ones. Values are edited as JSON, validated on the client and the server, and you see a diff before saving. Saves use optimistic concurrency, so a stale edit fails with `PT409` |
| Broadcast | An in-app notification (Bangla, with optional English) plus a push, sent to everyone or to a segment (target exam, district, language, active within N days). It shows a live recipient count, is limited to 5 sends per hour, and is idempotent per message |
| Monitoring | Client errors grouped by fingerprint (with stacks), AI usage and estimated cost by day, function and model, and the audit log |

## Running locally

```bash
cd admin
cp .env.example .env.local      # fill in VITE_SUPABASE_ANON_KEY (public anon key)
npm install
npm run dev                     # http://localhost:5174
```

| Script | Purpose |
|--------|---------|
| `npm run dev` | Vite dev server |
| `npm run build` | `tsc --noEmit` followed by the production build into `dist/` |
| `npm run typecheck` | TypeScript in strict mode |
| `npm run lint` | ESLint (typescript-eslint + react-hooks) |
| `npm run format` / `format:check` | Prettier |

### Environment variables

| Variable | Value |
|----------|-------|
| `VITE_SUPABASE_URL` | `https://zoicsfuukvoibwzqjffy.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | the project's **anon / publishable** key |

Both values are public by design and are inlined at build time. The console refuses to start with a
service-role key or an `sb_secret_…` key. Never put those in the environment.

## Deploying to Vercel

| Setting | Value |
|---------|-------|
| Framework preset | Vite |
| Root directory | `admin` |
| Install command | `npm ci` |
| Build command | `npm run build` |
| Output directory | `dist` |
| Node.js | 20.19+ or 22.x |
| Environment variables | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (Production and Preview) |

`admin/vercel.json` adds SPA rewrites to `/index.html` and security headers: `X-Frame-Options: DENY`,
`nosniff`, a strict `Referrer-Policy`, HSTS, `Permissions-Policy` and a CSP. The CSP allows scripts only
from the site itself, Supabase (`https://*.supabase.co`, `wss://*.supabase.co`), Google Fonts (Hind
Siliguri), and `https:` images for avatars and post media.

The console is not linked from the app. Keep it on its own domain and protect Preview deployments
with Vercel's Deployment Protection if you like.

## Database: migration `20261004000020_admin_console.sql`

New objects:

* `admin_audit_log` (actor, action such as `user.ban`, target type and id, `details` jsonb, time). It is
  append-only: admins can read it, and nobody can write to it except the RPCs.
* An admin-only select policy (and the matching grant) on `client_errors` from 0019.
* `app_config.ai_pricing` (private): USD per 1M tokens per model, used for cost estimates.
* Supporting indexes: `profiles (created_at, id)`, `question_attempts (question_id, selected_index)`,
  `reports (target_type, target_id, status)`, `exam_sessions (submitted_at)`, `study_plans (schedule_id)`,
  `daily_notes (note_date)`, `news_articles (source_id, fetched_at)`, `user_entitlements (addon_code, expires_at)`.

RPCs (S = staff, A = admin). Existing RPCs are reused through thin audited wrappers, so their
contracts are unchanged.

| RPC | Role | Notes |
|-----|------|-------|
| `admin_console_stats()` | A | Dashboard payload |
| `admin_ai_usage_summary(p_days)` | A | By day and by function/model, with estimated cost |
| `admin_list_users(p_search, p_role, p_banned, p_limit, p_after_created, p_after_id)` | A | Keyset on `(created_at, id)`; includes e-mail |
| `admin_get_user(p_user)` | A | Profile, auth, entitlements, exams, plan, payments, history |
| `admin_change_role(p_user, p_role)` | A | Wraps `admin_set_role`; not for yourself |
| `admin_set_ban(p_user, p_banned, p_reason)` | A | Profile flag + `auth.users.banned_until` + session revoke |
| `admin_user_grant_addon(p_user, p_addon, p_days)` | A | Wraps `admin_grant_addon` |
| `admin_revoke_entitlement(p_entitlement, p_reason)` | A | Ends it now (a stacked one is removed) |
| `admin_reset_onboarding(p_user, p_step)` | A | |
| `admin_search_questions(filters…, p_limit, p_after_id)` | S | Keyset on `id`; `#123` searches by id |
| `admin_get_question(p_id)` | S | With answer stats, fact, source, reports |
| `admin_save_question(p_id, p_question)` | S | Create (`p_id` null) or update; duplicate → `PT409` |
| `admin_set_question_status(p_ids, p_status, p_review_status)` | S | Bulk, up to 500 |
| `admin_find_duplicate_questions(p_stems)` | S | Same normalisation as `stem_hash` |
| `admin_import_questions(p_items, p_status, p_review_status)` | A | Seed format, up to 1000 items per call |
| `admin_export_questions(filters…, p_limit, p_after_id)` | S | Seed format, keyset |
| `admin_moderate_report(p_report, p_action, p_note)` | S | Wraps `admin_resolve_report` (`hide`, `restore`, `dismiss`, `resolve`) |
| `admin_get_report_target(p_target_type, p_target_id)` | S | Full content + all reports on it |
| `admin_list_note_days(p_before, p_limit)` / `admin_list_notes(p_date)` | A | |
| `admin_update_note(p_id, p_patch)` / `admin_delete_note(p_id)` | A | Bangla and English text, facts, Q&A, status |
| `admin_get_daily_exam(p_date)` | A | Questions with answers, submissions |
| `admin_list_news_sources()` / `admin_save_news_source(p_id, p_source)` | A | |
| `admin_trigger_pipeline(p_stage)` / `admin_pipeline_result(p_request_id)` | A | Wraps `admin_run_pipeline`; 3 runs per stage per 10 min |
| `admin_list_schedules()` / `admin_save_schedule(p_id, p_schedule)` / `admin_delete_schedule(p_id)` | A | |
| `admin_list_exam_tracks()` / `admin_save_exam_track(p_code, p_track)` | A | Distribution must sum to full marks |
| `admin_list_addons()` / `admin_save_addon(p_code, p_addon, p_create)` / `admin_save_feature(p_code, p_patch)` | A | |
| `admin_list_promos(p_search, p_limit, p_after_created, p_after_code)` / `admin_save_promo(…)` / `admin_delete_promo(p_code)` | A | |
| `admin_list_config()` / `admin_set_config(p_key, p_value, p_description, p_is_public, p_expected_updated_at)` | A | Known keys are validated |
| `admin_broadcast_segments()` / `admin_broadcast(p_title, p_body, p_title_en, p_body_en, p_route, p_segment, p_send_push, p_dry_run, p_client_key)` | A | One set-based insert; 5 sends per hour |
| `admin_list_client_errors(p_hours, p_platform, p_fatal_only, p_search, p_limit, cursor…)` / `admin_client_error_events(p_fingerprint, …)` | A | Grouped by fingerprint |

The console also reads `admin_audit_log`, `ai_usage_log`, `subjects`, `topics`, `sources` and
`exam_types` directly, through their RLS policies. It calls the existing `admin_list_reports` as it is.

Broadcasts are notifications with `type = 'announcement'` and `data.route`. Push taps already open
`data.route`. For taps in the in-app inbox to open it too, add an `announcement` case to
`notificationRoute()` in the app.

## Testing

```bash
tools/db.sh file admin/tests/admin_console_test.sql
```

The test runs the migration and about 150 checks as an admin, a moderator, a user and anon inside one
transaction, then rolls back. It covers validation, keyset pages, audit rows, role gates, rate limits
and duplicate handling. It prints `ALL ADMIN CONSOLE CHECKS PASSED`.
