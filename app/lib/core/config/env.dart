/// Compile-time configuration, injected with `--dart-define` (see
/// `docs/RELEASE.md`). Nothing secret lives here: the Supabase anon key is
/// public by design and every table is protected by Row Level Security.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zoicsfuukvoibwzqjffy.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// AdMob rewarded unit ids. Empty → Google's official test units.
  static const admobRewardedAndroid = String.fromEnvironment('ADMOB_REWARDED_ANDROID');
  static const admobRewardedIos = String.fromEnvironment('ADMOB_REWARDED_IOS');

  /// Firebase (optional). Push notifications are enabled only when these are
  /// provided at build time; everything else works without Firebase.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static const flavor = String.fromEnvironment('APP_FLAVOR', defaultValue: 'prod');

  static bool get isConfigured => supabaseAnonKey.isNotEmpty;

  static bool get firebaseEnabled =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
}
