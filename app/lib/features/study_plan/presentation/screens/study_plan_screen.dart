import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/study_plan/application/daily_advice_providers.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/ai_advice_card.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/generating_plan_view.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_generation_ui.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_overview_widgets.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_sheets.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_ui.dart';

/// The AI study plan — shown only partially: aggregates for the whole plan,
/// details for the last week and the next two days, the rest stays locked.
class StudyPlanScreen extends ConsumerWidget {
  const StudyPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final hasPlan = ref.watch(planOverviewProvider.select((v) => v.value?.hasPlan ?? false));
    final unlocked = ref.watch(hasFeatureProvider(Features.aiStudyPlan));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.studyPlanTitle),
        actions: [
          IconButton(
            tooltip: l.studyPlanProgressTooltip,
            onPressed: () => context.push(Routes.progress),
            icon: const Icon(Icons.insights_rounded),
          ),
          if (hasPlan && unlocked) const _PlanMenu(),
        ],
      ),
      body: EntitlementGate(
        feature: Features.aiStudyPlan,
        lockedTitle: l.studyPlanLockedFeatureTitle,
        lockedMessage: l.studyPlanLockedFeatureBody,
        child: const _PlanBody(),
      ),
    );
  }
}

class _PlanMenu extends ConsumerWidget {
  const _PlanMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l.studyPlanMoreActions,
      icon: const Icon(Icons.tune_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'replan':
            await showReplanSheet(context, ref);
          case 'minutes':
            final current = ref.read(currentProfileProvider).value?.dailyStudyMinutes ?? 120;
            await showDailyMinutesSheet(context, ref, current: current);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'replan',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_fix_high_rounded),
            title: Text(l.studyPlanReplan),
          ),
        ),
        PopupMenuItem(
          value: 'minutes',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined),
            title: Text(l.studyPlanChangeMinutes),
          ),
        ),
      ],
    );
  }
}

class _PlanBody extends ConsumerWidget {
  const _PlanBody();

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      // Advice: today's stored copy is re-read (quiet); the card's own button
      // asks for a re-evaluation.
      await Future.wait([refreshPlanData(ref.read), refreshDailyAdvice(ref.read, regenerate: false)]);
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final generating = ref.watch(planGenerationProvider.select((s) => s.running));
    if (generating) return const Center(child: GeneratingPlanView());
    final overview = ref.watch(planOverviewProvider);
    return RefreshIndicator(
      onRefresh: () => _refresh(context, ref),
      child: AsyncView<PlanOverview>(
        value: overview,
        loading: const _PlanSkeleton(),
        onRetry: () => ref.invalidate(planOverviewProvider),
        // Generation runs from here: this widget stays mounted while the
        // progress view replaces the empty state, so its result is reported.
        data: (o) => o.hasPlan
            ? _PlanContent(overview: o)
            : _NoPlanView(onCreate: () => unawaited(generatePlanWithFeedback(context, ref))),
      ),
    );
  }
}

class _PlanContent extends StatelessWidget {
  const _PlanContent({required this.overview});

  final PlanOverview overview;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final summary = overview.summary;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
      children: [
        PlanHeaderCard(overview: overview),
        Gap.h12,
        PlanStatsRow(overview: overview),
        _AdviceSection(planTips: overview.aiTips),
        if (overview.kinds.isNotEmpty) ...[
          PlanSectionHeader(title: l.studyPlanComposition, icon: Icons.donut_small_rounded),
          PlanCompositionRow(kinds: overview.kinds),
        ],
        if (summary.phases.isNotEmpty) ...[
          PlanSectionHeader(title: l.studyPlanPhases, icon: Icons.timeline_rounded),
          PlanPhasesTimeline(phases: summary.phases),
        ],
        if (summary.milestones.isNotEmpty) ...[
          PlanSectionHeader(title: l.studyPlanMilestones, icon: Icons.flag_rounded),
          PlanMilestonesCard(milestones: summary.milestones),
        ],
        PlanSectionHeader(title: l.studyPlanRecentDays, icon: Icons.view_agenda_rounded),
        if (overview.recent.isEmpty)
          EmptyView(compact: true, icon: Icons.event_busy_rounded, title: l.studyPlanNoVisibleDays)
        else
          for (final day in overview.recent)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: PlanDayTimelineTile(day: day),
            ),
        if (overview.lockedDays > 0) ...[
          PlanSectionHeader(title: l.studyPlanUpcoming, icon: Icons.lock_clock_rounded),
          LockedDaysSection(lockedDays: overview.lockedDays),
        ],
      ],
    );
  }
}

/// Today's AI advice (fresh every day, from the learner's data). The tips
/// written when the plan was created are shown only if no advice is
/// available (function unreachable, today's allowance used up…).
class _AdviceSection extends ConsumerWidget {
  const _AdviceSection({required this.planTips});

  final List<String> planTips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unavailable = ref.watch(
      dailyAdviceProvider.select((a) => (a.hasError && !a.hasValue) || (a.value?.isEmpty ?? false)),
    );
    if (!unavailable) {
      return const Padding(
        padding: EdgeInsets.only(top: Gap.md),
        child: AiAdviceCard(),
      );
    }
    if (planTips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlanSectionHeader(title: context.l10n.studyPlanAiTips, icon: Icons.auto_awesome_rounded),
        PlanTipsCard(tips: planTips),
      ],
    );
  }
}

class _NoPlanView extends StatelessWidget {
  const _NoPlanView({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Gap.h32,
        EmptyView(
          icon: Icons.auto_awesome_rounded,
          title: l.studyPlanNoPlanTitle,
          message: l.studyPlanNoPlanBody,
          actionLabel: l.studyPlanCreate,
          action: onCreate,
        ),
      ],
    );
  }
}

class _PlanSkeleton extends StatelessWidget {
  const _PlanSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          const SkeletonBox(height: 128, radius: 16),
          Gap.h12,
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) Gap.w8,
                const Expanded(child: SkeletonBox(height: 76, radius: 12)),
              ],
            ],
          ),
          Gap.h24,
          const SkeletonBox(width: 140, height: 16),
          Gap.h12,
          for (var i = 0; i < 4; i++) ...[const SkeletonBox(height: 76, radius: 16), Gap.h8],
        ],
      ),
    );
  }
}
