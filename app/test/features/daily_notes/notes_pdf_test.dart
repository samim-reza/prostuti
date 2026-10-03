import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/services/pdf_export_service.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/presentation/notes_download_flow.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/note_category_style.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/notes_print_blocks.dart';

const _note = DailyNote(
  id: 5,
  category: NoteCategory.economy,
  title: 'বাজেট ২০২৬-২৭',
  summary: 'জাতীয় সংসদে বাজেট পাস হয়েছে।',
  titleEn: 'Budget 2026-27',
  keyFacts: [
    NoteFact(fact: 'আকার: ৮ লাখ কোটি টাকা', tag: 'সংখ্যা'),
    NoteFact(fact: 'জিডিপি প্রবৃদ্ধি লক্ষ্য ৬.৫%'),
  ],
  probableQuestions: [ProbableQuestion(question: 'বাজেটের আকার কত?', answer: '৮ লাখ কোটি টাকা')],
  importance: 4,
  sourceLinks: [SourceLink(url: 'https://www.prothomalo.com/a', source: 'Prothom Alo', title: 'বাজেট পাস')],
);

NotesPrintStrings _strings(AppLocalizations l, {required bool bangla}) => NotesPrintStrings(
  brand: l.dailyNotesPdfBrand,
  tagline: l.dailyNotesPdfTagline,
  dateLabel: notesLongDate(DateTime.utc(2026, 10, 4), bangla: bangla),
  countLabel: l.dailyNotesNoteCount('১'),
  keyFacts: l.dailyNotesKeyFacts,
  probableQuestions: l.dailyNotesPdfProbableQuestions,
  answer: l.dailyNotesAnswer,
  sources: l.dailyNotesSources,
  footer: l.dailyNotesPdfFooter,
  downloadedBy: l.dailyNotesPdfDownloadedBy('rahim'),
  categoryLabel: (c) => noteCategoryLabel(l, c),
  importanceLabel: (level) => noteImportanceLabel(l, level),
  bangla: bangla,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('bn');
    await initializeDateFormatting('en');
  });

  test('file name and long date', () {
    expect(notesPdfFileName('2026-10-04'), 'prostuti-notes-2026-10-04.pdf');
    expect(notesLongDate(DateTime.utc(2026, 10, 4), bangla: false), 'Sunday, 4 October 2026');
    expect(notesLongDate(DateTime.utc(2026, 10, 4), bangla: true), contains('অক্টোবর'));
  });

  testWidgets('print blocks render without Localizations/Navigator (off-screen tree), in dark mode too', (
    tester,
  ) async {
    final l = lookupAppLocalizations(const Locale('bn'));
    final strings = _strings(l, bangla: true);
    // Mirrors the ancestors PdfExportService provides.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(539, 2000)),
        child: Theme(
          data: AppTheme.dark(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Material(
              color: Colors.white,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 539,
                  child: Column(
                    children: [
                      NotesPrintHeader(strings: strings),
                      NotePrintBlock(note: _note, index: 1, strings: strings),
                      NotesPrintFooter(strings: strings),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(l.dailyNotesPdfBrand), findsOneWidget);
    expect(find.text(_note.title), findsOneWidget);
    expect(find.textContaining('৮ লাখ কোটি টাকা', findRichText: true), findsWidgets);
    expect(find.text(l.dailyNotesPdfDownloadedBy('rahim')), findsOneWidget);
  });

  testWidgets('PdfExportService builds a real PDF from the blocks', (tester) async {
    final l = lookupAppLocalizations(const Locale('en'));
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final strings = _strings(l, bangla: false);
    final bytes = await tester.runAsync(
      () => PdfExportService.instance.buildPdf(
        context: ctx,
        blocks: [
          NotesPrintHeader(strings: strings),
          for (var i = 0; i < 4; i++) NotePrintBlock(note: _note, index: i + 1, strings: strings),
          NotesPrintFooter(strings: strings),
        ],
        watermark: '@rahim',
        pixelRatio: 1,
      ),
    );
    expect(bytes, isNotNull);
    expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
  });
}
