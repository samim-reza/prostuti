import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/features/daily_notes/application/countdown.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/note_category_style.dart';

void main() {
  final bn = lookupAppLocalizations(const Locale('bn'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('category label mapping', () {
    test('Bangla labels', () {
      expect(noteCategoryLabel(bn, NoteCategory.bangladesh), 'বাংলাদেশ');
      expect(noteCategoryLabel(bn, NoteCategory.international), 'আন্তর্জাতিক');
      expect(noteCategoryLabel(bn, NoteCategory.economy), 'অর্থনীতি');
      expect(noteCategoryLabel(bn, NoteCategory.scienceTech), 'বিজ্ঞান ও প্রযুক্তি');
      expect(noteCategoryLabel(bn, NoteCategory.sports), 'খেলাধুলা');
      expect(noteCategoryLabel(bn, NoteCategory.misc), 'বিবিধ');
    });

    test('every category has a distinct label, icon and colour in both languages', () {
      for (final l in [bn, en]) {
        final labels = NoteCategory.values.map((c) => noteCategoryLabel(l, c)).toSet();
        expect(labels, hasLength(NoteCategory.values.length));
        expect(labels.every((s) => s.trim().isNotEmpty), isTrue);
      }
      expect(NoteCategory.values.map(noteCategoryIcon).toSet(), hasLength(NoteCategory.values.length));
      expect(NoteCategory.values.map(noteCategoryBaseColor).toSet(), hasLength(NoteCategory.values.length));
      expect(noteCategoryLabel(en, NoteCategory.awardsPeople), 'Awards & people');
    });

    test('dark mode lightens category colours', () {
      final light = noteCategoryColor(NoteCategory.bangladesh, Brightness.light);
      final dark = noteCategoryColor(NoteCategory.bangladesh, Brightness.dark);
      expect(dark.computeLuminance(), greaterThan(light.computeLuminance()));
    });

    test('importance labels', () {
      expect(noteImportanceLabel(bn, 5), bn.dailyNotesImportanceTop);
      expect(noteImportanceLabel(bn, 4), bn.dailyNotesImportanceHigh);
      expect(noteImportanceLabel(bn, 3), bn.dailyNotesImportanceMedium);
      expect(noteImportanceLabel(bn, 1), bn.dailyNotesImportanceLow);
    });
  });

  group('countdown', () {
    test('splitCountdown rounds up to the next minute', () {
      expect(splitCountdown(const Duration(hours: 5, minutes: 22, seconds: 10)), (hours: 5, minutes: 23));
      expect(splitCountdown(const Duration(hours: 5, minutes: 23)), (hours: 5, minutes: 23));
      expect(splitCountdown(const Duration(seconds: 1)), (hours: 0, minutes: 1));
      expect(splitCountdown(const Duration(minutes: 59, seconds: 30)), (hours: 1, minutes: 0));
      expect(splitCountdown(Duration.zero), (hours: 0, minutes: 0));
      expect(splitCountdown(const Duration(seconds: -5)), (hours: 0, minutes: 0));
    });

    test('formatCountdown in Bangla uses Bangla digits', () {
      expect(formatCountdown(const Duration(hours: 5, minutes: 23), bn, bangla: true), 'আর ৫ ঘণ্টা ২৩ মিনিট বাকি');
      expect(formatCountdown(const Duration(minutes: 7), bn, bangla: true), 'আর ৭ মিনিট বাকি');
      expect(formatCountdown(Duration.zero, bn, bangla: true), bn.dailyNotesTimeUp);
    });

    test('formatCountdown in English', () {
      expect(formatCountdown(const Duration(hours: 12), en, bangla: false), '12h 0m left');
      expect(formatCountdown(const Duration(minutes: 3, seconds: 1), en, bangla: false), '4 min left');
    });

    test('untilNextMinute aligns to the wall clock', () {
      expect(untilNextMinute(DateTime(2026, 10, 4, 10, 15, 42)), const Duration(seconds: 18));
      expect(untilNextMinute(DateTime(2026, 10, 4, 23, 59, 59, 500)), const Duration(milliseconds: 500));
      expect(untilNextMinute(DateTime(2026, 10, 4, 10, 15)), const Duration(minutes: 1));
    });
  });
}
