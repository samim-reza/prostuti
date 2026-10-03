/// Bangladesh Standard Time helpers (UTC+6, no daylight saving).
///
/// The product's "day" (today's notes, streaks, routines) is the Bangladesh
/// calendar day, independent of the device's time zone.
abstract final class BdTime {
  static const offset = Duration(hours: 6);

  /// Current wall-clock time in Bangladesh (as a UTC-flagged DateTime whose
  /// fields read as Dhaka local time).
  static DateTime now() => DateTime.now().toUtc().add(offset);

  /// Today's date in Bangladesh (time stripped).
  static DateTime today() {
    final n = now();
    return DateTime.utc(n.year, n.month, n.day);
  }

  /// `yyyy-MM-dd` for today in Bangladesh — matches Postgres `bd_today()`.
  static String todayIso() => toIsoDate(today());

  static String toIsoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The instant the current Bangladesh day ends (used as a cache TTL for
  /// "today only" data such as daily notes).
  static DateTime endOfToday() {
    final t = today();
    return t.add(const Duration(days: 1)).subtract(offset); // back to real UTC instant
  }

  static Duration untilEndOfToday() {
    final d = endOfToday().difference(DateTime.now().toUtc());
    return d.isNegative ? Duration.zero : d;
  }

  /// Converts a server timestamp to Dhaka wall-clock for display.
  static DateTime toBd(DateTime instant) => instant.toUtc().add(offset);
}
