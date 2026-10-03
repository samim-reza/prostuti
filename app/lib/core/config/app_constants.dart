/// App-wide constants that are not environment specific.
abstract final class AppConstants {
  static const appName = 'প্রস্তুতি';
  static const appNameEn = 'Prostuti';
  static const supportEmail = 'support@prostuti.app';

  /// Deep-link scheme registered on Android/iOS (password reset, etc.).
  static const authRedirectUrl = 'io.prostuti.app://login-callback';

  // Pagination
  static const pageSize = 20;
  static const chatPageSize = 30;

  // Media
  static const maxPostImages = 4;
  static const imageMaxDimension = 1280;
  static const imageQuality = 78;
  static const avatarMaxDimension = 512;

  // Exams (BCS rule: −0.5 per wrong answer)
  static const defaultNegativeMark = 0.5;

  // Storage buckets
  static const avatarsBucket = 'avatars';
  static const postMediaBucket = 'post-media';
  static const chatMediaBucket = 'chat-media';
}
