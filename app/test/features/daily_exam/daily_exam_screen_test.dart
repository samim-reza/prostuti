import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/daily_exam/application/leaderboard_providers.dart';
import 'package:prostuti/features/daily_exam/data/daily_leaderboard.dart';
import 'package:prostuti/features/daily_exam/presentation/screens/daily_exam_screen.dart';
import 'package:prostuti/features/daily_exam/presentation/widgets/leaderboard_widgets.dart';
import 'package:prostuti/features/daily_notes/application/today_notes_controller.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';

class _FakeTodayNotes extends TodayNotesNotifier {
  _FakeTodayNotes(this.value);
  final TodayNotes value;

  @override
  Future<TodayNotes> build() async => value;
}

const _exam = DailyExamInfo(id: 1, title: 'আজকের সাম্প্রতিক পরীক্ষা', questionCount: 20, durationMinutes: 10);

DailyLeaderboard _board({MyStanding? me}) => DailyLeaderboard.fromJson({
  'date': '2026-10-04',
  'participants': 12,
  'entries': [
    for (var i = 1; i <= 5; i++)
      {'rank': i, 'user_id': 'u$i', 'username': 'user$i', 'score': 20.0 - i, 'time_taken_seconds': 300 + i},
  ],
  'me': me?.toJson(),
});

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
        dailyLeaderboardProvider.overrideWith((ref, q) async => _board(me: me)),
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

  testWidgets('intro: exam details, rules, start button and top-5 preview', (tester) async {
    await _pump(tester, exam: _exam);
    expect(find.text(_exam.title), findsOneWidget);
    expect(find.text(l.dailyExamQuestionsValue('২০')), findsOneWidget);
    expect(find.text(l.dailyExamNegativeValue('০.৫')), findsOneWidget);
    expect(find.text(l.dailyExamRuleOnce), findsOneWidget);
    expect(find.text(l.dailyExamStart), findsOneWidget);
    expect(find.text(l.dailyExamTopFive), findsOneWidget);
    expect(find.byType(LeaderboardRow), findsNWidgets(5));
    // Not attempted → nothing pinned.
    expect(find.byType(MyRankCard), findsNothing);
    await tester.pumpWidget(const SizedBox()); // disposes the live-refresh timer
  });

  testWidgets('already attempted: done card, my rank, leaderboard + history buttons', (tester) async {
    await _pump(tester, exam: _exam, me: const MyStanding(rank: 9, score: 11.5, timeTakenSeconds: 420));
    expect(find.text(l.dailyExamAttemptedTitle), findsOneWidget);
    expect(find.text(l.dailyExamStart), findsNothing);
    expect(find.text(l.dailyExamHistory), findsOneWidget);
    // Rank 9 is outside the top 5 → shown in the done card and pinned in the preview.
    expect(find.byType(MyRankCard), findsNWidgets(2));
    expect(find.textContaining('#৯', findRichText: true), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no exam published yet: friendly empty state', (tester) async {
    await _pump(tester);
    expect(find.text(l.dailyExamNoExamTitle), findsOneWidget);
    expect(find.text(l.dailyExamStart), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
