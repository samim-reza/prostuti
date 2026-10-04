import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/home/application/home_helpers.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/data/readiness_models.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_ui.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/progress_charts.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/readiness_gauge.dart';

/// How ready the user is for the final exam: readiness gauge, estimated
/// score, per-subject mastery (bars + radar), history and levels.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final readiness = ref.watch(readinessProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.studyPlanProgressTitle),
        actions: [
          IconButton(
            tooltip: l.studyPlanExamHistory,
            onPressed: () => context.push(Routes.examHistory),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await Future.wait([
              ref.read(readinessProvider.notifier).refresh(),
              ref.read(currentProfileProvider.notifier).reload(),
            ]);
          } on Object catch (e) {
            if (context.mounted) showErrorSnack(context, e);
          }
        },
        child: AsyncView<Readiness>(
          value: readiness,
          loading: const _ProgressSkeleton(),
          onRetry: () => ref.invalidate(readinessProvider),
          data: (r) => _ProgressContent(readiness: r),
        ),
      ),
    );
  }
}

class _ProgressContent extends StatelessWidget {
  const _ProgressContent({required this.readiness});

  final Readiness readiness;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final subjects = readiness.subjects;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
      children: [
        _HeroCard(readiness: readiness),
        PlanSectionHeader(title: l.studyPlanStreakTitle, icon: Icons.local_fire_department_rounded),
        const _StreakRow(),
        if (subjects.isNotEmpty) ...[
          PlanSectionHeader(title: l.studyPlanSubjectMastery, icon: Icons.bar_chart_rounded),
          _MasteryBars(subjects: subjects),
        ],
        if (subjects.length >= 3) ...[
          PlanSectionHeader(title: l.studyPlanRadarTitle, icon: Icons.hub_rounded),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.sm),
              child: MasteryRadarChart(subjects: subjects),
            ),
          ),
        ],
        PlanSectionHeader(title: l.studyPlanHistoryTitle, icon: Icons.show_chart_rounded),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: readiness.history.length >= 2
                ? ReadinessHistoryChart(history: readiness.history)
                : EmptyView(compact: true, icon: Icons.show_chart_rounded, title: l.studyPlanHistoryEmpty),
          ),
        ),
        PlanSectionHeader(title: l.studyPlanLevelsTitle, icon: Icons.stairs_rounded),
        _LevelsCard(readiness: readiness),
        Gap.h24,
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.examHistory),
          icon: const Icon(Icons.history_rounded),
          label: Text(l.studyPlanExamHistory),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.readiness});

  final Readiness readiness;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final delta = readiness.weeklyDelta;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.lg),
        child: Column(
          children: [
            ReadinessGauge(value: readiness.readiness, caption: l.studyPlanReadyForFinal),
            if (delta != null && delta != 0) ...[
              Gap.h8,
              PlanPill(
                icon: delta > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                color: delta > 0 ? AppColors.success : scheme.error,
                label: l.studyPlanWeeklyDelta('${delta > 0 ? '+' : '−'}${context.n(delta.abs())}'),
              ),
            ],
            Gap.h16,
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.emoji_events_rounded,
                    value: '${context.n(readiness.estimatedScore)}/${context.n(readiness.maxScore)}',
                    label: l.studyPlanEstimatedScore,
                  ),
                ),
                Gap.w12,
                Expanded(
                  child: _StatTile(
                    icon: Icons.donut_large_rounded,
                    value: '${context.n(readiness.coverage)}%',
                    label: l.studyPlanCoverage,
                  ),
                ),
              ],
            ),
            Gap.h12,
            Text(
              l.studyPlanReadinessExplain,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.07), borderRadius: Radii.button),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          Gap.w8,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakRow extends ConsumerWidget {
  const _StreakRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final profile = ref.watch(currentProfileProvider).value;
    final streak = effectiveStreak(
      count: profile?.streakCount ?? 0,
      lastActive: profile?.lastActiveDate,
      bdToday: BdTime.today(),
    );
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.local_fire_department_rounded,
            value: l.studyPlanDaysCount(streak, context.n(streak)),
            label: l.studyPlanCurrentStreak,
          ),
        ),
        Gap.w12,
        Expanded(
          child: _StatTile(
            icon: Icons.military_tech_rounded,
            value: l.studyPlanDaysCount(profile?.longestStreak ?? 0, context.n(profile?.longestStreak ?? 0)),
            label: l.studyPlanLongestStreak,
          ),
        ),
      ],
    );
  }
}

class _MasteryBars extends StatelessWidget {
  const _MasteryBars({required this.subjects});

  final List<SubjectReadiness> subjects;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          children: [
            for (final (i, s) in subjects.indexed) ...[
              if (i > 0) Gap.h16,
              Semantics(
                label: '${context.isBn ? s.nameBn : s.nameEn}: ${context.n(s.mastery)}%',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.fromHex(s.colorHex, fallback: scheme.primary),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Gap.w8,
                        Expanded(
                          child: Text(
                            context.isBn ? s.nameBn : s.nameEn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '${context.n(s.mastery)}%',
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Gap.h4,
                    PlanProgressBar(
                      value: s.mastery / 100,
                      color: AppColors.fromHex(s.colorHex, fallback: scheme.primary),
                    ),
                    Gap.h4,
                    Text(
                      l.studyPlanSubjectMeta(context.n(s.marks), context.n(s.coverage)),
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LevelsCard extends StatelessWidget {
  const _LevelsCard({required this.readiness});

  final Readiness readiness;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    if (readiness.levels.isEmpty) {
      return Card(
        // No level test yet (it can be skipped during setup): offer it here.
        child: EmptyView(
          compact: true,
          icon: Icons.stairs_rounded,
          title: l.studyPlanLevelsEmpty,
          actionLabel: l.homeSetupPlacement,
          action: () => context.push(Routes.later(Routes.onboardingPlacement)),
        ),
      );
    }
    final names = {for (final s in readiness.subjects) s.subjectId: context.isBn ? s.nameBn : s.nameEn};
    return Card(
      child: Column(
        children: [
          for (final lv in readiness.levels)
            ListTile(
              leading: Icon(lv.level.icon, color: lv.level.color),
              title: Text(names[lv.subjectId] ?? '#${context.n(lv.subjectId)}', style: theme.textTheme.bodyMedium),
              subtitle: Text(l.studyPlanLevelScore(context.n((lv.scorePct * 100).round()))),
              trailing: PlanPill(label: lv.level.label(context), color: lv.level.color),
            ),
        ],
      ),
    );
  }
}

class _ProgressSkeleton extends StatelessWidget {
  const _ProgressSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          const SkeletonBox(height: 320, radius: 16),
          Gap.h16,
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 64, radius: 12)),
              SizedBox(width: Gap.md),
              Expanded(child: SkeletonBox(height: 64, radius: 12)),
            ],
          ),
          Gap.h16,
          for (var i = 0; i < 5; i++) ...[const SkeletonBox(height: 36), Gap.h12],
        ],
      ),
    );
  }
}
