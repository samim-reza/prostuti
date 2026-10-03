import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_ui.dart';

/// Gradient header: completion ring + exam date + days left + budget.
class PlanHeaderCard extends StatelessWidget {
  const PlanHeaderCard({required this.overview, super.key});

  final PlanOverview overview;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = scheme.onPrimary;
    final exam = overview.examDate;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        borderRadius: Radii.card,
        gradient: LinearGradient(
          colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.28)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 96,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: overview.completion),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => CircularProgressIndicator(
                    value: v,
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    color: on,
                    backgroundColor: on.withValues(alpha: 0.2),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${context.n(overview.doneDays)}/${context.n(overview.totalDays)}',
                        style: theme.textTheme.titleMedium?.copyWith(color: on, fontWeight: FontWeight.w800),
                      ),
                      Text(l.studyPlanDaysDone, style: theme.textTheme.labelSmall?.copyWith(color: on)),
                    ],
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
                Text(
                  l.studyPlanExamOn,
                  style: theme.textTheme.labelMedium?.copyWith(color: on.withValues(alpha: 0.85)),
                ),
                Text(
                  exam == null ? '—' : PlanFmt.date(context, exam),
                  style: theme.textTheme.titleLarge?.copyWith(color: on),
                ),
                Gap.h4,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xxs),
                  decoration: BoxDecoration(color: on.withValues(alpha: 0.16), borderRadius: Radii.chip),
                  child: Text(
                    l.studyPlanDaysLeft(overview.daysLeft, context.n(overview.daysLeft)),
                    style: theme.textTheme.labelMedium?.copyWith(color: on, fontWeight: FontWeight.w700),
                  ),
                ),
                Gap.h8,
                Text(
                  [
                    l.studyPlanDailyBudget(PlanFmt.minutes(context, overview.dailyMinutes)),
                    if (overview.version > 1) l.studyPlanVersion(context.n(overview.version)),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: on.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Done / partial / missed / locked counts.
class PlanStatsRow extends StatelessWidget {
  const PlanStatsRow({required this.overview, super.key});

  final PlanOverview overview;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final stats = [
      (Icons.check_circle_rounded, overview.doneDays, l.studyPlanStatDone, AppColors.success),
      (Icons.timelapse_rounded, overview.partialDays, l.studyPlanStatPartial, AppColors.warning),
      (Icons.cancel_rounded, overview.missedDays, l.studyPlanStatMissed, scheme.error),
      (Icons.lock_rounded, overview.lockedDays, l.studyPlanStatLocked, scheme.outline),
    ];
    return Row(
      children: [
        for (final (i, s) in stats.indexed) ...[
          if (i > 0) Gap.w8,
          Expanded(
            child: Semantics(
              label: '${s.$3}: ${context.n(s.$2)}',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: Gap.md, horizontal: Gap.xs),
                decoration: BoxDecoration(color: s.$4.withValues(alpha: 0.1), borderRadius: Radii.button),
                child: Column(
                  children: [
                    Icon(s.$1, color: s.$4, size: 20),
                    Gap.h4,
                    Text(
                      context.n(s.$2),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      s.$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// How the whole plan is composed (counts per day kind) — aggregates only.
class PlanCompositionRow extends StatelessWidget {
  const PlanCompositionRow({required this.kinds, super.key});

  final Map<String, int> kinds;

  @override
  Widget build(BuildContext context) {
    if (kinds.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final entries = kinds.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        for (final e in entries)
          PlanPill(
            icon: PlanDayKind.parse(e.key).icon,
            color: PlanDayKind.parse(e.key).color(scheme),
            label: '${PlanDayKind.parse(e.key).label(context)} · ${context.n(e.value)}',
          ),
      ],
    );
  }
}

/// Vertical timeline of the plan's phases; the current one is highlighted.
class PlanPhasesTimeline extends StatelessWidget {
  const PlanPhasesTimeline({required this.phases, super.key});

  final List<PlanPhase> phases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = BdTime.today();
    final bangla = context.isBn;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        child: Column(
          children: [
            for (final (i, p) in phases.indexed)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Column(
                        children: [
                          _PhaseDot(current: p.isCurrent(today), past: p.isPast(today)),
                          if (i < phases.length - 1)
                            Expanded(
                              child: Container(
                                width: 2,
                                margin: const EdgeInsets.symmetric(vertical: Gap.xs),
                                color: p.isPast(today) ? scheme.primary : scheme.outlineVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Gap.w8,
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: i < phases.length - 1 ? Gap.lg : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    p.name(bangla: bangla),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: p.isCurrent(today) ? scheme.primary : null,
                                    ),
                                  ),
                                ),
                                if (p.isCurrent(today)) ...[
                                  Gap.w8,
                                  PlanPill(label: context.l10n.studyPlanPhaseNow, color: scheme.primary, dense: true),
                                ],
                              ],
                            ),
                            if (p.startDate != null && p.endDate != null)
                              Text(
                                '${PlanFmt.date(context, p.startDate!, withYear: false)} – '
                                '${PlanFmt.date(context, p.endDate!, withYear: false)}',
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            if (p.focus(bangla: bangla) != null) ...[
                              Gap.h4,
                              Text(p.focus(bangla: bangla)!, style: theme.textTheme.bodyMedium),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhaseDot extends StatelessWidget {
  const _PhaseDot({required this.current, required this.past});

  final bool current;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = current || past ? scheme.primary : scheme.outlineVariant;
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: past ? color : scheme.surface,
        border: Border.all(color: color, width: current ? 6 : 2),
      ),
      child: past ? Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary) : null,
    );
  }
}

class PlanMilestonesCard extends StatelessWidget {
  const PlanMilestonesCard({required this.milestones, super.key});

  final List<PlanMilestone> milestones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = BdTime.today();
    return Card(
      child: Column(
        children: [
          for (final m in milestones)
            ListTile(
              leading: Icon(
                m.date != null && m.date!.isBefore(today) ? Icons.flag_rounded : Icons.outlined_flag_rounded,
                color: AppColors.gold,
              ),
              title: Text(m.title(bangla: context.isBn)),
              subtitle: m.date == null ? null : Text(PlanFmt.date(context, m.date!)),
              subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class PlanTipsCard extends StatelessWidget {
  const PlanTipsCard({required this.tips, super.key});

  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          children: [
            for (final (i, t) in tips.indexed) ...[
              if (i > 0) const Divider(height: Gap.xl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_rounded, color: AppColors.gold, size: 20),
                  Gap.w12,
                  Expanded(child: Text(t, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A visible day in the timeline (last 7 days + the next 2).
class PlanDayTimelineTile extends StatelessWidget {
  const PlanDayTimelineTile({required this.day, super.key});

  final PlanDayBrief day;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = BdTime.today();
    final isToday = day.date == today;
    final isFuture = day.date.isAfter(today);
    final kindColor = day.kind.color(scheme);
    final statusText = isFuture ? l.studyPlanStatusUpcoming : day.status.label(context);
    final statusColor = isFuture ? scheme.primary : day.status.color(scheme);

    return Card(
      color: isToday ? scheme.primary.withValues(alpha: 0.06) : null,
      shape: isToday
          ? RoundedRectangleBorder(
              borderRadius: Radii.card,
              side: BorderSide(color: scheme.primary, width: 1.4),
            )
          : null,
      child: InkWell(
        borderRadius: Radii.card,
        onTap: () => context.push(Routes.planDay(day.id)),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                decoration: BoxDecoration(color: kindColor.withValues(alpha: 0.1), borderRadius: Radii.button),
                child: Column(
                  children: [
                    Text(
                      isToday ? l.studyPlanToday : PlanFmt.weekdayShort(context, day.date),
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(color: kindColor, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      PlanFmt.dayNumber(context, day.date),
                      style: theme.textTheme.titleLarge?.copyWith(color: kindColor, height: 1.2),
                    ),
                  ],
                ),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PlanKindBadge(kind: day.kind, dense: true),
                        const Spacer(),
                        Icon(isFuture ? Icons.schedule_rounded : day.status.icon, size: 16, color: statusColor),
                        Gap.w4,
                        Text(statusText, style: theme.textTheme.labelSmall?.copyWith(color: statusColor)),
                      ],
                    ),
                    Gap.h4,
                    Text(
                      day.title(bangla: context.isBn),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (day.totalItems > 0) ...[
                      Gap.h8,
                      PlanProgressBar(value: day.progress, color: statusColor, height: 6),
                    ],
                  ],
                ),
              ),
              Gap.w8,
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visually locked future: blurred placeholder cards (no real content is
/// ever loaded — RLS hides those days) with a lock and an explanation.
class LockedDaysSection extends StatelessWidget {
  const LockedDaysSection({required this.lockedDays, super.key});

  final int lockedDays;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: '${l.studyPlanLockedTitle}. ${l.studyPlanLockedCount(lockedDays, context.n(lockedDays))}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: Radii.card,
        child: Stack(
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++) ...[if (i > 0) Gap.h8, _FakeDayCard(seed: i)],
                ],
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.scaffoldBackgroundColor.withValues(alpha: 0.35),
                      theme.scaffoldBackgroundColor.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(Gap.md),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 16)],
                          ),
                          child: Icon(Icons.lock_rounded, color: scheme.onPrimary, size: 26),
                        ),
                        Gap.h12,
                        Text(l.studyPlanLockedTitle, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                        Gap.h4,
                        Text(
                          l.studyPlanLockedCount(lockedDays, context.n(lockedDays)),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FakeDayCard extends StatelessWidget {
  const _FakeDayCard({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bar = scheme.surfaceContainerHighest;
    final accents = [scheme.primary, AppColors.info, AppColors.warning];
    return Container(
      height: 76,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.card,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            decoration: BoxDecoration(
              color: accents[seed % accents.length].withValues(alpha: 0.18),
              borderRadius: Radii.button,
            ),
          ),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.35,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(color: bar, borderRadius: Radii.chip),
                  ),
                ),
                Gap.h8,
                FractionallySizedBox(
                  widthFactor: 0.7 - seed * 0.1,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(color: bar, borderRadius: Radii.chip),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
