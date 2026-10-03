import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/features/addons/application/addons_providers.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/presentation/addons_messages.dart';

/// Current plan (or free plan + upsell) on the profile tab → add-on store.
class PremiumStatusCard extends ConsumerWidget {
  const PremiumStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(primaryPlanProvider);
    final catalog = ref.watch(addonCatalogProvider).value;
    final moreCount = (ref.watch(myPlansProvider).value?.length ?? 0) - 1;

    return plan.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const SkeletonShimmer(child: SkeletonBox(height: 96, radius: 16)),
      // Plans are a nice-to-have here; on error show the upsell (still useful).
      error: (_, _) => const _Body(plan: null, addon: null, moreCount: 0),
      data: (p) => _Body(plan: p, addon: p == null ? null : catalog?.byCode(p.addonCode), moreCount: moreCount),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.plan, required this.addon, required this.moreCount});

  final ActivePlan? plan;
  final Addon? addon;
  final int moreCount;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = plan;
    final active = p != null;
    final accent = active ? addonAccent(addon, scheme) : scheme.primary;
    final title = active ? (addon?.name(bangla: context.isBn) ?? p.addonCode) : l.profileFreePlan;
    final subtitle = !active
        ? l.profileFreePlanHint
        : [
            if (p.isTrial) l.profileTrialRunning else entitlementSourceLabel(l, p.source),
            planCountdownLabel(context, p.expiresAt),
            if (moreCount > 0) l.profileMorePlans(context.n(moreCount)),
          ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: accent.withValues(alpha: active ? 0.5 : 0.3)),
      ),
      child: InkWell(
        onTap: () => unawaited(context.push(Routes.addons)),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.14), accent.withValues(alpha: 0.03)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: Gap.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), shape: BoxShape.circle),
                    child: Icon(
                      active ? Icons.workspace_premium_rounded : Icons.rocket_launch_outlined,
                      color: active ? accent : AppColors.gold,
                    ),
                  ),
                  Gap.w12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Gap.w8,
                  Text(
                    active ? l.profileManagePlan : l.profileUpgrade,
                    style: theme.textTheme.labelLarge?.copyWith(color: accent),
                  ),
                  Icon(Icons.chevron_right_rounded, color: accent),
                ],
              ),
              if (active) ...[
                Gap.h12,
                ClipRRect(
                  borderRadius: Radii.chip,
                  child: LinearProgressIndicator(
                    value: p.remainingFraction(DateTime.now()),
                    minHeight: 6,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
