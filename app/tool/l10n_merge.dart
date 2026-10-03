// Merges every feature's ARB fragments into the app-wide ARB files that
// `flutter gen-l10n` consumes.
//
//   lib/core/l10n/core_{en,bn}.arb
//   lib/features/<feature>/l10n/<feature>_{en,bn}.arb
//        ↓  dart run tool/l10n_merge.dart
//   lib/l10n/arb/app_{en,bn}.arb
//
// Fails on duplicate keys or on keys missing from one locale, so features can
// own their strings without stepping on each other.
// ignore_for_file: avoid_print, cascade_invocations
import 'dart:convert';
import 'dart:io';

const locales = ['en', 'bn'];

void main(List<String> args) {
  final check = args.contains('--check');
  final root = Directory('lib');
  final fragments =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => f.path.contains('${Platform.pathSeparator}l10n${Platform.pathSeparator}') && f.path.endsWith('.arb'),
          )
          .where((f) => !f.path.contains('${Platform.pathSeparator}l10n${Platform.pathSeparator}arb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final merged = {
    for (final l in locales) l: <String, dynamic>{'@@locale': l},
  };
  final owners = {for (final l in locales) l: <String, String>{}};
  var failed = false;

  for (final file in fragments) {
    final locale = RegExp(r'_([a-z]{2})\.arb$').firstMatch(file.path)?.group(1);
    if (locale == null || !locales.contains(locale)) continue;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    json.forEach((key, value) {
      if (key.startsWith('@@')) return;
      if (!key.startsWith('@') && owners[locale]!.containsKey(key)) {
        print('✗ duplicate key "$key" in ${file.path} (already in ${owners[locale]![key]})');
        failed = true;
      }
      if (!key.startsWith('@')) owners[locale]![key] = file.path;
      // Placeholder metadata lives in the English template only.
      if (key.startsWith('@') && locale != 'en') return;
      merged[locale]![key] = value;
    });
  }

  final enKeys = merged['en']!.keys.where((k) => !k.startsWith('@')).toSet();
  for (final l in locales.where((l) => l != 'en')) {
    final keys = merged[l]!.keys.where((k) => !k.startsWith('@')).toSet();
    for (final missing in enKeys.difference(keys)) {
      print('✗ "$missing" missing in $l');
      failed = true;
    }
    for (final extra in keys.difference(enKeys)) {
      print('✗ "$extra" exists in $l but not in en');
      failed = true;
    }
  }
  if (failed) exit(1);

  const encoder = JsonEncoder.withIndent('  ');
  var stale = false;
  for (final l in locales) {
    final sorted = {
      '@@locale': l,
      for (final k
          in (merged[l]!.keys.where((k) => k != '@@locale').toList()..sort(
            (a, b) => a.replaceFirst('@', '').compareTo(b.replaceFirst('@', '')) == 0
                ? (a.startsWith('@') ? 1 : -1)
                : a.replaceFirst('@', '').compareTo(b.replaceFirst('@', '')),
          )))
        k: merged[l]![k],
    };
    final out = File('lib/l10n/arb/app_$l.arb');
    final text = '${encoder.convert(sorted)}\n';
    if (check) {
      if (!out.existsSync() || out.readAsStringSync() != text) stale = true;
    } else {
      out
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
  }
  if (check && stale) {
    print('✗ merged ARB files are stale — run: dart run tool/l10n_merge.dart');
    exit(1);
  }
  print('✓ ${fragments.length} fragments, ${enKeys.length} keys');
}
