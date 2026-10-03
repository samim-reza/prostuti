import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/home/application/home_helpers.dart';
import 'package:prostuti/features/home/application/home_providers.dart';
import 'package:prostuti/features/home/presentation/widgets/home_card.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_ui.dart';

// -----------------------------------------------------------------------------
// Trial banner
// -----------------------------------------------------------------------------
class TrialBanner extends ConsumerWidget {
  const TrialBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trial = ref.watch(trialStatusProvider.select((s) => s.value?.trial));
    final now = DateTime.now();
    if (trial == null || !trial.isActive(now)) return const SizedBox.shrink();
    final l = context.l10n;
    final days = trial.daysLeft(now);
    final theme = Theme.of(context);
    const ink = Color(0xFF3D2A00);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: Radii.card,
          onTap: () => context.push(Routes.addons),
          child: Ink(
            decoration: const BoxDecoration(
              borderRadius: Radii.card,
              gradient: LinearGradient(colors: [Color(0xFFFFD36B), AppColors.gold]),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded, color: ink),
                Gap.w12,
                Expanded(
                  child: Text(
                    days <= 1 ? l.homeTrialLastDay : l.homeTrialDaysLeft(days, context.n(days)),
                    style: theme.textTheme.titleSmall?.copyWith(color: ink),
                  ),
                ),
                Text(l.homeTrialCta, style: theme.textTheme.labelLarge?.copyWith(color: ink)),
                const Icon(Icons.chevron_right_rounded, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Exam countdown
// -----------------------------------------------------------------------------
class CountdownCard extends ConsumerWidget {
  const CountdownCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(targetScheduleProvider);
    if (schedule == null) {
      final loading = ref.watch(examSchedulesProvider.select((s) => s.isLoading && !s.hasValue));
      return loading ? const SkeletonShimmer(child: SkeletonBox(height: 132, radius: 16)) : const SizedBox.shrink();
    }
    return _CountdownBody(schedule: schedule);
  }
}

class _CountdownBody extends StatelessWidget {
  const _CountdownBody({required this.schedule});

  final ExamSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = scheme.onPrimary;
    final days = daysUntil(schedule.expectedDate, BdTime.today());
    final date = DateTime.utc(schedule.expectedDate.year, schedule.expectedDate.month, schedule.expectedDate.day);
    return Semantics(
      label: l.homeCountdownSemantics(schedule.title(context), context.n(days)),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Gap.lg),
        decoration: BoxDecoration(
          borderRadius: Radii.card,
          gradient: LinearGradient(
            colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.3)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: scheme.primary.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, size: 16, color: on.withValues(alpha: 0.85)),
                      Gap.w4,
                      Text(
                        l.homeCountdownLabel,
                        style: theme.textTheme.labelMedium?.copyWith(color: on.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                  Gap.h4,
                  Text(
                    schedule.title(context),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(color: on),
                  ),
                  Gap.h8,
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_rounded, size: 15, color: on.withValues(alpha: 0.9)),
                          Gap.w4,
                          Text(
                            Fmt.date(date, bangla: context.isBn),
                            style: theme.textTheme.bodySmall?.copyWith(color: on.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                      if (!schedule.isConfirmed)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 1),
                          decoration: BoxDecoration(color: on.withValues(alpha: 0.18), borderRadius: Radii.chip),
                          child: Text(
                            l.homeTentativeDate,
                            style: theme.textTheme.labelSmall?.copyWith(color: on, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Gap.w12,
            Column(
              children: [
                Text(
                  context.n(days),
                  style: theme.textTheme.displaySmall?.copyWith(color: on, fontWeight: FontWeight.w800, height: 1.05),
                ),
                Text(
                  days == 0 ? l.homeExamToday : l.homeDaysLeftShort,
                  style: theme.textTheme.labelMedium?.copyWith(color: on.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Readiness
// -----------------------------------------------------------------------------
class ReadinessCard extends ConsumerWidget {
  const ReadinessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = ref.watch(readinessProvider);
    final r = value.value;
    if (r == null) {
      if (value.hasError) {
        return HomeCard(
          child: HomeInlineError(error: value.error!, onRetry: () => ref.invalidate(readinessProvider)),
        );
      }
      return const SkeletonShimmer(child: SkeletonBox(height: 104, radius: 16));
    }
    return HomeCard(
      onTap: () => context.push(Routes.progress),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: r.readiness / 100),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => CircularProgressIndicator(
                    value: v,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  ),
                ),
                Center(
                  child: Text(
                    '${context.n(r.readiness)}%',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Gap.w16,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.homeReadinessTitle(context.n(r.readiness)), style: theme.textTheme.titleSmall),
                Gap.h8,
                PlanProgressBar(value: r.readiness / 100),
                Gap.h8,
                Text(
                  l.homeEstimatedScore(context.n(r.estimatedScore), context.n(r.maxScore)),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Today's notes
// -----------------------------------------------------------------------------
class NotesCard extends ConsumerWidget {
  const NotesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = ref.watch(notesDigestProvider);
    final digest = value.value;
    Widget body;
    if (digest == null) {
      body = value.hasError
          ? HomeInlineError(error: value.error!, onRetry: () => ref.invalidate(notesDigestProvider))
          : const SkeletonShimmer(
              child: Column(children: [SkeletonBox(), Gap.h8, SkeletonBox(), Gap.h8, SkeletonBox(width: 180)]),
            );
    } else if (digest.count == 0) {
      final early = BdTime.now().hour < 6;
      body = Row(
        children: [
          const Icon(Icons.wb_twilight_rounded, color: AppColors.gold),
          Gap.w12,
          Expanded(
            child: Text(
              early ? l.homeNotesComingAt6 : l.homeNotesComingSoon,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in digest.top)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                    ),
                  ),
                  Gap.w12,
                  Expanded(
                    child: Text(
                      n.title(bangla: context.isBn),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          Text(l.homeNotesReadAll, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
        ],
      );
    }
    return HomeCard(
      title: l.homeNotesTitle,
      icon: Icons.newspaper_rounded,
      trailing: (digest?.count ?? 0) > 0
          ? PlanPill(label: l.homeNotesCount(digest!.count, context.n(digest.count)), color: scheme.primary)
          : null,
      onTap: () => context.push(Routes.notes),
      child: body,
    );
  }
}

// -----------------------------------------------------------------------------
// Daily exam
// -----------------------------------------------------------------------------
class DailyExamCard extends ConsumerWidget {
  const DailyExamCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final exam = ref.watch(notesDigestProvider.select((v) => v.value?.dailyExam));
    final subtitle = exam == null
        ? l.homeDailyExamPending
        : [
            l.homeQuestionCount(exam.questionCount, context.n(exam.questionCount)),
            if (exam.durationMinutes > 0) Fmt.minutes(exam.durationMinutes, bangla: context.isBn),
            l.homeNegativeMarking,
          ].join(' · ');
    return HomeCard(
      onTap: () => context.push(Routes.dailyExam),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: scheme.secondary.withValues(alpha: 0.12), borderRadius: Radii.button),
            child: Icon(Icons.timer_rounded, color: scheme.secondary),
          ),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam?.title(bangla: context.isBn) ?? l.homeDailyExamTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Gap.w8,
          FilledButton.tonal(
            onPressed: () => context.push(Routes.dailyExam),
            style: FilledButton.styleFrom(minimumSize: const Size(72, 44)),
            child: Text(exam == null ? l.homeDailyExamOpen : l.homeDailyExamStart),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Quick actions
// -----------------------------------------------------------------------------
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final actions = [
      (Icons.assignment_rounded, l.homeQuickModelTest, Routes.modelTests, AppColors.warning),
      (Icons.edit_note_rounded, l.homeQuickPractice, Routes.questionBank, AppColors.info),
      (Icons.error_outline_rounded, l.homeQuickWrongAnswers, Routes.wrongAnswers, AppColors.danger),
      (Icons.leaderboard_rounded, l.homeQuickLeaderboard, Routes.leaderboard, AppColors.success),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, a) in actions.indexed) ...[
          if (i > 0) Gap.w8,
          Expanded(
            child: _QuickAction(icon: a.$1, label: a.$2, route: a.$3, color: a.$4),
          ),
        ],
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.route, required this.color});

  final IconData icon;
  final String label;
  final String route;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: Radii.card,
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md, horizontal: Gap.xs),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(Gap.sm + 2),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 22),
              ),
              Gap.h8,
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
