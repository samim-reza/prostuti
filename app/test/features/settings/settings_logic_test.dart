import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/settings/application/password_strength.dart';
import 'package:prostuti/features/settings/application/reminder_time.dart';
import 'package:prostuti/features/settings/application/support.dart';
import 'package:prostuti/features/settings/data/settings_repository.dart';

void main() {
  group('reminder time ↔ database', () {
    test('TimeOfDay → HH:mm:00', () {
      expect(timeOfDayToDb(const TimeOfDay(hour: 20, minute: 0)), '20:00:00');
      expect(timeOfDayToDb(const TimeOfDay(hour: 6, minute: 5)), '06:05:00');
      expect(timeOfDayToDb(const TimeOfDay(hour: 0, minute: 0)), '00:00:00');
    });

    test('database → TimeOfDay accepts HH:mm:ss and HH:mm', () {
      expect(timeOfDayFromDb('20:00:00'), const TimeOfDay(hour: 20, minute: 0));
      expect(timeOfDayFromDb('07:30'), const TimeOfDay(hour: 7, minute: 30));
      expect(timeOfDayFromDb('7:05:00'), const TimeOfDay(hour: 7, minute: 5));
    });

    test('malformed values fall back', () {
      const fallback = TimeOfDay(hour: 6, minute: 30);
      expect(timeOfDayFromDb(null), defaultReminderTime);
      expect(timeOfDayFromDb(''), defaultReminderTime);
      expect(timeOfDayFromDb('25:00:00', fallback: fallback), fallback);
      expect(timeOfDayFromDb('12:75', fallback: fallback), fallback);
      expect(timeOfDayFromDb('evening', fallback: fallback), fallback);
    });

    test('round trip for every minute of the day', () {
      for (var h = 0; h < 24; h++) {
        for (var m = 0; m < 60; m += 7) {
          final t = TimeOfDay(hour: h, minute: m);
          expect(timeOfDayFromDb(timeOfDayToDb(t)), t);
        }
      }
    });
  });

  group('time formatting', () {
    test('Bangla uses day-part words and Bangla digits', () {
      expect(formatTimeOfDay(const TimeOfDay(hour: 20, minute: 0), bangla: true), 'রাত ৮:০০');
      expect(formatTimeOfDay(const TimeOfDay(hour: 6, minute: 30), bangla: true), 'সকাল ৬:৩০');
      expect(formatTimeOfDay(const TimeOfDay(hour: 12, minute: 0), bangla: true), 'দুপুর ১২:০০');
      expect(formatTimeOfDay(const TimeOfDay(hour: 16, minute: 45), bangla: true), 'বিকাল ৪:৪৫');
      expect(formatTimeOfDay(const TimeOfDay(hour: 18, minute: 10), bangla: true), 'সন্ধ্যা ৬:১০');
      expect(formatTimeOfDay(const TimeOfDay(hour: 4, minute: 50), bangla: true), 'ভোর ৪:৫০');
      expect(formatTimeOfDay(const TimeOfDay(hour: 0, minute: 15), bangla: true), 'রাত ১২:১৫');
    });

    test('English uses AM/PM', () {
      expect(formatTimeOfDay(const TimeOfDay(hour: 20, minute: 0), bangla: false), '8:00 PM');
      expect(formatTimeOfDay(const TimeOfDay(hour: 0, minute: 5), bangla: false), '12:05 AM');
      expect(formatTimeOfDay(const TimeOfDay(hour: 12, minute: 30), bangla: false), '12:30 PM');
    });
  });

  test('password strength', () {
    expect(passwordStrength(''), 0);
    expect(passwordStrength('abc'), 0);
    expect(passwordStrength('abcdefgh'), 1);
    expect(passwordStrength('abcdefg1'), 2);
    expect(passwordStrength('Abcdefgh12!x'), 4);
    expect(passwordStrength('abcdefghijkl'), 2);
  });

  test('mailto uses %20 (not +) so mail apps show spaces', () {
    final uri = mailtoUri('support@prostuti.app', subject: 'অ্যাকাউন্ট মুছুন', body: 'a b\nc');
    expect(uri.scheme, 'mailto');
    expect(uri.path, 'support@prostuti.app');
    expect(uri.toString(), isNot(contains('+')));
    expect(uri.toString(), contains('a%20b%0Ac'));
    expect(mailtoUri('x@y.z').toString(), 'mailto:x@y.z');
  });

  test('blocked users join keeps block order and skips missing profiles', () {
    final users = joinBlockedProfiles(
      [
        {'blocked_id': 'u2', 'created_at': '2026-10-03T10:00:00Z'},
        {'blocked_id': 'gone', 'created_at': '2026-10-02T10:00:00Z'},
        {'blocked_id': 'u1', 'created_at': '2026-10-01T10:00:00Z'},
      ],
      [
        {'id': 'u1', 'username': 'one', 'full_name': null, 'avatar_url': null},
        {'id': 'u2', 'username': 'two', 'full_name': 'দুই', 'avatar_url': 'https://x/a.webp'},
      ],
    );
    expect(users.map((u) => u.id), ['u2', 'u1']);
    expect(users.first.displayName, 'দুই');
    expect(users.last.displayName, 'one');
    expect(users.first.blockedAt, DateTime.utc(2026, 10, 3, 10));
    final cached = BlockedUser.fromJson(users.first.toJson());
    expect(cached.id, 'u2');
    expect(cached.blockedAt, users.first.blockedAt);
  });
}
