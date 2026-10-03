import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/bookmarks/data/bookmark.dart';
import 'package:prostuti/features/bookmarks/presentation/widgets/bookmark_cards.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';

Widget _host(Widget child, {Locale locale = const Locale('bn')}) => ProviderScope(
  overrides: [
    subjectsProvider.overrideWith(
      (ref) async => const [
        Subject(id: 3, code: 'bd', nameBn: 'বাংলাদেশ বিষয়াবলি', nameEn: 'Bangladesh Affairs', bcsMarks: 30),
      ],
    ),
  ],
  child: MaterialApp(
    locale: locale,
    theme: AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('bn');
    await initializeDateFormatting('en');
  });

  testWidgets('question card shows the correct answer and explanation', (tester) async {
    final b = Bookmark(
      type: BookmarkType.question,
      itemId: '7',
      createdAt: DateTime.now().toUtc(),
      payload: const {
        'subject_id': 3,
        'stem': 'বাংলাদেশের জাতীয় ফুল কোনটি?',
        'options': ['শাপলা', 'গোলাপ'],
        'correct_index': 0,
        'explanation': 'শাপলা জাতীয় ফুল।',
      },
    );
    await tester.pumpWidget(_host(BookmarkQuestionCard(bookmark: b)));
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('bn'));
    expect(find.text('বাংলাদেশের জাতীয় ফুল কোনটি?'), findsOneWidget);
    expect(find.text('বাংলাদেশ বিষয়াবলি'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text(l.bookmarksExplanation), findsOneWidget);
    expect(find.text(l.bookmarksAnswerUnknown), findsNothing);
  });

  testWidgets('note card collapses long fact lists and expands on tap', (tester) async {
    final b = Bookmark(
      type: BookmarkType.note,
      itemId: '1',
      createdAt: DateTime.utc(2026, 9),
      payload: const {
        'note_date': '2026-09-01',
        'category': 'economy',
        'title': 'বাজেট ২০২৬-২৭',
        'summary': 'সারাংশ',
        'key_facts': ['এক', 'দুই', 'তিন', 'চার', 'পাঁচ'],
      },
    );
    await tester.pumpWidget(_host(BookmarkNoteCard(bookmark: b)));
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('bn'));
    expect(find.text('বাজেট ২০২৬-২৭'), findsOneWidget);
    expect(find.text(l.bookmarksCatEconomy), findsOneWidget);
    expect(find.text('চার'), findsNothing);
    await tester.tap(find.text(l.bookmarksShowMore('২')));
    await tester.pumpAndSettle();
    expect(find.text('চার'), findsOneWidget);
    expect(find.text(l.bookmarksShowLess), findsOneWidget);
  });
}
