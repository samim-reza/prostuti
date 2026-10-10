import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/study_plan/application/daily_advice_providers.dart';
import 'package:prostuti/features/study_plan/data/daily_advice_models.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/online_guard.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_ui.dart';

/// "প্রস্তুতি এআই-এর পরামর্শ" — today's advice built from the learner's own
/// data (weak topics, recent exams, routine, streak, days left).
///
/// Self-contained: loads, caches (until Bangladesh midnight, offline too) and
/// refreshes itself. Shows a skeleton on the first load and renders nothing
/// when there is no advice (a new learner without any data, or the advice is
/// unavailable), so it can be dropped into any list.
class AiAdviceCard extends ConsumerWidget {
  const AiAdviceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advice = ref.watch(dailyAdviceProvider);
    final child = advice.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const _AdviceSkeleton(),
      error: (_, _) => const SizedBox.shrink(),
      data: (a) => a.isEmpty ? const SizedBox.shrink() : _AdviceContent(advice: a),
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child),
    );
  }
}

class _AdviceContent extends ConsumerWidget {
  const _AdviceContent({required this.advice});

  final DailyAdvice advice;

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    if (!ensureOnline(context)) return;
    final l = context.l10n;
    try {
      final next = await ref.read(dailyAdviceProvider.notifier).regenerate();
      if (!context.mounted) return;
      showInfoSnack(context, next.unchanged ? l.studyPlanAdviceUpToDate : l.studyPlanAdviceRefreshed);
    } on Object catch (e) {
      if (!context.mounted) return;
      if (AppFailure.from(e) is RateLimitFailure) {
        showInfoSnack(context, l.studyPlanAdviceRefreshLimit);
      } else {
        showErrorSnack(context, e);
      }
    }
  }

  String _updated(BuildContext context) {
    final l = context.l10n;
    final day = advice.day;
    if (!advice.isToday && day != null) return l.studyPlanAdviceFromDay(PlanFmt.date(context, day, withYear: false));
    final at = advice.generatedAt;
    return at == null ? l.studyPlanAdviceForToday : l.studyPlanAdviceUpdatedAt(Fmt.time(at, bangla: context.isBn));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final refreshing = ref.watch(dailyAdviceRefreshingProvider);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [scheme.primary.withValues(alpha: 0.08), scheme.primary.withValues(alpha: 0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.xs, Gap.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _AiBadge(),
                  Gap.w12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l.studyPlanAdviceTitle,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          _updated(context),
                          style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  SizedBox.square(
                    dimension: 48,
                    child: refreshing
                        ? const Center(
                            child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            tooltip: l.studyPlanAdviceRefresh,
                            onPressed: () => unawaited(_refresh(context, ref)),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                  ),
                ],
              ),
              Gap.h4,
              for (final (i, tip) in advice.tips.indexed) _TipTile(index: i, tip: tip),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radii.md),
        gradient: LinearGradient(
          colors: [scheme.primary, Color.lerp(scheme.primary, AppColors.gold, 0.55)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.auto_awesome_rounded, color: scheme.onPrimary, size: 22),
    );
  }
}

class _TipTile extends StatelessWidget {
  const _TipTile({required this.index, required this.tip});

  final int index;
  final AdviceTip tip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final route = tip.actionRoute;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(0, Gap.sm, Gap.sm, Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Text(
              context.n(index + 1),
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
            ),
          ),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tip.title.isNotEmpty)
                  Text(tip.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (tip.body.isNotEmpty) ...[
                  const SizedBox(height: Gap.xxs),
                  Text(tip.body, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          if (route != null) ...[
            Gap.w4,
            Padding(
              padding: const EdgeInsets.only(top: Gap.xxs),
              child: Icon(Icons.chevron_right_rounded, color: scheme.primary),
            ),
          ],
        ],
      ),
    );
    if (route == null) return content;
    return InkWell(borderRadius: Radii.button, onTap: () => _open(context, route), child: content);
  }
}

/// Opens a tip's screen: tabs are switched to, other screens pushed on top;
/// a tip pointing at the screen already shown does nothing.
void _open(BuildContext context, String route) {
  if (!isAdviceRouteAllowed(route)) return;
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  if (router.routerDelegate.currentConfiguration.isNotEmpty && router.state.uri.toString() == route) return;
  if (route == Routes.exams) {
    router.go(route);
  } else {
    unawaited(router.push(route));
  }
}

class _AdviceSkeleton extends StatelessWidget {
  const _AdviceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: Gap.card,
        child: SkeletonShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  SkeletonBox(width: 40, height: 40, radius: 12),
                  Gap.w12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [SkeletonBox(width: 170, height: 16), Gap.h4, SkeletonBox(width: 110, height: 10)],
                    ),
                  ),
                ],
              ),
              for (var i = 0; i < 3; i++) ...[
                Gap.h16,
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 26, height: 26, radius: 13),
                    Gap.w12,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 140),
                          Gap.h8,
                          SkeletonBox(height: 10),
                          Gap.h4,
                          SkeletonBox(width: 200, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
