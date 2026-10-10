import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/daily_exam/application/leaderboard_providers.dart';
import 'package:prostuti/features/daily_exam/data/daily_standing.dart';
import 'package:prostuti/features/daily_exam/presentation/screens/daily_exam_screen.dart';
import 'package:prostuti/features/daily_exam/presentation/widgets/standing_widgets.dart';
import 'package:prostuti/features/daily_notes/application/today_notes_controller.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';

class _FakeTodayNotes extends TodayNotesNotifier {
  _FakeTodayNotes(this.value);
  final TodayNotes value;

  @override
  Future<TodayNotes> build() async => value;
}

const _exam = DailyExamInfo(id: 1, title: 'আজকের সাম্প্রতিক পরীক্ষা', questionCount: 20, durationMinutes: 10);

DailyStanding _standing({MyStanding? me}) => DailyStanding(
  date: '2026-10-04',
  participants: 12,
  totalMarks: 20,
  topScore: 19.5,
  me: me,
  neighbors: me == null ? const [] : const [LadderRung(rank: 8, score: 12), LadderRung(rank: 10, score: 11)],
);

Future<void> _pump(WidgetTester tester, {DailyExamInfo? exam, MyStanding? me}) async {
  // Tall surface so the whole page (incl. the leaderboard preview) is built.
  tester.view
    ..physicalSize = const Size(480, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('me'),
        featureAccessProvider.overrideWith((ref) async => {Features.dailyExam: true}),
        todayNotesProvider.overrideWith(() => _FakeTodayNotes(TodayNotes(noteDate: '2026-10-04', dailyExam: exam))),
        dailyLeaderboardProvider.overrideWith((ref, date) async => _standing(me: me)),
        activeDailySessionProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        locale: const Locale('bn'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DailyExamScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final l = lookupAppLocalizations(const Locale('bn'));

  setUpAll(() async {
    await initializeDateFormatting('bn');
    await initializeDateFormatting('en');
  });

  testWidgets('intro: exam details, rules, start button and a private live preview', (tester) async {
    await _pump(tester, exam: _exam);
    expect(find.text(_exam.title), findsOneWidget);
    expect(find.text(l.dailyExamQuestionsValue('২০')), findsOneWidget);
    expect(find.text(l.dailyExamNegativeValue('০.৫')), findsOneWidget);
    expect(find.text(l.dailyExamRuleOnce), findsOneWidget);
    expect(find.text(l.dailyExamStart), findsOneWidget);
    // Participants and the top score only — no names.
    expect(find.text(l.dailyExamTodayStanding), findsOneWidget);
    expect(find.bySemanticsLabel('${l.dailyExamParticipantsLabel} ১২'), findsOneWidget);
    expect(find.bySemanticsLabel('${l.dailyExamTopScore} ১৯.৫/২০'), findsOneWidget);
    expect(find.text(l.dailyExamGetYourRank), findsOneWidget);
    expect(find.byType(StandingSummaryCard), findsNothing);
    await tester.pumpWidget(const SizedBox()); // disposes the live-refresh timer
  });

  testWidgets('already attempted: done card, my rank, leaderboard + history buttons', (tester) async {
    await _pump(tester, exam: _exam, me: const MyStanding(rank: 9, score: 11.5, timeTakenSeconds: 420, percentile: 75));
    expect(find.text(l.dailyExamAttemptedTitle), findsOneWidget);
    expect(find.text(l.dailyExamStart), findsNothing);
    expect(find.text(l.dailyExamHistory), findsOneWidget);
    expect(find.byType(StandingSummaryCard), findsOneWidget);
    expect(find.textContaining('#৯', findRichText: true), findsOneWidget);
    expect(find.text('১১.৫/২০'), findsOneWidget);
    expect(find.text(l.dailyExamTopPercent('৭৫')), findsOneWidget);
    // The pre-exam preview is gone once I have a rank.
    expect(find.text(l.dailyExamTodayStanding), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no exam published yet: friendly empty state', (tester) async {
    await _pump(tester);
    expect(find.text(l.dailyExamNoExamTitle), findsOneWidget);
    expect(find.text(l.dailyExamStart), findsNothing);
    expect(find.text(l.dailyExamTodayStanding), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
