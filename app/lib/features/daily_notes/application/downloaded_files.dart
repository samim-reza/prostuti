import 'package:prostuti/core/utils/formatters.dart';

final _notesFile = RegExp(r'prostuti-notes-(\d{4})-(\d{2})-(\d{2})\.pdf$');

/// The notes date encoded in a saved file name
/// (`…/prostuti-notes-2026-10-04.pdf` → 2026-10-04), or null for other PDFs.
DateTime? notesDateFromFileName(String path) {
  final m = _notesFile.firstMatch(path);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime.utc(y, mo, d);
}

/// Last path segment.
String fileBaseName(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

/// File size split into a display value and unit: (`"240"`, kb) or
/// (`"1.4"`, mb). Digits are localized.
({String value, bool megabytes}) fileSizeParts(int bytes, {required bool bangla}) {
  if (bytes < 1024 * 1024) {
    final kb = (bytes / 1024).ceil().clamp(1, 1024);
    return (value: Fmt.digits(kb, bangla: bangla), megabytes: false);
  }
  final mb = (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.0', '');
  return (value: Fmt.digits(mb, bangla: bangla), megabytes: true);
}
