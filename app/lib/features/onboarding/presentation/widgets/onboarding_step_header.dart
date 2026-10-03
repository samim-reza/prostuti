import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';

/// "Step 2 of 4" with four labelled segments (profile → interview →
/// level test → plan).
class OnboardingStepHeader extends StatelessWidget {
  const OnboardingStepHeader({required this.step, super.key});

  /// 1-based.
  final int step;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labels = [
      l.onboardingStepProfile,
      l.onboardingStepInterview,
      l.onboardingStepPlacement,
      l.onboardingStepPlan,
    ];
    return Semantics(
      label: l.onboardingStepOf(context.n(step), context.n(labels.length)),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.onboardingStepOf(context.n(step), context.n(labels.length)),
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
          Gap.h8,
          Row(
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
        ],
      ),
    );
  }
}
