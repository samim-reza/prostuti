# Architecture

Prostuti is a **Flutter** app (Android + iOS from one codebase) backed by
**Supabase**: Postgres with Row Level Security, Auth, Storage, Realtime,
Edge Functions and pg_cron.

```
┌────────────────────────── Flutter app (app/) ──────────────────────────┐
│ presentation  (screens, widgets)      ← ConsumerWidgets, go_router       │
│ application   (Riverpod notifiers)    ← state, pagination, optimistic UI │
│ data          (models, repositories)  ← Supabase client + cache          │
│ core          (theme, router, cache, pagination, services, widgets)      │
└───────────────┬──────────────────────────────────────────────────────────┘
                │ HTTPS (PostgREST RPC / tables) · Realtime websockets · Storage
┌───────────────▼──────────────────── Supabase (supabase/) ────────────────┐
│ Postgres: tables + RLS + security-definer RPCs (business rules live here) │
│ Edge Functions (Deno): AI pipeline, study planner, push dispatch           │
│ pg_cron → pg_net → Edge Functions (daily notes 05:20, exam 05:50 BD …)    │
└────────────────────────────────────────────────────────────────────────────┘
```

## Repository layout

| Path | What lives there |
|------|------------------|
| `app/lib/core/` | Cross-cutting building blocks: theme, router, l10n, cache, pagination, errors, services, shared widgets. |
| `app/lib/features/<name>/` | One folder per feature (auth, feed, chat, daily_notes, exam, …). |
| `app/lib/l10n/` | Generated localizations (do not edit `arb/` or `gen/` by hand). |
| `app/test/` | Unit and widget tests, mirroring `lib/`. |
| `supabase/migrations/` | Ordered SQL migrations: schema, RLS, RPCs, cron, seed reference data. |
| `supabase/functions/` | Edge Functions (Deno/TypeScript) with `_shared/` utilities. |
| `supabase/seed/questions/` | Question-bank seed files (JSON, with sources). |
| `tools/` | Maintainer scripts (`db.sh`, question importer, brand assets). |
| `docs/` | This documentation. |

## Feature module anatomy

```
lib/features/feed/
├── data/
│   ├── post.dart                 immutable models (fromJson / toJson)
│   └── feed_repository.dart      Supabase calls + caching; exposes a Provider
├── application/
│   └── feed_controller.dart      Riverpod Notifier/AsyncNotifier (state + actions)
├── presentation/
│   ├── screens/                  one widget per route
│   └── widgets/                  feature-private widgets
└── l10n/
    ├── feed_en.arb               English strings (template, with @metadata)
    └── feed_bn.arb               Bangla strings
```

Rules of thumb:

1. **Screens never talk to Supabase.** They watch providers, and providers call repositories.
2. **Repositories return models or throw `AppFailure`.** Use `guard()` for table
   queries, and `client.rpcMap / rpcList / rpcCall` for RPCs. Both map
   backend errors such as `rate_limited` (HTTP 429) and `feature_locked` (402)
   to typed failures.
3. **Business rules live in Postgres.** Scoring, entitlement checks, rate limits,
   visibility and counters run in RPCs and triggers. The client is never trusted.
4. **No hard-coded UI text.** Add keys to the feature's ARB files. Prefix keys
   with the feature name (`feedComposeHint`). Then run
   `dart run tool/l10n_merge.dart && flutter gen-l10n`.
5. Use `context.n(…)` and `Fmt.*` for numbers and dates (Bangla digits in Bangla UI).
6. Navigate with `Routes` constants (`context.push(Routes.postDetail(id))`).
   Feature-internal sub-pages may use `Navigator.push`.

## State management (Riverpod 3, no code generation)

* `Provider` provides repositories and services.
* `FutureProvider` / `AsyncNotifier` handle one-shot data and screens with actions.
* `PagedNotifier<T, Cursor>` (core) backs every infinite list. Pass a page
  fetcher and an `idOf` function. It gives you refresh, load-more, retry,
  de-duplication and optimistic `upsertFirst` / `replace` / `removeWhere`.
* Riverpod's automatic retry is limited to transient network errors (see `bootstrap.dart`).

## Performance toolkit (see `docs/CACHING.md`)

| Problem | Tool |
|---------|------|
| Repeated reads | `CachedFetcher`: memory LRU → Hive disk TTL cache, stale-while-revalidate |
| Stampedes (many widgets ask at once) | single-flight request coalescing in `CachedFetcher` |
| Lookups for data that doesn't exist | negative caching (`isEmpty` → short TTL) |
| Deep lists | keyset (cursor) pagination, never OFFSET; `PagedListView` prefetches |
| Duplicate realtime and page items | hash-set merge in `PagedNotifier`, `BloomFilter` for streams |
| Spammy taps | `Debouncer`, `Throttler`, `TokenBucket` (client) + Postgres rate limits (server) |
| Image memory and data usage | WebP compression before upload; `AppNetworkImage` decodes at display size |
| Heavy JSON | `decodeJsonInBackground` (isolate) |
| Counts in lists | trigger-maintained counters (`reaction_count`, `comment_count`, …) |

## Bilingual by design

The language (বাংলা / English) is a user setting (`appSettingsProvider`), mirrored
to `profiles.locale`.

* UI strings live in ARB files for both languages.
* Numbers and dates switch between Bangla and Latin digits.
* Server-generated content carries both languages: daily notes (`*_en`),
  notifications (`title_en`/`body_en`) and plan days (`title_en`). The app shows
  whichever matches the current locale.
* AI endpoints receive `locale` and answer in it.
* Exam questions stay in their original language, as in the real exams.

## Offline-first

See `docs/CACHING.md`. Every read is served from the two-level cache when
offline. Writes go through the persistent `OfflineQueue` and replay on
reconnect. Subjects can be downloaded as offline practice packs. A global
banner shows offline and sync status.

## Security model

* Every table has RLS. Clients only hold the public anon key.
* Column-level privileges hide sensitive columns. For example, `questions.correct_index`
  cannot be selected by clients, and answers are revealed by RPCs only after the user answers.
* Daily notes are visible only on their own Bangladesh day (RLS), yet kept forever.
* Study plans are visible only up to today + 2 days (RLS). The full plan is
  exposed as an aggregate overview.
* Screenshots and screen recording are blocked with `FLAG_SECURE` on Android.
  iOS uses a secure layer plus a capture shield.
* Secrets (OpenAI key, service role key) exist only as Edge Function secrets.

## Request lifecycle example (daily exam)

1. The user taps **Start**. `ExamRepository.start(ExamKind.daily)` calls
   `rpc('start_exam')`. Postgres checks the entitlement (`require_feature`),
   the rate limit and the one-attempt rule. It returns the questions **without** answers.
2. Each answer is cached on device (`exam_answers:<id>`), so a killed app can resume.
3. **Submit** calls `submit_exam`. The server scores the exam (−0.5 per wrong
   answer), records attempts, updates topic mastery and the streak, snapshots
   readiness and returns the rank.
4. **Review** calls `get_exam_review`, which returns answers and explanations,
   allowed only after submission.
