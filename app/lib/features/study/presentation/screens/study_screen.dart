import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/presentation/widgets/feature_tile.dart';
import 'package:prostuti/features/home/application/home_providers.dart';
import 'package:prostuti/features/home/presentation/widgets/home_cards.dart';
import 'package:prostuti/features/home/presentation/widgets/routine_card.dart';
import 'package:prostuti/features/home/presentation/widgets/setup_card.dart';
import 'package:prostuti/features/question_bank/presentation/screens/question_bank_screen.dart';
import 'package:prostuti/features/study/presentation/widgets/study_widgets.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/ai_advice_card.dart';

/// Study tab: unfinished setup, exam countdown, readiness, today's routine
/// and the day's AI advice, every study tool and quick subject practice. (Today's notes are
/// on Home.)
class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key});

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final results = await Future.wait([
      refreshHome(ref.read),
      QuestionBankScreen.refreshSubjects(ref).then((_) => null),
    ]);
    final error = results.first;
    if (error != null && context.mounted && ConnectivityService.instance.isOnline) showErrorSnack(context, error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    registerExamFailureMessages();
    final l = context.l10n;
    final tools = <StudyTool>[
      StudyTool(Icons.event_note_rounded, const Color(0xFF7A4BD6), l.studyHubPlan, l.studyHubPlanBody, Routes.plan),
      StudyTool(
        Icons.library_books_rounded,
        AppColors.brand,
        l.studyHubQuestionBank,
        l.studyHubQuestionBankBody,
        Routes.questionBank,
      ),
      StudyTool(
        Icons.assignment_rounded,
        const Color(0xFFD9480F),
        l.examCardModelTitle,
        l.studyHubModelTestsBody,
        Routes.modelTests,
      ),
      StudyTool(
        Icons.assignment_late_rounded,
        AppColors.danger,
        l.studyHubWrong,
        l.studyHubWrongBody,
        Routes.wrongAnswers,
      ),
      StudyTool(
        Icons.bookmarks_rounded,
        AppColors.info,
        l.studyHubBookmarks,
        l.studyHubBookmarksBody,
        Routes.bookmarks,
      ),
      StudyTool(
        Icons.insights_rounded,
        const Color(0xFF0E7C66),
        l.studyHubProgress,
        l.studyHubProgressBody,
        Routes.progress,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l.studyHubTitle),
        actions: [
          IconButton(
            tooltip: l.studyHubBookmarks,
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => context.push(Routes.bookmarks),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context, ref),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
              sliver: SliverList.list(
                children: [
                  Text(l.studyHubGreeting, style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    l.studyHubGreetingBody,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  Gap.h16,
                  const SetupCard(),
                  const CountdownCard(),
                  Gap.h12,
                  const ReadinessCard(),
                  Gap.h12,
                  const RoutineCard(),
                  Gap.h12,
                  const AiAdviceCard(),
                  SectionHeader(title: l.studyHubTools),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: Gap.md,
                  crossAxisSpacing: Gap.md,
                  mainAxisExtent: 70 + 78 * MediaQuery.textScalerOf(context).scale(1),
                ),
                itemCount: tools.length,
                itemBuilder: (context, i) {
                  final t = tools[i];
                  return FeatureTile(
                    icon: t.icon,
                    color: t.color,
                    title: t.title,
                    subtitle: t.subtitle,
                    onTap: () => context.push(t.route),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: l.studyHubSubjects,
                      action: l.seeAll,
                      onAction: () => context.push(Routes.questionBank),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.md),
                      child: Text(
                        l.studyHubSubjectsHint,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl), sliver: SubjectQuickGrid()),
          ],
        ),
      ),
    );
  }
}

/// One entry of the study tools grid.
@immutable
class StudyTool {
  const StudyTool(this.icon, this.color, this.title, this.subtitle, this.route);
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;
}
