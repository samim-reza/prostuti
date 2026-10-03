import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/utils/formatters.dart';

/// Splits a remaining duration into whole hours and minutes, rounding *up*
/// to the next minute so the label never says "0 minutes" while time is
/// still left (minute-resolution countdown).
({int hours, int minutes}) splitCountdown(Duration remaining) {
  if (remaining <= Duration.zero) return (hours: 0, minutes: 0);
  final totalMinutes = (remaining.inSeconds + 59) ~/ 60;
  return (hours: totalMinutes ~/ 60, minutes: totalMinutes % 60);
}

/// "আর ৫ ঘণ্টা ২৩ মিনিট বাকি" / "5h 23m left"; "সময় শেষ…" when over.
String formatCountdown(Duration remaining, AppLocalizations l, {required bool bangla}) {
  final (:hours, :minutes) = splitCountdown(remaining);
  String n(int v) => Fmt.digits(v, bangla: bangla);
  if (hours == 0 && minutes == 0) return l.dailyNotesTimeUp;
  if (hours == 0) return l.dailyNotesTimeLeftM(n(minutes));
  return l.dailyNotesTimeLeftHm(n(hours), n(minutes));
}

/// Delay until the next wall-clock minute boundary (keeps the countdown in
/// sync with the phone's clock while ticking only once a minute).
Duration untilNextMinute(DateTime now) {
  final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
  final d = next.difference(now);
  return d <= Duration.zero ? const Duration(minutes: 1) : d;
}
