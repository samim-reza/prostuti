import 'package:flutter/material.dart';
import 'package:prostuti/core/theme/app_spacing.dart';

/// A titled card that groups related settings rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({required this.title, required this.children, this.footer, super.key});

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs, bottom: Gap.sm),
            child: Text(title, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary, letterSpacing: 0.2)),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(indent: 56), children[i]],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.sm, Gap.xs, 0),
              child: Text(footer!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// Leading icon in a soft tinted square, used by every settings row.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {this.color, super.key});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: const BorderRadius.all(Radii.sm)),
      child: Icon(icon, size: 20, color: c),
    );
  }
}
