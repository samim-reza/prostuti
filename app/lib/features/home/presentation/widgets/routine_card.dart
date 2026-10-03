import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/home/presentation/widgets/home_card.dart';
import 'package:prostuti/features/study_plan/application/plan_exam.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/generating_plan_view.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_generation_ui.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_item_actions.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_item_tile.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_ui.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/weak_topic_chips.dart';

/// Today's routine: checklist with optimistic (offline-queued) check-offs,
/// weak-topic exam launcher, and the next two days. Without a plan it turns
/// into the "create my plan" call to action.
class RoutineCard extends ConsumerWidget {
  const RoutineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(todayRoutineProvider);
    final routine = value.value;
    if (routine == null) {
      if (value.hasError) {
        return HomeCard(
          title: l.homeRoutineTitle,
          icon: Icons.checklist_rounded,
          child: HomeInlineError(error: value.error!, onRetry: () => ref.invalidate(todayRoutineProvider)),
        );
      }
      return const SkeletonShimmer(child: SkeletonBox(height: 220, radius: 16));
    }
    if (!routine.hasPlan) return const _CreatePlanCard();
    final day = routine.today;
    return HomeCard(
      title: l.homeRoutineTitle,
      icon: Icons.checklist_rounded,
      trailing: day == null ? null : PlanKindBadge(kind: day.kind, dense: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (day == null) _NoRoutineToday(routine: routine) else _RoutineBody(day: day),
          if (routine.upcoming.isNotEmpty) ...[const Divider(height: Gap.xl), _UpcomingRow(days: routine.upcoming)],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => context.push(Routes.plan),
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(l.homeSeeFullPlan),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineBody extends ConsumerWidget {
  const _RoutineBody({required this.day});

  final PlanDay day;

  Future<void> _complete(BuildContext context, WidgetRef ref, PlanItem item) async {
    final l = context.l10n;
    try {
      final synced = await ref.read(todayRoutineProvider.notifier).completeItem(item);
      if (!context.mounted) return;
      final today = ref.read(todayRoutineProvider).value?.today;
      if (!synced && !ConnectivityService.instance.isOnline) {
        showInfoSnack(context, l.offlineSaved);
      } else if (today != null && today.status == PlanDayStatus.done) {
        showInfoSnack(context, l.homeRoutineAllDone);
      }
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = day.status == PlanDayStatus.done;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                day.title(bangla: context.isBn),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Gap.w8,
            Text(
              [
                '${context.n(day.doneCount)}/${context.n(day.itemCount)}',
                if (day.plannedMinutes > 0) PlanFmt.minutes(context, day.plannedMinutes),
              ].join(' · '),
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        Gap.h8,
        PlanProgressBar(value: day.progress, color: done ? AppColors.success : null),
        if (done) ...[
          Gap.h12,
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: Radii.button),
            child: Row(
              children: [
                const Icon(Icons.celebration_rounded, color: AppColors.success),
                Gap.w12,
                Expanded(child: Text(l.homeRoutineDoneBanner, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        ],
        if (day.kind == PlanDayKind.weakTopicExam && !done) ...[
          Gap.h12,
          Text(l.homeWeakDayIntro, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (day.weakTopics.isNotEmpty) ...[Gap.h8, WeakTopicChips(topics: day.weakTopics)],
          Gap.h12,
          FilledButton.icon(
            onPressed: () => startPlanExam(context, weakTopicDayLaunch(day)),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(l.homeStartWeakExam),
          ),
        ],
        if (day.kind == PlanDayKind.rest) ...[
          Gap.h12,
          Row(
            children: [
              const Icon(Icons.self_improvement_rounded, color: AppColors.success),
              Gap.w12,
              Expanded(child: Text(l.homeRestDay, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ],
        if (day.items.isNotEmpty) ...[
          Gap.h8,
          for (final item in day.items)
            PlanItemTile(
              key: ValueKey('home-${item.key}'),
              dayId: day.id,
              item: item,
              canMarkDone: true,
              onMarkDone: () => _complete(context, ref, item),
              onOpen: () => openPlanItem(context, dayId: day.id, dayKind: day.kind, item: item, unlocked: true),
            ),
        ],
      ],
    );
  }
}

class _NoRoutineToday extends StatelessWidget {
  const _NoRoutineToday({required this.routine});

  final TodayRoutine routine;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final started = routine.plan?.startDate;
    final message = started != null && started.isAfter(DateTime.now().toUtc())
        ? l.homeRoutineStartsOn(PlanFmt.date(context, started))
        : l.homeNoRoutineToday;
    return Row(
      children: [
        Icon(Icons.event_available_rounded, color: theme.colorScheme.primary),
        Gap.w12,
        Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.days});

  final List<PlanDayBrief> days;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.homeComingUp, style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
        Gap.h8,
        Row(
          children: [
            for (final (i, d) in days.take(2).indexed) ...[
              if (i > 0) Gap.w8,
              Expanded(
                child: InkWell(
                  borderRadius: Radii.button,
                  onTap: () => context.push(Routes.planDay(d.id)),
                  child: Container(
                    padding: const EdgeInsets.all(Gap.sm + 2),
                    decoration: BoxDecoration(
                      borderRadius: Radii.button,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(d.kind.icon, size: 20, color: d.kind.color(scheme)),
                        Gap.w8,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i == 0 ? l.homeTomorrow : PlanFmt.weekdayShort(context, d.date),
                                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              Text(
                                d.title(bangla: context.isBn),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CreatePlanCard extends ConsumerWidget {
  const _CreatePlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final generating = ref.watch(planGenerationProvider.select((s) => s.running));
    return HomeCard(
      child: generating
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: Gap.md),
              child: GeneratingPlanView(compact: true),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(Gap.md),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
                      ),
                      child: Icon(Icons.auto_awesome_rounded, color: scheme.onPrimary),
                    ),
                    Gap.w12,
                    Expanded(child: Text(l.homeCreatePlanTitle, style: theme.textTheme.titleMedium)),
                  ],
                ),
                Gap.h12,
                Text(l.homeCreatePlanBody, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                Gap.h16,
                FilledButton.icon(
                  onPressed: () {
                    final access = ref.read(featureAccessProvider).value;
                    if (access != null && access[Features.aiStudyPlan] == false) {
                      showLockedSheet(context);
                      return;
                    }
                    unawaited(generatePlanWithFeedback(context, ref));
                  },
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(l.homeCreatePlanCta),
                ),
              ],
            ),
    );
  }
}
