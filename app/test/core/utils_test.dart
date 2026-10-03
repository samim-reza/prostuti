import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/core/utils/validators.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  group('Fmt', () {
    test('converts digits to Bangla only in Bangla UI', () {
      expect(Fmt.digits(2026, bangla: true), '২০২৬');
      expect(Fmt.digits(2026, bangla: false), '2026');
    });

    test('compact counts', () {
      expect(Fmt.count(1250, bangla: false), '1.3K');
      expect(Fmt.count(15000, bangla: true), '১৫হা');
    });

    test('exam clock', () {
      expect(Fmt.clock(const Duration(minutes: 9, seconds: 5), bangla: false), '09:05');
      expect(Fmt.clock(const Duration(hours: 2), bangla: true), '২:০০:০০');
    });
  });

  group('BdTime', () {
    test('today is in UTC+6 and the day ends at 18:00 UTC', () {
      final end = BdTime.endOfToday();
      expect(end.toUtc().hour, 18);
      expect(BdTime.untilEndOfToday().inHours, lessThanOrEqualTo(24));
      expect(BdTime.todayIso(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });

  group('AppFailure.from', () {
    test('maps PostgREST HTTP-coded errors', () {
      expect(
        AppFailure.from(const PostgrestException(message: 'rate_limited', code: 'PT429', hint: 'retry_after:12')),
        isA<RateLimitFailure>().having((f) => f.retryAfterSeconds, 'retry', 12),
      );
      expect(
        AppFailure.from(const PostgrestException(message: 'feature_locked', code: 'PT402', details: 'model_test')),
        isA<FeatureLockedFailure>().having((f) => f.feature, 'feature', 'model_test'),
      );
      expect(
        AppFailure.from(const PostgrestException(message: 'promo_invalid', code: 'P0001')),
        isA<ServerFailure>().having((f) => f.code, 'code', 'promo_invalid'),
      );
    });
  });

  group('misc helpers', () {
    test('version comparison', () {
      expect(isVersionBelow('1.0.0', '1.0.1'), isTrue);
      expect(isVersionBelow('1.2.0+5', '1.1.9'), isFalse);
      expect(isVersionBelow('2.0.0', '2.0.0'), isFalse);
    });

    test('validators', () {
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('nope'), 'invalid_email');
      expect(Validators.password('short'), 'password_too_short');
      expect(Validators.username('rahim_bcs'), isNull);
      expect(Validators.username('x'), 'invalid_username');
    });

    test('JsonRead is tolerant', () {
      final j = <String, dynamic>{
        'n': '5',
        'd': 2,
        'list': [
          <String, dynamic>{'a': 1},
        ],
        'o': <String, dynamic>{'k': 'v'},
      };
      expect(j.integer('n'), 5);
      expect(j.dbl('d'), 2.0);
      expect(j.list('list', (m) => m.integer('a')), [1]);
      expect(j.obj('o').str('k'), 'v');
      expect(j.str('missing', 'x'), 'x');
    });
  });
}
