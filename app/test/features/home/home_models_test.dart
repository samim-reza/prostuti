import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/home/application/home_notifications.dart';
import 'package:prostuti/features/home/data/home_models.dart';
import 'package:prostuti/features/profile/data/profile.dart';

void main() {
  group('trialFromEntitlements', () {
    final now = DateTime.utc(2026, 10, 4, 12);

    test('an active trial is advertised', () {
      final t = trialFromEntitlements([
        {'addon_code': 'prostuti_pro', 'source': 'trial', 'expires_at': '2026-10-10T20:47:38.749317+00:00'},
      ], now);
      expect(t, isNotNull);
      expect(t!.addonCode, 'prostuti_pro');
      expect(t.daysLeft(now), 7);
    });

    test('a purchase hides the trial banner', () {
      final t = trialFromEntitlements([
        {'addon_code': 'prostuti_pro', 'source': 'trial', 'expires_at': '2026-10-10T00:00:00Z'},
        {'addon_code': 'notes', 'source': 'purchase', 'expires_at': '2027-01-01T00:00:00Z'},
      ], now);
      expect(t, isNull);
    });

    test('expired rows are ignored; the latest trial wins', () {
      final t = trialFromEntitlements([
        {'addon_code': 'old', 'source': 'purchase', 'expires_at': '2026-01-01T00:00:00Z'},
        {'addon_code': 'a', 'source': 'trial', 'expires_at': '2026-10-05T00:00:00Z'},
        {'addon_code': 'b', 'source': 'trial', 'expires_at': '2026-10-08T00:00:00Z'},
      ], now);
      expect(t!.addonCode, 'b');
    });

    test('no rows → no banner', () => expect(trialFromEntitlements(const [], now), isNull));

    test('daysLeft rounds up and never goes negative', () {
      final t = TrialInfo(addonCode: 'x', expiresAt: now.add(const Duration(hours: 5)));
      expect(t.daysLeft(now), 1);
      expect(t.daysLeft(now.add(const Duration(days: 1))), 0);
      expect(t.isActive(now.add(const Duration(days: 1))), isFalse);
    });

    test('TrialStatus round-trips (cache)', () {
      final s = TrialStatus(TrialInfo(addonCode: 'x', expiresAt: now));
      expect(TrialStatus.fromJson(s.toJson()).trial!.expiresAt, now);
      expect(TrialStatus.fromJson(TrialStatus.none.toJson()).trial, isNull);
    });
  });

  group('NotesDigest', () {
    test('keeps only the count, the top 3 headlines and the daily exam', () {
      final d = NotesDigest.fromRpc({
        'note_date': '2026-10-04',
        'notes': [
          for (var i = 0; i < 5; i++) {'id': i, 'title': 'শিরোনাম $i', 'title_en': i == 0 ? 'Headline 0' : null},
        ],
        'daily_exam': const {'id': 3, 'title_bn': 'দৈনিক পরীক্ষা', 'question_count': 20, 'duration_minutes': 10},
      });
      expect(d.count, 5);
      expect(d.top, hasLength(3));
      expect(d.top.first.title(bangla: false), 'Headline 0');
      expect(d.top[1].title(bangla: false), 'শিরোনাম 1', reason: 'falls back to Bangla');
      expect(d.dailyExam!.questionCount, 20);
      final cached = NotesDigest.fromJson(d.toJson());
      expect(cached.count, 5);
      expect(cached.top.map((t) => t.titleBn), d.top.map((t) => t.titleBn));
      expect(cached.dailyExam!.durationMinutes, 10);
    });

    test('empty day (notes not out yet)', () {
      final d = NotesDigest.fromRpc(const {
        'notes': <Object>[],
        'note_date': '2026-10-04',
        'daily_exam': null,
        'downloaded': false,
      });
      expect(d.isEmpty, isTrue);
      expect(d.dailyExam, isNull);
    });
  });

  group('planHomeNotifications', () {
    const profile = Profile(id: 'u', username: 'rahim', reminderTime: '20:30');

    test('reminder at the profile time; morning nudge only with a plan', () {
      final p = planHomeNotifications(profile: profile, morningRoutineTime: '06:30', hasPlan: true, locale: 'bn');
      expect(p.reminderAt, const TimeOfDay(hour: 20, minute: 30));
      expect(p.morningAt, const TimeOfDay(hour: 6, minute: 30));
      expect(p.morningKnown, isTrue);

      final noPlan = planHomeNotifications(profile: profile, morningRoutineTime: '06:30', hasPlan: false, locale: 'bn');
      expect(noPlan.morningAt, isNull);
    });

    test('unknown plan state leaves the morning notification alone', () {
      final p = planHomeNotifications(profile: profile, morningRoutineTime: '06:30', hasPlan: null, locale: 'bn');
      expect(p.morningKnown, isFalse);
    });

    test('respects the user’s switches', () {
      const off = Profile(id: 'u', username: 'r', reminderEnabled: false, notificationSettings: {'routine': false});
      final p = planHomeNotifications(profile: off, morningRoutineTime: '06:30', hasPlan: true, locale: 'en');
      expect(p.reminderAt, isNull);
      expect(p.morningAt, isNull);
    });

    test('bad config time falls back to 06:30; equal inputs → equal plans', () {
      final a = planHomeNotifications(profile: profile, morningRoutineTime: 'soon', hasPlan: true, locale: 'bn');
      final b = planHomeNotifications(profile: profile, morningRoutineTime: 'soon', hasPlan: true, locale: 'bn');
      expect(a.morningAt, const TimeOfDay(hour: 6, minute: 30));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a == planHomeNotifications(profile: profile, morningRoutineTime: 'soon', hasPlan: true, locale: 'en'),
        isFalse,
      );
    });
  });
}
