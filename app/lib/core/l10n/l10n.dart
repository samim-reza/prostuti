import 'package:flutter/widgets.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/l10n/gen/app_localizations.dart';

export 'package:prostuti/l10n/gen/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// True when the UI is in Bangla (drives Bangla digits & date names).
  bool get isBn => Localizations.localeOf(this).languageCode == 'bn';

  /// Locale-aware number rendering (Bangla digits in Bangla UI).
  String n(Object value) => Fmt.digits(value, bangla: isBn);
}

/// Maps an [AppFailure] (or any error) to a user-facing localized message.
String failureMessage(BuildContext context, Object error) {
  final l = context.l10n;
  final f = AppFailure.from(error);
  // Feature-specific messages (e.g. `already_attempted`, `promo_invalid`) win
  // over the generic text for their failure class.
  final specific = _businessMessage(context, f.code);
  if (specific != null) return specific;
  return switch (f) {
    NetworkFailure() => l.errorNetwork,
    RateLimitFailure(:final retryAfterSeconds) =>
      retryAfterSeconds == null ? l.errorRateLimitedShort : l.errorRateLimited(context.n(retryAfterSeconds)),
    FeatureLockedFailure() => l.errorFeatureLocked,
    PermissionFailure() => l.errorPermission,
    NotFoundFailure() => l.errorNotFound,
    AuthFailure(:final code) when code == 'not_authenticated' => l.errorSession,
    AuthFailure(:final detail) => detail ?? l.errorGeneric,
    ServerFailure(:final code) => _businessMessage(context, code) ?? l.errorServer,
    _ => l.errorGeneric,
  };
}

/// Business error codes raised by Postgres functions → localized text.
/// Feature modules may add their own via [registerFailureMessages].
String? _businessMessage(BuildContext context, String code) {
  for (final resolver in _resolvers) {
    final message = resolver(context, code);
    if (message != null) return message;
  }
  return null;
}

typedef FailureMessageResolver = String? Function(BuildContext context, String code);

final List<FailureMessageResolver> _resolvers = [];

/// Lets a feature translate its own backend error codes (e.g. `promo_invalid`).
void registerFailureMessages(FailureMessageResolver resolver) {
  if (!_resolvers.contains(resolver)) _resolvers.add(resolver);
}
