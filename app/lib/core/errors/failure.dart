import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Every error that reaches the UI is converted into an [AppFailure], so
/// screens never deal with raw Postgrest/Auth/Storage exceptions.
///
/// The backend raises machine-readable codes (`rate_limited`,
/// `feature_locked`, `promo_invalid` …); [code] carries them to the UI,
/// which maps them to localized messages via `failureMessage()`.
sealed class AppFailure implements Exception {
  const AppFailure(this.code, {this.detail});

  /// Stable machine-readable code.
  final String code;

  /// Extra context (e.g. the locked feature code, retry-after seconds).
  final String? detail;

  @override
  String toString() => 'AppFailure($code${detail == null ? '' : ': $detail'})';

  /// Converts anything thrown by the data layer into an [AppFailure].
  static AppFailure from(Object error) {
    if (error is AppFailure) return error;
    if (error is PostgrestException) return _fromPostgrest(error);
    if (error is AuthException) {
      return AuthFailure(error.code ?? _authCodeFromMessage(error.message), detail: error.message);
    }
    if (error is StorageException) return ServerFailure('storage_error', detail: error.message);
    if (error is FunctionException) return _fromFunction(error);
    if (error is SocketException || error is TimeoutException || error is HttpException) {
      return const NetworkFailure();
    }
    if (error is RealtimeSubscribeException) return const NetworkFailure();
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('ClientException')) {
      return const NetworkFailure();
    }
    return UnknownFailure(text);
  }

  static AppFailure _fromPostgrest(PostgrestException e) {
    final message = e.message.trim();
    switch (e.code) {
      case 'PT429':
        final retry = RegExp(r'retry_after:(\d+)').firstMatch(e.hint ?? '')?.group(1);
        return RateLimitFailure(action: e.details?.toString(), retryAfterSeconds: int.tryParse(retry ?? ''));
      case 'PT402':
        return FeatureLockedFailure(e.details?.toString() ?? message);
      case 'PT401':
        return const AuthFailure('not_authenticated');
      case 'PT403':
      case '42501':
        return PermissionFailure(message.isEmpty ? 'forbidden' : message);
      case 'PT404':
      case 'PGRST116':
        return NotFoundFailure(message.isEmpty ? 'not_found' : message);
      case 'PT409':
      case '23505':
        return ConflictFailure(message.isEmpty ? 'conflict' : message);
      case '23514':
        return const ValidationFailure('invalid_input');
    }
    // Business errors raised with a bare code as the message (P0001).
    if (RegExp(r'^[a-z_]+$').hasMatch(message)) return ServerFailure(message);
    return ServerFailure('server_error', detail: message);
  }

  static AppFailure _fromFunction(FunctionException e) {
    final details = e.details;
    final code = details is Map ? details['error']?.toString() : null;
    switch (e.status) {
      case 429:
        final retry = details is Map ? int.tryParse('${details['retry_after'] ?? ''}') : null;
        return RateLimitFailure(action: code, retryAfterSeconds: retry);
      case 402:
        return FeatureLockedFailure(details is Map ? '${details['feature'] ?? code ?? ''}' : '');
      case 401:
        return const AuthFailure('not_authenticated');
      case 403:
        return PermissionFailure(code ?? 'forbidden');
      case 404:
        return NotFoundFailure(code ?? 'not_found');
    }
    return ServerFailure(code ?? 'server_error', detail: e.reasonPhrase);
  }

  static String _authCodeFromMessage(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid login')) return 'invalid_credentials';
    if (m.contains('already registered') || m.contains('already exists')) return 'user_already_exists';
    if (m.contains('password')) return 'weak_password';
    if (m.contains('rate limit')) return 'over_request_rate_limit';
    return 'auth_error';
  }
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure() : super('network');
}

final class AuthFailure extends AppFailure {
  const AuthFailure(super.code, {super.detail});
}

final class RateLimitFailure extends AppFailure {
  const RateLimitFailure({this.action, this.retryAfterSeconds}) : super('rate_limited', detail: action);
  final String? action;
  final int? retryAfterSeconds;
}

final class FeatureLockedFailure extends AppFailure {
  const FeatureLockedFailure(this.feature) : super('feature_locked', detail: feature);
  final String feature;
}

final class PermissionFailure extends AppFailure {
  const PermissionFailure(super.code);
}

final class NotFoundFailure extends AppFailure {
  const NotFoundFailure(super.code);
}

final class ConflictFailure extends AppFailure {
  const ConflictFailure(super.code);
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.code);
}

final class ServerFailure extends AppFailure {
  const ServerFailure(super.code, {super.detail});
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure(String message) : super('unknown', detail: message);
}
