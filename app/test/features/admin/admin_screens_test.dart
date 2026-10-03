import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/admin/application/admin_controllers.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';
import 'package:prostuti/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:prostuti/features/admin/presentation/widgets/question_editor_page.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

class _FakeProfile extends CurrentProfileNotifier {
  _FakeProfile(this.role);
  final String role;

  @override
  Future<Profile?> build() async => Profile(id: 'a', username: 'admin', role: role);
}

Widget _host(Widget child, {String role = 'admin', Locale locale = const Locale('bn')}) => ProviderScope(
  overrides: [
    currentProfileProvider.overrideWith(() => _FakeProfile(role)),
    adminDashboardProvider.overrideWith(
      (ref) async => const AdminStats(
        users: 15230,
        activeToday: 812,
        postsToday: 64,
        questions: 545,
        questionsUnverified: 37,
        questionsFlagged: 4,
        facts: 1200,
        notesToday: 18,
        dailyExamToday: true,
        activePlans: 940,
        openReports: 3,
        aiCallsToday: 120,
        aiCacheHitsToday: 45,
      ),
    ),
  ],
  child: MaterialApp(
    locale: locale,
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

void main() {
  testWidgets('admin dashboard shows stats, management links and pipeline', (tester) async {
    await tester.pumpWidget(_host(const AdminDashboardScreen()));
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('bn'));
    expect(find.text('১৫হা'), findsOneWidget);
    expect(find.text(l.adminDailyExamReady), findsOneWidget);
    await tester.scrollUntilVisible(find.text(l.adminSchedulesTitle), 300, scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.text(l.adminStageNotify), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text(l.adminStageIngest), findsOneWidget);
  });

  testWidgets('moderators do not get pipeline or schedule tools', (tester) async {
    await tester.pumpWidget(_host(const AdminDashboardScreen(), role: 'moderator', locale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Reports'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Exam schedules'), findsNothing);
    expect(find.text('AI pipeline'), findsNothing);
  });

  testWidgets('question editor validates and returns the edit', (tester) async {
    QuestionEdit? result;
    const q = AdminQuestion(id: 9, subjectId: 1, stem: 'প্রশ্ন?', options: ['ক', 'খ'], correctIndex: 0);
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await QuestionEditorPage.open(context, q),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('bn'));
    await tester.tap(find.text(l.adminEditAddOption));
    await tester.pumpAndSettle();
    // Empty third option is rejected.
    final save = find.widgetWithText(TextButton, l.save);
    await tester.tap(save);
    await tester.pump();
    expect(find.text(l.adminEditErrorEmptyOption), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(3), 'গ');
    await tester.tap(find.byType(Radio<int>).at(2));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.options, ['ক', 'খ', 'গ']);
    expect(result!.correctIndex, 2);
    expect(buildQuestionPatch(q, result!), {
      'options': ['ক', 'খ', 'গ'],
      'correct_index': 2,
    });
  });
}
