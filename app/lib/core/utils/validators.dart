/// Form validators returning l10n keys (resolved in the UI layer).
abstract final class Validators {
  static final _email = RegExp(r'^[\w.+\-]+@[\w\-]+(\.[\w\-]+)+$');
  static final _username = RegExp(r'^[a-zA-Z0-9_.]{3,24}$');

  static String? email(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'required';
    if (!_email.hasMatch(value)) return 'invalid_email';
    return null;
  }

  static String? password(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'required';
    if (value.length < 8) return 'password_too_short';
    return null;
  }

  static String? username(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'required';
    if (!_username.hasMatch(value)) return 'invalid_username';
    return null;
  }

  static String? required(String? v) => (v == null || v.trim().isEmpty) ? 'required' : null;
}
