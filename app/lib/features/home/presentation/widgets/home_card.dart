import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';

/// Card shell used by every Home section: icon + title row, optional
/// trailing widget and an optional tap target for the whole card.
class HomeCard extends StatelessWidget {
  const HomeCard({
    required this.child,
    this.title,
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.padding = Gap.card,
    super.key,
  });

  final String? title;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.primary;
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(Gap.xs + 2),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.button),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  Gap.w8,
                ],
                Expanded(
                  child: Semantics(header: true, child: Text(title!, style: theme.textTheme.titleMedium)),
                ),
                ?trailing,
              ],
            ),
            Gap.h12,
          ],
          child,
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Inline "couldn't load" row with a retry button (used inside cards so one
/// failing section never takes down the whole Home screen).
class HomeInlineError extends StatelessWidget {
  const HomeInlineError({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, color: scheme.onSurfaceVariant),
        Gap.w12,
        Expanded(
          child: Text(
            failureMessage(context, error),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    );
  }
}
