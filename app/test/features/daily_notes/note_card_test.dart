import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/note_card.dart';

const _note = DailyNote(
  id: 1,
  category: NoteCategory.international,
  title: 'জাতিসংঘ সাধারণ পরিষদের ৮১তম অধিবেশন',
  summary: 'নিউইয়র্কে অধিবেশন শুরু হয়েছে।',
  titleEn: '81st session of the UN General Assembly',
  keyFacts: [NoteFact(fact: 'সভাপতি: অ্যানালেনা বেয়ারবক', tag: 'ব্যক্তি')],
  probableQuestions: [ProbableQuestion(question: 'অধিবেশন কোথায় হয়?', answer: 'জাতিসংঘ সদর দপ্তর, যুক্তরাষ্ট্র')],
  importance: 5,
  sourceLinks: [SourceLink(url: 'https://www.prothomalo.com/a', source: 'Prothom Alo')],
);

Widget _host(Widget child, {Locale locale = const Locale('bn'), ThemeData? theme}) => MaterialApp(
  locale: locale,
  theme: theme ?? AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('shows note content and reveals answers on tap', (tester) async {
    await tester.pumpWidget(_host(const NoteCard(note: _note)));
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('bn'));

    expect(find.text(_note.title), findsOneWidget);
    expect(find.text('আন্তর্জাতিক'), findsOneWidget);
    expect(find.text(l.dailyNotesImportanceTop), findsOneWidget);
    expect(find.text('Prothom Alo'), findsOneWidget);

    // Questions are collapsed until the header is tapped.
    expect(find.textContaining('অধিবেশন কোথায় হয়?'), findsNothing);
    await tester.tap(find.text(l.dailyNotesProbableQuestions('১')));
    await tester.pumpAndSettle();
    expect(find.textContaining('অধিবেশন কোথায় হয়?'), findsOneWidget);

    // Answer is hidden until revealed.
    expect(find.textContaining('যুক্তরাষ্ট্র', findRichText: true), findsNothing);
    await tester.tap(find.text(l.dailyNotesShowAnswer));
    await tester.pumpAndSettle();
    expect(find.textContaining('যুক্তরাষ্ট্র', findRichText: true), findsOneWidget);
  });

  testWidgets('bookmark button reports taps and reflects state', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(NoteCard(note: _note, bookmarked: true, onToggleBookmark: () => taps++)));
    final l = lookupAppLocalizations(const Locale('bn'));
    expect(find.byTooltip(l.dailyNotesBookmarkRemove), findsOneWidget);
    await tester.tap(find.byTooltip(l.dailyNotesBookmarkRemove));
    expect(taps, 1);
  });

  testWidgets('English UI uses English fields with Bangla fallback, dark mode renders', (tester) async {
    await tester.pumpWidget(
      _host(
        const NoteCard(note: _note),
        locale: const Locale('en'),
        theme: AppTheme.dark(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('81st session of the UN General Assembly'), findsOneWidget);
    // No English summary → Bangla original.
    expect(find.text(_note.summary), findsOneWidget);
    expect(find.text('International'), findsOneWidget);
  });
}
