import 'package:flutter/material.dart';
import 'package:prostuti/core/utils/formatters.dart';

/// Default daily-exam reminder (matches the `profiles.reminder_time` default).
const defaultReminderTime = TimeOfDay(hour: 20, minute: 0);

/// `TimeOfDay` → Postgres `time` literal (`'HH:mm:00'`).
String timeOfDayToDb(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

/// Postgres `time` (`'HH:mm:ss'`) or `'HH:mm'` → `TimeOfDay`. Malformed or
/// out-of-range values fall back to [fallback].
TimeOfDay timeOfDayFromDb(String? value, {TimeOfDay fallback = defaultReminderTime}) {
  if (value == null) return fallback;
  final match = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch(value);
  if (match == null) return fallback;
  final h = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  if (h > 23 || m > 59) return fallback;
  return TimeOfDay(hour: h, minute: m);
}

/// Bangla day-part word used before a 12-hour time ("রাত ৮:০০").
String banglaDayPart(int hour) {
  if (hour >= 4 && hour < 6) return 'ভোর';
  if (hour >= 6 && hour < 12) return 'সকাল';
  if (hour >= 12 && hour < 15) return 'দুপুর';
  if (hour >= 15 && hour < 18) return 'বিকাল';
  if (hour >= 18 && hour < 20) return 'সন্ধ্যা';
  return 'রাত';
}

/// "রাত ৮:০০" in Bangla, "8:00 PM" in English.
String formatTimeOfDay(TimeOfDay time, {required bool bangla}) {
  final h12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final clock = '$h12:${time.minute.toString().padLeft(2, '0')}';
  if (bangla) return '${banglaDayPart(time.hour)} ${Fmt.digits(clock, bangla: true)}';
  return '$clock ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
}
