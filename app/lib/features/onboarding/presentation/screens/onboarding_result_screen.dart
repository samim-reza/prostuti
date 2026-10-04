import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/home/application/home_helpers.dart';
import 'package:prostuti/features/home/application/home_providers.dart';
import 'package:prostuti/features/onboarding/application/onboarding_flow.dart';
import 'package:prostuti/features/onboarding/application/placement_groups.dart';
import 'package:prostuti/features/onboarding/presentation/widgets/onboarding_step_header.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/generating_plan_view.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_ui.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/readiness_gauge.dart';

String placementGroupLabel(BuildContext context, PlacementGroup g) {
  final l = context.l10n;
  return switch (g) {
    PlacementGroup.bangla => l.onboardingGroupBangla,
    PlacementGroup.english => l.onboardingGroupEnglish,
    PlacementGroup.math => l.onboardingGroupMath,
    PlacementGroup.gk => l.onboardingGroupGk,
  };
}

enum _Phase { report, generating, preview, failed }

/// Step 4: level report → AI plan generation → a peek at the first three
/// days (the rest of the plan unlocks day by day) → Home.
class OnboardingResultScreen extends ConsumerStatefulWidget {
  const OnboardingResultScreen({super.key});

  @override
  ConsumerState<OnboardingResultScreen> createState() => _OnboardingResultScreenState();
}

class _OnboardingResultScreenState extends ConsumerState<OnboardingResultScreen> {
  _Phase _phase = _Phase.report;
  AppFailure? _error;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    // The placement test just changed levels and mastery: refresh both.
    unawaited(
      Future.microtask(
        () => Future.wait([
          ref.read(currentProfileProvider.notifier).reload().catchError((Object _) {}),
          ref.read(readinessProvider.notifier).refresh().catchError((Object _) {}),
        ]),
      ),
    );
  }

  Future<void> _generate() async {
    final l = context.l10n;
    if (!ConnectivityService.instance.isOnline) {
      setState(() {
        _phase = _Phase.failed;
        _error = const NetworkFailure();
      });
      return;
    }
    final access = ref.read(featureAccessProvider).value;
    if (access != null && access[Features.aiStudyPlan] == false) {
      showLockedSheet(context);
      return;
    }
    setState(() => _phase = _Phase.generating);
    final ok = await ref.read(planGenerationProvider.notifier).generate();
    if (!mounted) return;
    if (ok) {
      await ref.read(todayRoutineProvider.notifier).refresh().catchError((Object _) {});
      if (!mounted) return;
      setState(() => _phase = _Phase.preview);
    } else {
      final error = ref.read(planGenerationProvider).error;
      if (error is FeatureLockedFailure) {
        setState(() => _phase = _Phase.report);
        showLockedSheet(context);
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _error = error;
      });
      if (error is! NetworkFailure) showInfoSnack(context, l.studyPlanGenerateFailed);
    }
  }

  /// Onboarding done (with or without a plan) → Home.
  Future<void> _finish() async {
    if (_finishing) return;
    if (!ConnectivityService.instance.isOnline && !OnboardingFlow.isLater(ref)) {
      showInfoSnack(context, context.l10n.offlineUnavailable);
      return;
    }
    setState(() => _finishing = true);
    try {
      await OnboardingFlow.finish(context, ref);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final body = switch (_phase) {
      _Phase.report => _ReportView(onGenerate: _generate),
      _Phase.generating => const Center(child: GeneratingPlanView()),
      _Phase.preview => const _PreviewView(),
      _Phase.failed => _FailedView(error: _error, onRetry: _generate),
    };
    // The plan is optional too: the report can be left without building one.
    final showFinish = _phase != _Phase.generating;
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: KeyedSubtree(key: ValueKey(_phase), child: body),
        ),
      ),
      bottomNavigationBar: showFinish
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.md),
                child: _phase == _Phase.preview
                    ? FilledButton.icon(
                        onPressed: _finishing ? null : _finish,
                        icon: _finishing
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : const Icon(Icons.rocket_launch_rounded),
                        label: Text(l.onboardingStartJourney),
                      )
                    : _phase == _Phase.report
                    ? TextButton(onPressed: _finishing ? null : _finish, child: Text(l.onboardingContinueWithoutPlan))
                    : OutlinedButton(
                        onPressed: _finishing ? null : _finish,
                        child: Text(l.onboardingContinueWithoutPlan),
                      ),
              ),
            )
          : null,
    );
  }
}

