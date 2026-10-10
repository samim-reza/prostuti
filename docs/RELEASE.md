# Build, release and operations

## Build-time configuration (`--dart-define`)

| Key | Required | Purpose |
|-----|----------|---------|
| `SUPABASE_URL` | yes (has default) | project URL |
| `SUPABASE_ANON_KEY` | **yes** | public anon key (RLS protects data) |
| `ADMOB_REWARDED_ANDROID`, `ADMOB_REWARDED_IOS` | no | real ad units (test units otherwise) |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID` | no | enables FCM push |

Android AdMob **app id**: `-PadmobAppId=…` or the `ADMOB_APP_ID` env var (Google's test id by default).

## Local builds

```bash
cd app
flutter pub get && dart run tool/l10n_merge.dart && flutter gen-l10n
flutter run --dart-define=SUPABASE_ANON_KEY=<anon key>
flutter build apk --release --dart-define=SUPABASE_ANON_KEY=<anon key>
```

Play Store bundles are built in CI (see [Play Store App Bundle](#play-store-app-bundle)),
never on a laptop, so they always carry the release signature, obfuscation and an
increasing versionCode.

Release signing reads `android/key.properties` (git-ignored) or these env vars:
`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`. **Back up the release keystore.** Losing it means you
can never update the app on the Play Store.

## GitHub Actions

| Workflow | Trigger | Result |
|----------|---------|--------|
| `ci.yml` | PRs and pushes | localization check, format, analyze, tests, Deno lint/check/tests |
| `android-release.yml` | push to `main`, manual | one signed universal APK as an artifact and a **GitHub pre-release**; manual runs with **bundle** ticked also produce the Play `.aab` |
| `supabase-deploy.yml` | `supabase/**` changes, manual | `supabase db push` + `functions deploy` |

Release builds use `versionCode = 10000 + run number`, so every new APK installs
over an older one (including the early split-per-ABI test builds), and Play Store
uploads always increase. All builds are signed with the same release key.

Required repository secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`,
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`.

## Play Store App Bundle

1. GitHub → **Actions** → *Android release (APK)* → **Run workflow** on `main`,
   tick **bundle** and run. The normal APK + pre-release are produced as usual.
2. After the APK release, the job runs `flutter build appbundle --release` with the
   same build number (`versionCode = 10000 + run number`), dart-defines and
   `--obfuscate --split-debug-info`. It fails on purpose if the release keystore
   secret is missing, because Play rejects debug-signed bundles.
3. Download the artifacts:
   * `prostuti-aab-<run>`: the `.aab` to upload in Play Console
     (*Testing → Internal testing* first, then promote). It is **not** attached
     to the GitHub release.
   * `prostuti-aab-debug-symbols-<run>`: Dart symbols for that bundle, plus the
     R8 `mapping.txt` (upload it in Play Console under *App bundle explorer →
     Downloads → ReTrace mapping file*). Keep this artifact for every bundle you
     ship to Play: crash stacks from Play installs can only be read with it.
4. Play App Signing: on first upload let Google manage the app-signing key. Our
   release keystore then acts as the **upload key**, and every later bundle must be
   signed with it.

## Crash & error reports

Release builds report uncaught errors themselves (no third-party SDK):
`lib/core/services/error_reporter.dart` → RPC `log_client_error` → table
`public.client_errors` (migration `0019`).

* Captured: Flutter framework errors, uncaught async/zone errors and start-up
  failures. Network/offline errors are skipped. Each distinct error (fingerprint
  = error type + top 5 stack frames) is sent once per session, at most 20 per
  session, with a 10 s timeout. Reporting never throws or delays start-up.
* Stored: app version/build, platform, OS string, UI language, route pattern
  (`/exam/:id`), error (≤ 1000 chars, emails/tokens/phone numbers masked), stack
  (≤ 8000), fatal flag, user id (null when signed out, set to null when the
  account is deleted). The same fingerprint from the same user within an hour
  increments `occurrences` instead of adding a row. Rate limits: 30 per user per
  hour, 60 per minute for all signed-out devices together.
* Retention: 30 days (`prostuti-client-errors-purge` cron job, daily).
* Reading: clients cannot select the table (RLS, no policy). Use the SQL editor or
  `tools/db.sh psql`:

  ```sql
  select fingerprint, max(error) as error, sum(occurrences) as hits,
         count(distinct user_id) as users, max(last_seen_at) as last_seen,
         max(app_version || '+' || build_number) as latest_build, bool_or(fatal) as fatal
    from public.client_errors
   where created_at > now() - interval '7 days'
   group by fingerprint order by hits desc limit 50;
  ```
* Symbolizing: release stacks are obfuscated. Save a row's `stack` to
  `stack.txt`, download the debug-symbols artifact of that build
  (`prostuti-debug-symbols-<run>` for the GitHub APK,
  `prostuti-aab-debug-symbols-<run>` for Play), pick the file for the `arch:`
  shown in the stack header and run
  `flutter symbolize -i stack.txt -d app.android-arm64.symbols`.
  `build_number - 10000` is the run number.

## Privacy policy, terms & Play "Data safety"

* In the app: *Settings → Legal*, *About → Legal*, and linked from the sign-up
  consent line. The texts live in `lib/features/settings/l10n/settings_{en,bn}.arb`.
* Public copies for the Play listing (same content, English + Bangla):
  [`docs/PRIVACY.md`](PRIVACY.md) and [`docs/TERMS.md`](TERMS.md). Privacy-policy
  URL for Play Console: `https://github.com/samim-reza/prostuti/blob/main/docs/PRIVACY.md`.
  Account-deletion URL: the same page, section *Deleting your account*.
* When the texts change, update the ARB fragments, both Markdown files and
  `legalLastUpdated` in `legal_screen.dart` together.
* Account deletion is a verified email request (Settings → Account → Request
  account deletion). The policy promises completion **within 30 days**: delete the
  user in Supabase *Authentication → Users*; every table cascades from
  `auth.users` / `profiles`.

### Data safety answers

All data is encrypted in transit (HTTPS/TLS). Users can request deletion. Data is
not sold. Supabase and OpenAI act as service providers (processing on our behalf),
which Play does not count as "sharing". Google AdMob collects data itself, so its
rows are marked as shared.

| Data type (Play category) | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Name (Personal info) | yes | no | no | App functionality, Account management |
| Email address (Personal info) | yes | no | no | Account management, App functionality |
| User IDs (Personal info) | yes | no | no | Account management, App functionality |
| Other info: date of birth, district, education, occupation (Personal info) | yes | no | yes | App functionality, Personalization |
| Photos (Photos and videos) | yes | no | yes | App functionality |
| In-app messages (Messages) | yes | no | yes | App functionality |
| Other user-generated content: posts, comments, onboarding answers | yes | no | yes | App functionality, Personalization |
| App interactions: exams, practice, study plan, ad interactions (App activity) | yes | yes (AdMob) | no | App functionality, Personalization, Analytics, Advertising, Fraud prevention |
| Crash logs, Diagnostics (App info and performance) | yes | yes (AdMob diagnostics) | no | App functionality, Analytics |
| Device or other IDs: advertising ID (AdMob), push token if enabled | yes | yes (AdMob) | no | Advertising, Analytics, Fraud prevention, App functionality |
| Approximate location: IP-derived, by AdMob only | yes | yes (AdMob) | no | Advertising, Analytics, Fraud prevention |
| Financial info, health, contacts, files, calendar, audio, web history, precise location | no | no | — | — |

Other answers: not designed for children (not in the Families program); no
independent security review; data encrypted in transit; deletion request available.

## Supabase setup checklist (new project)

1. `tools/db.sh migrate` (or `supabase db push`).
2. Vault secrets `project_url` and `cron_secret` (see `docs/DATABASE.md`).
3. Function secrets:
   `supabase secrets set OPENAI_API_KEY=… OPENAI_MODEL=gpt-5.4-mini OPENAI_EMBED_MODEL=text-embedding-3-small CRON_SECRET=…`
   (optionally `FCM_SERVICE_ACCOUNT='<json>'`).
4. `supabase functions deploy --use-api`.
5. `python3 tools/import_questions.py --apply`.
6. Auth: add `io.prostuti.app://**` to redirect URLs. For production, configure
   **custom SMTP** (Resend, Brevo, SES…). The default Supabase mailer only sends
   to team members, so password-reset e-mails need SMTP. "Confirm email" is
   currently off so testers can sign up instantly. Turn it on together with SMTP.

## Enabling push notifications (optional)

1. Create a Firebase project and an Android app `io.prostuti.app` (plus iOS `io.prostuti.app`).
2. Build with the four `FIREBASE_*` dart-defines (no `google-services.json` needed).
3. Set the Edge Function secret `FCM_SERVICE_ACCOUNT` (service-account JSON).
   `dispatch-notifications` starts delivering the push outbox automatically.

## Free-plan notes

* Free Supabase projects **pause after 7 days without activity**. The cron jobs
  keep the database busy, but upgrade before launch.
* Nano compute has 60 connections. The app uses PostgREST (pooled), so this is fine for testing.
* Edge Functions have a 150 s limit. The notes pipeline takes about 40–50 s.

## iOS

The iOS project is kept in `app/ios` for a future release (bundle id `io.prostuti.app`,
screen-capture protection already wired). It is not built in CI yet.
