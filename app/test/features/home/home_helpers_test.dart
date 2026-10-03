import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/home/application/home_helpers.dart';

ExamSchedule _s(int id, String type, DateTime date) => ExamSchedule(
  id: id,
  examType: type,
  titleBn: 'পরীক্ষা $id',
  titleEn: 'Exam $id',
  expectedDate: date,
  isConfirmed: false,
);

void main() {
  group('dayPartFor (greeting)', () {
    test('covers every hour of the day', () {
      final parts = {for (var h = 0; h < 24; h++) h: dayPartFor(h)};
      expect(parts[4], DayPart.dawn);
      expect(parts[5], DayPart.dawn);
      expect(parts[6], DayPart.morning);
      expect(parts[11], DayPart.morning);
      expect(parts[12], DayPart.noon);
      expect(parts[14], DayPart.noon);
      expect(parts[15], DayPart.afternoon);
      expect(parts[17], DayPart.afternoon);
      expect(parts[18], DayPart.evening);
      expect(parts[20], DayPart.evening);
      expect(parts[21], DayPart.night);
      expect(parts[0], DayPart.night);
      expect(parts[3], DayPart.night);
    });

    test('wraps out-of-range hours', () => expect(dayPartFor(30), DayPart.morning));
  });

  group('effectiveStreak', () {
    final today = DateTime.utc(2026, 10, 4);

    test('active today or yesterday keeps the streak', () {
      expect(effectiveStreak(count: 5, lastActive: DateTime(2026, 10, 4), bdToday: today), 5);
      expect(effectiveStreak(count: 5, lastActive: DateTime(2026, 10, 3), bdToday: today), 5);
    });

    test('a gap of two days or more resets it', () {
      expect(effectiveStreak(count: 5, lastActive: DateTime(2026, 10, 2), bdToday: today), 0);
      expect(effectiveStreak(count: 5, lastActive: null, bdToday: today), 0);
    });

    test('activeToday', () {
      expect(activeToday(lastActive: DateTime(2026, 10, 4, 23), bdToday: today), isTrue);
      expect(activeToday(lastActive: DateTime(2026, 10, 3), bdToday: today), isFalse);
    });
  });

  group('daysUntil', () {
    final today = DateTime.utc(2026, 10, 4);
    test('counts whole calendar days', () {
      expect(daysUntil(DateTime(2026, 10, 5), today), 1);
      expect(daysUntil(DateTime(2027, 5, 14), today), 222);
      expect(daysUntil(DateTime(2026, 10, 4, 23, 59), today), 0);
    });
    test('never negative', () => expect(daysUntil(DateTime(2026, 9), today), 0));
  });

  group('resolveTargetSchedule', () {
    final schedules = [
      _s(1, 'bcs', DateTime(2026, 11, 28)),
      _s(2, 'bcs', DateTime(2027, 5, 14)),
      _s(3, 'bank', DateTime(2027, 2, 19)),
      _s(4, 'primary', DateTime(2027, 3, 12)),
    ];

    test('the profile target wins', () {
      expect(resolveTargetSchedule(schedules, targetId: 3, defaultId: 2)!.id, 3);
    });

    test('then the server default (when it matches the user’s exams)', () {
      expect(resolveTargetSchedule(schedules, defaultId: 2)!.id, 2);
      expect(resolveTargetSchedule(schedules, defaultId: 2, targetExams: ['bank'])!.id, 3);
    });

    test('then the earliest exam of a targeted type', () {
      expect(resolveTargetSchedule(schedules, targetExams: ['primary'])!.id, 4);
      expect(resolveTargetSchedule(schedules)!.id, 1);
    });

    test('unknown ids fall through; empty list → null', () {
      expect(resolveTargetSchedule(schedules, targetId: 99, defaultId: 98)!.id, 1);
      expect(resolveTargetSchedule(const []), isNull);
    });
  });
}
