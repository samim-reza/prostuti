import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/features/daily_exam/application/leaderboard_providers.dart';
import 'package:prostuti/features/daily_exam/data/daily_standing.dart';
import 'package:prostuti/features/daily_exam/presentation/screens/leaderboard_screen.dart';
import 'package:prostuti/features/daily_exam/presentation/widgets/standing_widgets.dart';
import 'package:prostuti/features/feed/presentation/screens/compose_post_screen.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

class _FakeProfile extends CurrentProfileNotifier {
  @override
  Future<Profile?> build() async => const Profile(id: 'me', username: 'me_user', fullName: 'আমি');
}

/// Rank 12 of 340, 13.5/15 in 5:12; the day's top score is 15.
final _attempted = DailyStanding.fromJson({
  'date': '2026-10-04',
  'participants': 340,
  'total_marks': 15,
  'top_score': 15,
  'me': const {'rank': 12, 'score': 13.5, 'time_taken_seconds': 312, 'percentile': 3.5},
  'neighbors': [
    for (final (rank, score) in [(9, 14.0), (10, 14.0), (11, 13.5), (13, 13.0), (14, 13.0), (15, 12.5)])
      {'rank': rank, 'score': score},
  ],
});

final _notAttempted = DailyStanding.fromJson(const {
  'date': '2026-10-04',
  'participants': 340,
  'total_marks': 15,
  'top_score': 15,
});

const _noExam = DailyStanding(date: '2026-10-04', participants: 0);

Future<void> _pump(
  WidgetTester tester,
  FutureOr<DailyStanding> Function(String date) standing, {
  Locale locale = const Locale('bn'),
  ThemeData? theme,
  bool online = true,
  bool settle = true,
}) async {
  tester.view
    ..physicalSize = const Size(480, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('me'),
        currentProfileProvider.overrideWith(_FakeProfile.new),
        dailyLeaderboardProvider.overrideWith((ref, date) async => standing(date)),
        isOnlineProvider.overrideWith((ref) => Stream.value(online)),
      ],
      child: MaterialApp(
        locale: locale,
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LeaderboardScreen(),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  final l = lookupAppLocalizations(const Locale('bn'));
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await initializeDateFormatting('bn');
    await initializeDateFormatting('en');
  });

  testWidgets('attempted: hero with rank, Top %, score, time and top score; anonymous ladder', (tester) async {
    await _pump(tester, (_) => _attempted);

    expect(find.byType(StandingHero), findsOneWidget);
    expect(find.text(l.dailyExamRank('১২')), findsOneWidget);
    expect(find.text(l.dailyExamOfParticipants('৩৪০')), findsOneWidget);
    expect(find.text(l.dailyExamTopPercent('৪')), findsOneWidget);
    expect(find.text('১৩.৫/১৫'), findsOneWidget, reason: 'my score out of the full marks');
    expect(find.text('০৫:১২'), findsWidgets, reason: 'time taken, in the hero and on my rung');
    expect(find.bySemanticsLabel(RegExp('${l.dailyExamTopScore} ১৫/১৫')), findsOneWidget);

    // Ladder: #1 rung + 3 above + 3 below, every one anonymous and blurred.
    final hidden = find.bySemanticsLabel(RegExp(', ${l.dailyExamIdentityHidden}\$'));
    expect(hidden, findsNWidgets(7));
    expect(find.bySemanticsLabel(RegExp('^${l.dailyExamYou}, ${l.dailyExamRankSemantics('১২')}')), findsOneWidget);
    expect(find.text('আমি'), findsOneWidget, reason: 'only my own name is shown');
    expect(find.text(l.dailyExamBehindNext('০.৫', '১০')), findsOneWidget);

    expect(find.text(l.dailyExamShareScore), findsOneWidget);
    expect(find.text(l.dailyExamTakeNow), findsNothing);
    expect(find.byType(LockedLadder), findsNothing);
  });

  testWidgets('not attempted today: CTA, participants, top score and a locked ladder', (tester) async {
    await _pump(tester, (_) => _notAttempted);

    expect(find.text(l.dailyExamNotJoinedToday), findsOneWidget);
    expect(find.text(l.dailyExamNotTakenBody('৩৪০')), findsOneWidget);
    expect(find.text(l.dailyExamTakeNow), findsOneWidget);
    expect(find.bySemanticsLabel('${l.dailyExamParticipantsLabel} ৩৪০'), findsOneWidget);
    expect(find.bySemanticsLabel('${l.dailyExamTopScore} ১৫/১৫'), findsOneWidget);
    expect(find.byType(LockedLadder), findsOneWidget);
    expect(find.byType(StandingHero), findsNothing);
    expect(find.text(l.dailyExamShareScore), findsNothing);
  });

  testWidgets('no exam published: friendly empty state', (tester) async {
    await _pump(tester, (_) => _noExam);
    expect(find.text(l.dailyExamNoExamTitle), findsOneWidget);
    expect(find.byType(StandingHero), findsNothing);
  });

  testWidgets('loading shows a skeleton', (tester) async {
    final never = Completer<DailyStanding>();
    await _pump(tester, (_) => never.future, settle: false);
    await tester.pump();
    expect(find.byType(SkeletonShimmer), findsOneWidget);
  });

  testWidgets('errors offer a retry', (tester) async {
    await _pump(tester, (_) => throw const NetworkFailure());
    expect(find.text(l.errorNetwork), findsOneWidget);
    expect(find.text(l.retry), findsOneWidget);
  });

  testWidgets('offline: the saved standing is shown with a note', (tester) async {
    await _pump(tester, (_) => _attempted, online: false);
    expect(find.text(l.dailyExamSavedStanding), findsOneWidget);
    expect(find.byType(StandingHero), findsOneWidget);
    expect(ConnectivityService.instance.isOnline, isTrue, reason: 'only the provider was faked');
  });

  testWidgets('dark theme renders the hero and ladder', (tester) async {
    await _pump(tester, (_) => _attempted, theme: AppTheme.dark());
    expect(find.byType(StandingHero), findsOneWidget);
    expect(find.byType(StandingLadder), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Share opens the composer with an editable draft; an untouched draft closes freely', (tester) async {
    await _pump(tester, (_) => _attempted);

    await tester.tap(find.text(l.dailyExamShareScore));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePostScreen), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'আজকের দৈনিক সাম্প্রতিক পরীক্ষায় আমার র‍্যাংক ১২/৩৪০, স্কোর ১৩.৫/১৫ 🎯 #প্রস্তুতি');

    // Untouched → no discard prompt.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePostScreen), findsNothing);
    expect(find.text(l.feedDiscardTitle), findsNothing);

    // Edited → the usual discard guard.
    await tester.tap(find.text(l.dailyExamShareScore));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'আমার আজকের ফল!');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text(l.feedDiscardTitle), findsOneWidget);
  });

  testWidgets('English draft uses Latin digits', (tester) async {
    await _pump(tester, (_) => _attempted, locale: const Locale('en'));
    await tester.tap(find.text(en.dailyExamShareScore));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, "My rank in today's daily current-affairs exam: 12/340, score 13.5/15 🎯 #Prostuti");
  });
}
