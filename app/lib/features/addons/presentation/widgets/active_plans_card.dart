import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/addons/application/addons_providers.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/presentation/addons_messages.dart';

/// "আমার সক্রিয় প্ল্যান" — every running add-on with its source and countdown.
class ActivePlansCard extends ConsumerWidget {
  const ActivePlansCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final plans = ref.watch(myPlansProvider);
    final catalog = ref.watch(addonCatalogProvider).value ?? AddonCatalog.empty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.addonsMyPlans, style: theme.textTheme.titleMedium),
        Gap.h8,
        plans.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const SkeletonShimmer(child: SkeletonBox(height: 92, radius: 16)),
          error: (e, _) => Card(
            child: ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(myPlansProvider)),
          ),
          data: (list) => list.isEmpty
              ? const _FreePlanCard()
              : Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(indent: Gap.lg, endIndent: Gap.lg),
                        _PlanRow(plan: list[i], addon: catalog.byCode(list[i].addonCode)),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.addon});
  final ActivePlan plan;
  final Addon? addon;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = addonAccent(addon, scheme);
    final now = DateTime.now();
    final name = addon?.name(bangla: context.isBn) ?? plan.addonCode;

    return Padding(
      padding: Gap.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(addon?.iconData ?? Icons.workspace_premium_rounded, color: accent, size: 22),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleSmall),
                    Text(
                      l.addonsEndsOn(Fmt.date(plan.expiresAt, bangla: context.isBn)),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Gap.w8,
              _SourceChip(label: entitlementSourceLabel(l, plan.source), color: accent),
            ],
          ),
          Gap.h12,
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: Radii.chip,
                  child: LinearProgressIndicator(
                    value: plan.remainingFraction(now),
                    minHeight: 6,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.14),
                  ),
                ),
              ),
              Gap.w12,
              Text(
                planCountdownLabel(context, plan.expiresAt, now: now),
                style: theme.textTheme.labelMedium?.copyWith(color: accent, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2, vertical: Gap.xxs),
      decoration: BoxDecoration(
        borderRadius: Radii.chip,
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }
}

class _FreePlanCard extends StatelessWidget {
  const _FreePlanCard();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_open_rounded, color: scheme.primary),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.addonsNoActivePlan, style: theme.textTheme.titleSmall),
                  Gap.h4,
                  Text(
                    l.addonsNoActivePlanBody,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
