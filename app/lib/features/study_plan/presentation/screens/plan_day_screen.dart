import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/study_plan/application/plan_exam.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_item_actions.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_item_tile.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_ui.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/weak_topic_chips.dart';

/// One day of the routine. Days beyond today+2 are hidden by RLS, so a
/// missing row is shown as "locked".
class PlanDayScreen extends ConsumerWidget {
  const PlanDayScreen({required this.dayId, super.key});
  final int dayId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(planDayProvider(dayId));
    final day = value.value;
    return Scaffold(
      appBar: AppBar(title: Text(day == null ? l.studyPlanDayTitle : PlanFmt.date(context, day.date))),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(planDayProvider(dayId).notifier).refresh();
          } on Object catch (e) {
            if (context.mounted) showErrorSnack(context, e);
          }
        },
        child: AsyncView<PlanDay?>(
          value: value,
          loading: const SkeletonList(itemCount: 5),
          onRetry: () => ref.invalidate(planDayProvider(dayId)),
          data: (d) => d == null ? const _LockedDayView() : _DayContent(day: d),
        ),
      ),
    );
  }
}

class _DayContent extends ConsumerWidget {
  const _DayContent({required this.day});

  final PlanDay day;

  Future<void> _complete(BuildContext context, WidgetRef ref, PlanItem item) async {
    try {
      final synced = await ref.read(planDayProvider(day.id).notifier).completeItem(item);
      if (!synced && context.mounted && !ConnectivityService.instance.isOnline) {
        showInfoSnack(context, context.l10n.offlineSaved);
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
    final today = BdTime.today();
    final unlocked = day.isUnlockedOn(today);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
      children: [
        _DayHeader(day: day, isToday: day.date == today),
        if (!unlocked) ...[
          Gap.h12,
          _Banner(icon: Icons.schedule_rounded, color: scheme.primary, text: l.studyPlanFutureDayNote),
        ],
        if (day.kind == PlanDayKind.weakTopicExam) ...[
          PlanSectionHeader(title: l.studyPlanWeakTopics, icon: Icons.track_changes_rounded),
          if (day.weakTopics.isNotEmpty) ...[WeakTopicChips(topics: day.weakTopics), Gap.h12],
          Text(l.studyPlanWeakDayBody, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          if (unlocked) ...[
            Gap.h12,
            FilledButton.icon(
              onPressed: () => startPlanExam(context, weakTopicDayLaunch(day)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l.studyPlanStartWeakExam),
            ),
          ],
        ],
        if (day.kind == PlanDayKind.rest) ...[
          Gap.h12,
          _Banner(icon: Icons.self_improvement_rounded, color: AppColors.success, text: l.studyPlanRestDayBody),
        ],
        PlanSectionHeader(
          title: l.studyPlanChecklist,
          icon: Icons.checklist_rounded,
          trailing: Text(
            '${context.n(day.doneCount)}/${context.n(day.itemCount)}',
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
        ),
        if (day.items.isEmpty)
          EmptyView(compact: true, icon: Icons.playlist_remove_rounded, title: l.studyPlanNoItems)
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.sm),
              child: Column(
                children: [
                  for (final item in day.items)
                    PlanItemTile(
                      key: ValueKey(item.key),
                      dayId: day.id,
                      item: item,
                      canMarkDone: unlocked,
                      onMarkDone: () => _complete(context, ref, item),
                      onOpen: () =>
                          openPlanItem(context, dayId: day.id, dayKind: day.kind, item: item, unlocked: unlocked),
                    ),
                ],
              ),
            ),
          ),
        if (unlocked && day.items.any((i) => !i.done && i.canComplete)) ...[
          Gap.h12,
          Text(
            l.studyPlanTickHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isToday});

  final PlanDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = day.kind.color(scheme);
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PlanKindBadge(kind: day.kind),
                const Spacer(),
                if (isToday) PlanPill(label: l.studyPlanToday, color: scheme.primary, icon: Icons.today_rounded),
              ],
            ),
            Gap.h12,
            Text(day.title(bangla: context.isBn), style: theme.textTheme.titleLarge),
            Gap.h4,
            Text(
              '${PlanFmt.weekdayShort(context, day.date)}, ${PlanFmt.date(context, day.date)}'
              '${day.dayIndex > 0 ? ' · ${l.studyPlanDayNumber(context.n(day.dayIndex))}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Gap.h16,
            Row(
              children: [
                _Metric(
                  icon: Icons.timer_outlined,
                  value: PlanFmt.minutes(context, day.plannedMinutes),
                  label: l.studyPlanPlannedTime,
                ),
                _Metric(
                  icon: Icons.task_alt_rounded,
                  value: '${context.n(day.doneCount)}/${context.n(day.itemCount)}',
                  label: l.studyPlanTasks,
                ),
                _Metric(icon: day.status.icon, value: day.status.label(context), label: l.studyPlanStatus),
              ],
            ),
            Gap.h12,
            PlanProgressBar(value: day.progress, color: color),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          Gap.h4,
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: Radii.button),
      child: Row(
        children: [
          Icon(icon, color: color),
          Gap.w12,
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _LockedDayView extends StatelessWidget {
  const _LockedDayView();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Gap.h32,
        EmptyView(
          icon: Icons.lock_clock_rounded,
          title: l.studyPlanDayLockedTitle,
          message: l.studyPlanDayLockedBody,
          actionLabel: l.studyPlanBackToPlan,
          action: () => context.canPop() ? context.pop() : context.go(Routes.plan),
        ),
      ],
    );
  }
}
