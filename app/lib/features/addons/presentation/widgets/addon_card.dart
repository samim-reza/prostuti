import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/presentation/addons_messages.dart';

/// One add-on in the store: what it unlocks, its price per period and a buy
/// (or extend) button. Prostuti Pro gets an accent border and a badge.
class AddonCard extends StatelessWidget {
  const AddonCard({
    required this.addon,
    required this.featureNames,
    required this.onBuy,
    this.plan,
    this.busy = false,
    super.key,
  });

  final Addon addon;
  final List<String> featureNames;
  final ActivePlan? plan;
  final VoidCallback onBuy;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = addonAccent(addon, scheme);
    final bangla = context.isBn;
    final highlight = addon.isPro;
    final description = addon.description(bangla: bangla);
    final badge = highlight ? (bangla ? (addon.badge ?? l.addonsBestValue) : l.addonsBestValue) : addon.badge;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: highlight
            ? BorderSide(color: accent, width: 2)
            : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlight)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.04)]),
              ),
              child: const SizedBox(height: 6),
            ),
          Padding(
            padding: Gap.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: Radii.button),
                      child: Icon(addon.iconData, color: accent, size: 26),
                    ),
                    Gap.w12,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: Gap.sm,
                            runSpacing: Gap.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(addon.name(bangla: bangla), style: theme.textTheme.titleMedium),
                              if (badge != null && badge.trim().isNotEmpty) _Badge(label: badge, color: accent),
                            ],
                          ),
                          if (description != null) ...[
                            Gap.h4,
                            Text(
                              description,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (featureNames.isNotEmpty) ...[
                  Gap.h12,
                  Text(l.addonsIncludes, style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                  Gap.h4,
                  for (final name in featureNames)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.xxs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Icon(Icons.check_circle_rounded, size: 18, color: accent),
                          ),
                          Gap.w8,
                          Expanded(child: Text(name, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
                if (plan != null) ...[Gap.h12, _ActiveStrip(plan: plan!, color: accent)],
                Gap.h12,
                const Divider(),
                Gap.h12,
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            addonPriceLabel(context, addon),
                            style: theme.textTheme.titleLarge?.copyWith(color: highlight ? accent : null),
                          ),
                          if (addon.trialDays > 0)
                            Text(
                              l.addonsTrialBadge(context.n(addon.trialDays)),
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    Gap.w12,
                    FilledButton(
                      onPressed: busy ? null : onBuy,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(112, 46),
                        backgroundColor: highlight ? accent : null,
                        foregroundColor: highlight ? _onColor(accent) : null,
                      ),
                      child: busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                          : Text(plan == null ? l.addonsBuy : l.addonsExtend),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _onColor(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : const Color(0xFF111111);
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xxs),
      decoration: BoxDecoration(color: color, borderRadius: Radii.chip),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AddonCard._onColor(color), fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ActiveStrip extends StatelessWidget {
  const _ActiveStrip({required this.plan, required this.color});
  final ActivePlan plan;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: Radii.button),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, size: 18, color: color),
          Gap.w8,
          Expanded(
            child: Text(
              '${l.addonsActive} · ${entitlementSourceLabel(l, plan.source)} · '
              '${planCountdownLabel(context, plan.expiresAt)}',
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