class _ReportView extends ConsumerWidget {
  const _ReportView({required this.onGenerate});

  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final readiness = ref.watch(readinessProvider);
    final schedule = ref.watch(targetScheduleProvider);
    final r = readiness.value;
    final groups = r == null ? const <GroupLevel>[] : groupLevels(r);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xl),
      children: [
        const OnboardingStepHeader(step: 4),
        Gap.h24,
        Text(l.onboardingResultTitle, style: theme.textTheme.headlineSmall),
        Gap.h4,
        Text(l.onboardingResultSubtitle, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        Gap.h16,
        if (r == null && readiness.hasError)
          ErrorView(error: readiness.error!, compact: true, onRetry: () => ref.invalidate(readinessProvider))
        else if (r == null)
          const SkeletonShimmer(child: SkeletonBox(height: 220, radius: 16))
        else ...[
          Card(
            child: Padding(
              padding: Gap.card,
              child: Column(
                children: [
                  ReadinessGauge(value: r.readiness, size: 170, caption: l.studyPlanReadyForFinal),
                  Gap.h8,
                  Text(
                    l.homeEstimatedScore(context.n(r.estimatedScore), context.n(r.maxScore)),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          Gap.h12,
          if (groups.isEmpty)
            Card(
              child: ListTile(
                leading: Icon(Icons.info_outline_rounded, color: scheme.primary),
                title: Text(l.onboardingNoLevels),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                child: Column(children: [for (final g in groups) _GroupLevelRow(level: g)]),
              ),
            ),
        ],
        if (schedule != null) ...[
          Gap.h12,
          Card(
            child: ListTile(
              leading: Icon(Icons.hourglass_bottom_rounded, color: scheme.primary),
              title: Text(schedule.title(context)),
              subtitle: Text(
                [
                  l.onboardingDaysUntilExam(context.n(daysUntil(schedule.expectedDate, BdTime.today()))),
                  Fmt.date(
                    DateTime.utc(schedule.expectedDate.year, schedule.expectedDate.month, schedule.expectedDate.day),
                    bangla: context.isBn,
                  ),
                  if (!schedule.isConfirmed) l.onboardingTentative,
                ].join(' · '),
              ),
            ),
          ),
        ],
        Gap.h24,
        Text(
          l.onboardingPlanPitch,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Gap.h12,
        FilledButton.icon(
          onPressed: onGenerate,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: Text(l.studyPlanCreate),
        ),
      ],
    );
  }
}

class _GroupLevelRow extends StatelessWidget {
  const _GroupLevelRow({required this.level});

  final GroupLevel level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = level.level.color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
      child: Column(
        children: [
          Row(
            children: [
              Icon(level.level.icon, color: color),
              Gap.w12,
              Expanded(child: Text(placementGroupLabel(context, level.group), style: theme.textTheme.titleSmall)),
              PlanPill(label: level.level.label(context), color: color),
              Gap.w8,
              SizedBox(
                width: 44,
                child: Text(
                  '${context.n((level.scorePct * 100).round())}%',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
          Gap.h8,
          PlanProgressBar(value: level.scorePct, color: color, height: 6),
        ],
      ),
    );
  }
}

class _PreviewView extends ConsumerWidget {
  const _PreviewView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final routine = ref.watch(todayRoutineProvider).value;
    final today = routine?.today;
    final upcoming = routine?.upcoming ?? const <PlanDayBrief>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.xl),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(Gap.lg),
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.celebration_rounded, size: 44, color: scheme.primary),
          ),
        ),
        Gap.h16,
        Text(l.onboardingPlanReadyTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        Gap.h8,
        Text(
          l.onboardingPlanReadyBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Gap.h24,
        if (today != null)
          _PreviewDay(
            label: l.studyPlanToday,
            kind: today.kind,
            title: today.title(bangla: context.isBn),
            minutes: today.plannedMinutes,
            items: [for (final i in today.items.take(5)) i.title(bangla: context.isBn)],
          ),
        for (final (i, d) in upcoming.take(2).indexed)
          _PreviewDay(
            label: i == 0 ? l.homeTomorrow : PlanFmt.weekdayShort(context, d.date),
            kind: d.kind,
            title: d.title(bangla: context.isBn),
            minutes: d.targetMinutes,
          ),
        if (today == null && upcoming.isEmpty)
          EmptyView(compact: true, icon: Icons.event_note_rounded, title: l.onboardingPreviewEmpty),
        Gap.h8,
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: Radii.card,
          ),
          child: Row(
            children: [
              Icon(Icons.lock_clock_rounded, color: scheme.onSurfaceVariant),
              Gap.w12,
              Expanded(child: Text(l.onboardingUnlockNote, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewDay extends StatelessWidget {
  const _PreviewDay({
    required this.label,
    required this.kind,
    required this.title,
    required this.minutes,
    this.items = const [],
  });

  final String label;
  final PlanDayKind kind;
  final String title;
  final int minutes;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Card(
        child: Padding(
          padding: Gap.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
                  const Spacer(),
                  PlanKindBadge(kind: kind, dense: true),
                ],
              ),
              Gap.h8,
              Text(title, style: theme.textTheme.titleSmall),
              if (minutes > 0)
                Text(
                  PlanFmt.minutes(context, minutes),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.xs),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, size: 16, color: scheme.primary),
                      Gap.w8,
                      Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.error, required this.onRetry});

  final AppFailure? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final offline = error is NetworkFailure;
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Gap.h32,
        EmptyView(
          icon: offline ? Icons.wifi_off_rounded : Icons.auto_awesome_motion_rounded,
          title: offline ? l.offlineUnavailable : l.onboardingPlanFailedTitle,
          message: offline ? l.onboardingPlanOfflineBody : l.onboardingPlanFailedBody,
          actionLabel: l.retry,
          action: onRetry,
        ),
      ],
    );
  }
}
