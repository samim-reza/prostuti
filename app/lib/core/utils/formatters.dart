import 'package:intl/intl.dart';
import 'package:prostuti/core/utils/bd_time.dart';

const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// Locale-aware number/date/time formatting. Bangla UI uses Bangla digits.
abstract final class Fmt {
  static String digits(Object value, {required bool bangla}) {
    final s = value.toString();
    if (!bangla) return s;
    final b = StringBuffer();
    for (final c in s.codeUnits) {
      b.write(c >= 48 && c <= 57 ? _bnDigits[c - 48] : String.fromCharCode(c));
    }
    return b.toString();
  }

  /// Compact counts: 1.2K / ১.২হা
  static String count(int n, {required bool bangla}) {
    if (n < 1000) return digits(n, bangla: bangla);
    if (n < 1000000) {
      final v = (n / 1000).toStringAsFixed(n < 10000 ? 1 : 0).replaceAll('.0', '');
      return '${digits(v, bangla: bangla)}${bangla ? 'হা' : 'K'}';
    }
    final v = (n / 1000000).toStringAsFixed(1).replaceAll('.0', '');
    return '${digits(v, bangla: bangla)}${bangla ? 'মি' : 'M'}';
  }

  static String score(num value, {required bool bangla}) {
    final s = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');
    return digits(s, bangla: bangla);
  }

  static String percent(num value, {required bool bangla}) => '${digits(value.round(), bangla: bangla)}%';

  /// "৫ মিনিট আগে" / "5m ago"
  static String timeAgo(DateTime time, {required bool bangla}) {
    final diff = DateTime.now().toUtc().difference(time.toUtc());
    String n(int v) => digits(v, bangla: bangla);
    if (diff.inSeconds < 60) return bangla ? 'এইমাত্র' : 'just now';
    if (diff.inMinutes < 60) return bangla ? '${n(diff.inMinutes)} মিনিট আগে' : '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return bangla ? '${n(diff.inHours)} ঘণ্টা আগে' : '${diff.inHours}h ago';
    if (diff.inDays < 7) return bangla ? '${n(diff.inDays)} দিন আগে' : '${diff.inDays}d ago';
    return date(time, bangla: bangla);
  }

  static String date(DateTime time, {required bool bangla, bool withYear = true}) {
    final d = BdTime.toBd(time);
    final pattern = withYear ? 'd MMMM y' : 'd MMMM';
    return DateFormat(pattern, bangla ? 'bn' : 'en').format(d);
  }

  static String time(DateTime time, {required bool bangla}) {
    final d = BdTime.toBd(time);
    return DateFormat('h:mm a', bangla ? 'bn' : 'en').format(d);
  }

  /// mm:ss countdown (exam timer).
  static String clock(Duration d, {required bool bangla}) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return digits(h > 0 ? '$h:$m:$s' : '$m:$s', bangla: bangla);
  }

  static String minutes(int minutes, {required bool bangla}) {
    if (minutes < 60) return bangla ? '${digits(minutes, bangla: true)} মিনিট' : '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (bangla) {
      return m == 0
          ? '${digits(h, bangla: true)} ঘণ্টা'
          : '${digits(h, bangla: true)} ঘণ্টা ${digits(m, bangla: true)} মিনিট';
    }
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String currency(num amount, {required bool bangla}) =>
      bangla ? '৳${digits(amount.toInt(), bangla: true)}' : '৳${amount.toInt()}';
}
