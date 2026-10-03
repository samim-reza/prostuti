import 'package:prostuti/features/catalog/data/catalog.dart';

/// Part of the day for the greeting (Bangladesh wall-clock hour).
enum DayPart { dawn, morning, noon, afternoon, evening, night }

/// 4–5 ভোর, 6–11 সকাল, 12–14 দুপুর, 15–17 বিকেল, 18–20 সন্ধ্যা, 21–3 রাত.
DayPart dayPartFor(int hour) {
  final h = hour % 24;
  if (h >= 4 && h < 6) return DayPart.dawn;
  if (h >= 6 && h < 12) return DayPart.morning;
  if (h >= 12 && h < 15) return DayPart.noon;
  if (h >= 15 && h < 18) return DayPart.afternoon;
  if (h >= 18 && h < 21) return DayPart.evening;
  return DayPart.night;
}

/// The streak shown to the user. `profiles.streak_count` is only updated on
/// activity, so a streak whose last active day is before yesterday is over.
int effectiveStreak({required int count, required DateTime? lastActive, required DateTime bdToday}) {
  if (lastActive == null || count <= 0) return 0;
  final last = DateTime.utc(lastActive.year, lastActive.month, lastActive.day);
  final gap = bdToday.difference(last).inDays;
  return gap <= 1 ? count : 0;
}

/// True when the user was active today (the flame is lit).
bool activeToday({required DateTime? lastActive, required DateTime bdToday}) {
  if (lastActive == null) return false;
  return DateTime.utc(lastActive.year, lastActive.month, lastActive.day) == bdToday;
}

/// Whole days from the Bangladesh [bdToday] to [date] (never negative).
int daysUntil(DateTime date, DateTime bdToday) {
  final target = DateTime.utc(date.year, date.month, date.day);
  final d = target.difference(bdToday).inDays;
  return d < 0 ? 0 : d;
}

/// The exam the user is preparing for: their own target, else the server's
/// default schedule (when it matches their target exams), else the earliest
/// exam of a type they target, else the default, BCS, or the earliest exam.
ExamSchedule? resolveTargetSchedule(
  List<ExamSchedule> schedules, {
  int? targetId,
  int? defaultId,
  List<String> targetExams = const ['bcs'],
}) {
  if (schedules.isEmpty) return null;
  ExamSchedule? byId(int? id) {
    if (id == null) return null;
    for (final s in schedules) {
      if (s.id == id) return s;
    }
    return null;
  }

  final sorted = [...schedules]..sort((a, b) => a.expectedDate.compareTo(b.expectedDate));
  ExamSchedule? firstOf(String type) {
    for (final s in sorted) {
      if (s.examType == type) return s;
    }
    return null;
  }

  final fallback = byId(defaultId);
  return byId(targetId) ??
      (fallback != null && targetExams.contains(fallback.examType) ? fallback : null) ??
      targetExams.map(firstOf).whereType<ExamSchedule>().firstOrNull ??
      fallback ??
      firstOf('bcs') ??
      sorted.first;
}
