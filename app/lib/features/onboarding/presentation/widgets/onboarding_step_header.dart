import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/onboarding/application/onboarding_flow.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// "Step 2 of 4" with four labelled segments (profile → interview →
/// level test → plan) and a "Do it later" shortcut into the app. Hidden when
/// the screen was opened again from Home (setup already finished/postponed).
class OnboardingStepHeader extends ConsumerWidget {
  const OnboardingStepHeader({required this.step, super.key});

  /// 1-based.
  final int step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentProfileProvider.select((p) => p.value?.isOnboarded ?? false))) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labels = [
      l.onboardingStepProfile,
      l.onboardingStepInterview,
      l.onboardingStepPlacement,
      l.onboardingStepPlan,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.onboardingStepOf(context.n(step), context.n(labels.length)),
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
              ),
            ),
            const OnboardingLaterButton(),
          ],
        ),
        Gap.h4,
        Semantics(
          label: l.onboardingStepOf(context.n(step), context.n(labels.length)),
          excludeSemantics: true,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) Gap.w4,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 5,
                        decoration: BoxDecoration(
                          color: i < step ? scheme.primary : scheme.primary.withValues(alpha: 0.15),
                          borderRadius: Radii.chip,
                        ),
                      ),
                      Gap.h4,
                      Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: i + 1 == step ? scheme.onSurface : scheme.onSurfaceVariant,
                          fontWeight: i + 1 == step ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Finishes onboarding now and opens Home; the skipped steps stay available
/// from Home's "Finish setting up" card.
class OnboardingLaterButton extends ConsumerStatefulWidget {
  const OnboardingLaterButton({super.key});

  @override
  ConsumerState<OnboardingLaterButton> createState() => _OnboardingLaterButtonState();
}

class _OnboardingLaterButtonState extends ConsumerState<OnboardingLaterButton> {
  bool _busy = false;

  Future<void> _later() async {
    final l = context.l10n;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    // The app-wide messenger outlives this screen.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await OnboardingFlow.finish(context, ref);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.onboardingDoLaterDone)));
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
      onPressed: _busy ? null : () => unawaited(_later()),
      child: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(context.l10n.onboardingDoLater),
    );
  }
}
