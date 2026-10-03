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
# Play Store upload (App Bundle):
flutter build appbundle --release --dart-define=SUPABASE_ANON_KEY=<anon key>
```

Release signing reads `android/key.properties` (git-ignored) or these env vars:
`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`. **Back up the release keystore.** Losing it means you
can never update the app on the Play Store.

## GitHub Actions

| Workflow | Trigger | Result |
|----------|---------|--------|
| `ci.yml` | PRs and pushes | localization check, format, analyze, tests, Deno lint/check/tests |
| `android-release.yml` | push to `main`, manual | one signed universal APK as an artifact and a **GitHub pre-release** |
| `supabase-deploy.yml` | `supabase/**` changes, manual | `supabase db push` + `functions deploy` |

Release builds use `versionCode = 10000 + run number`, so every new APK installs
over an older one (including the early split-per-ABI test builds), and Play Store
uploads always increase. All builds are signed with the same release key.

Required repository secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`,
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`.

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
