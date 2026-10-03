# Contributing to Prostuti

Welcome! This guide gets a new developer productive in about 15 minutes.

## 1. Set up

| Tool | Version |
|------|---------|
| Flutter | 3.47.6 (stable) |
| Java | 17+ (Android builds) |
| Deno | 2.x (Edge Functions) |
| psql | any recent (database scripts) |

```bash
git clone git@github.com:samim-reza/prostuti.git && cd prostuti
cd app
flutter pub get
dart run tool/l10n_merge.dart && flutter gen-l10n
flutter run --dart-define=SUPABASE_ANON_KEY=<ask a maintainer>
```

## 2. Find your way around

Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) first. In short:

* `app/lib/core/` holds shared building blocks. Reuse them; don't re-invent them.
* `app/lib/features/<name>/` contains `data/` (models + repository), `application/`
  (Riverpod controllers), `presentation/` (screens + widgets) and `l10n/` (strings).
* `supabase/` holds the backend: migrations (schema + RLS + RPCs) and Edge Functions.

## 3. Rules we follow

1. **No hard-coded UI text.** Add keys to your feature's `l10n/<feature>_en.arb`
   and `_bn.arb`, prefixed with the feature name, then run
   `dart run tool/l10n_merge.dart && flutter gen-l10n`. Both languages must be
   complete and natural.
2. **Screens never call Supabase directly.** Go through a repository and a provider.
3. **Business rules belong in Postgres** (RPCs, triggers, RLS). The client is never trusted.
4. **Lists use keyset pagination** (`PagedNotifier` + `PagedListView`). Never use OFFSET.
5. **Reads go through `CachedFetcher`**, so they're fast and work offline.
   **Writes that make sense offline go through `OfflineQueue`**, with
   client-generated ids.
6. **Errors** become `AppFailure`; show them with `failureMessage()` / `showErrorSnack()`.
7. Dispose every controller, timer, stream and Realtime channel.

## 4. Before you push

```bash
cd app
dart format lib test tool
flutter analyze            # must report "No issues found!"
flutter test
cd ../supabase/functions
deno fmt && deno lint && deno check */index.ts && deno test _shared generate-study-plan
```

Database changes go in a **new** migration file
(`supabase/migrations/<yyyymmddHHMMSS>_<name>.sql`). Never edit a migration
that has already been applied. Run `tools/db.sh file tools/rls_smoke_test.sql`
after changing policies.

## 5. Commits & PRs

* Conventional commits: `feat(feed): …`, `fix(exam): …`, `docs: …`, `chore: …`.
* Keep PRs focused on one feature or fix. Include screenshots for UI changes.
* CI must be green. A merge to `main` publishes a signed test APK automatically.
