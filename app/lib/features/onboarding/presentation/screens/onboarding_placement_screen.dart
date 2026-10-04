import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';
import 'package:prostuti/features/onboarding/application/onboarding_flow.dart';
import 'package:prostuti/features/onboarding/presentation/widgets/onboarding_step_header.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// An unfinished placement session to resume (null when none / offline).
final activePlacementProvider = FutureProvider.autoDispose<ExamSession?>((ref) async {
  if (!ConnectivityService.instance.isOnline) return null;
  try {
    final session = await ref.watch(examRepositoryProvider).active();
    return session?.kind == ExamKind.placement ? session : null;
  } on Object {
    return null;
  }
});

/// Step 3: the 40-question / 25-minute level test.
class OnboardingPlacementScreen extends ConsumerStatefulWidget {
  const OnboardingPlacementScreen({super.key});

  @override
  ConsumerState<OnboardingPlacementScreen> createState() => _OnboardingPlacementScreenState();
}

class _OnboardingPlacementScreenState extends ConsumerState<OnboardingPlacementScreen> {
  bool _busy = false;

  bool _requireOnline() {
    if (ConnectivityService.instance.isOnline) return true;
    showInfoSnack(context, context.l10n.offlineUnavailable);
    return false;
  }

  Future<void> _openSession(String sessionId) async {
    await context.push(Routes.examSession(sessionId));
    // Back without submitting (submitting opens the result screen itself):
    // the test can be resumed.
    if (!mounted) return;
    ref.invalidate(activePlacementProvider);
  }

  Future<void> _start() async {
    if (_busy || !_requireOnline()) return;
    setState(() => _busy = true);
    try {
      final session = await ref.read(examRepositoryProvider).start(ExamKind.placement);
      if (!mounted) return;
      setState(() => _busy = false);
      await _openSession(session.sessionId);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _later() async {
    final l = context.l10n;
    if (OnboardingFlow.isLater(ref)) {
      context.go(Routes.home);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: l.onboardingPlacementLaterTitle,
      message: l.onboardingPlacementLaterBody,
      confirmLabel: l.onboardingPlacementLaterConfirm,
    );
    if (!ok || !mounted || !_requireOnline()) return;
    setState(() => _busy = true);
    try {
      await OnboardingFlow.advance(context, ref, OnboardingStep.plan);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = ref.watch(activePlacementProvider).value;
    // Test shape is server-driven (app_config.placement).
    final shape = ref.watch(remoteConfigProvider.select((c) => c.value?.values.obj('placement'))) ?? const {};
    final perGroup = shape.integer('per_group', 10);
    final minutes = shape.integer('duration_minutes', 25);

    final groups = [
      (Icons.menu_book_rounded, l.onboardingGroupBangla, const Color(0xFF0E7C66)),
      (Icons.translate_rounded, l.onboardingGroupEnglish, const Color(0xFF3559E0)),
      (Icons.calculate_rounded, l.onboardingGroupMath, const Color(0xFFD9480F)),
      (Icons.public_rounded, l.onboardingGroupGk, const Color(0xFF7A4BD6)),
    ];
    final tips = [
      (Icons.skip_next_rounded, l.onboardingTipSkip),
      (Icons.remove_circle_outline_rounded, l.onboardingTipNegative),
      (Icons.timer_outlined, l.onboardingTipTimer),
      (Icons.self_improvement_rounded, l.onboardingTipHonest),
    ];

    final later = ref.watch(currentProfileProvider.select((p) => p.value?.isOnboarded ?? false));

    return Scaffold(
      // Opened again from Home: a plain back button instead of the step header.
      appBar: later ? AppBar() : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xl),
          children: [
            const OnboardingStepHeader(step: 3),
            Gap.h24,
            Text(l.onboardingPlacementTitle, style: theme.textTheme.headlineSmall),
            Gap.h4,
            Text(
              l.onboardingPlacementSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Gap.h16,
            Row(
              children: [
                _Fact(
                  icon: Icons.help_outline_rounded,
                  value: context.n(perGroup * 4),
                  label: l.onboardingFactQuestions,
                ),
                Gap.w8,
                _Fact(icon: Icons.timer_rounded, value: context.n(minutes), label: l.onboardingFactMinutes),
                Gap.w8,
                _Fact(icon: Icons.category_rounded, value: context.n(4), label: l.onboardingFactSubjects),
              ],
            ),
            Gap.h16,
            Card(
              child: Padding(
                padding: Gap.card,
                child: Column(
                  children: [
                    for (final (i, g) in groups.indexed) ...[
                      if (i > 0) const Divider(height: Gap.xl),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(Gap.sm),
                            decoration: BoxDecoration(color: g.$3.withValues(alpha: 0.12), borderRadius: Radii.button),
                            child: Icon(g.$1, color: g.$3, size: 20),
                          ),
                          Gap.w12,
                          Expanded(child: Text(g.$2, style: theme.textTheme.titleSmall)),
                          Text(
                            l.onboardingQuestionsShort(context.n(perGroup)),
                            style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Gap.h16,
            Text(l.onboardingTipsTitle, style: theme.textTheme.titleMedium),
            Gap.h8,
            for (final t in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(t.$1, size: 20, color: AppColors.gold),
                    Gap.w12,
                    Expanded(child: Text(t.$2, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            if (active != null) ...[
              Gap.h12,
              Card(
                color: scheme.primary.withValues(alpha: 0.07),
                child: ListTile(
                  leading: Icon(Icons.play_circle_fill_rounded, color: scheme.primary, size: 36),
                  title: Text(l.onboardingResumeTitle),
                  subtitle: Text(l.onboardingResumeBody),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy ? null : () => unawaited(_openSession(active.sessionId)),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : (active != null ? () => _openSession(active.sessionId) : _start),
                icon: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(active != null ? l.onboardingResumeCta : l.onboardingStartTest),
              ),
              if (!later) TextButton(onPressed: _busy ? null : _later, child: Text(l.onboardingPlacementLater)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.07), borderRadius: Radii.button),
        child: Column(
          children: [
            Icon(icon, color: scheme.primary),
            Gap.h4,
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
