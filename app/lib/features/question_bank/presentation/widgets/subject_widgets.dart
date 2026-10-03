import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_kind_style.dart';
import 'package:prostuti/features/exam/presentation/widgets/score_ring.dart';

/// Mastery ring (0…1) with the percentage inside; "—" when not assessed.
class MasteryRing extends StatelessWidget {
  const MasteryRing({required this.mastery, this.size = 46, super.key});

  final double? mastery;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = mastery;
    final pct = m == null ? null : (m * 100).clamp(0, 100).toDouble();
    final color = pct == null ? Theme.of(context).colorScheme.outline : scoreColor(pct);
    final label = pct == null
        ? l.questionBankNotAssessed
        : l.questionBankMasteryValue(Fmt.percent(pct, bangla: context.isBn));
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: ScoreRing(
        value: (m ?? 0).clamp(0, 1).toDouble(),
        color: color,
        size: size,
        stroke: size / 9,
        child: Text(
          pct == null ? '—' : Fmt.digits(pct.round(), bangla: context.isBn),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }
}

/// Horizontal mastery bar with label (topics).
class MasteryBar extends StatelessWidget {
  const MasteryBar({required this.mastery, super.key});

  final double? mastery;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final m = mastery;
    if (m == null) {
      return Text(
        l.questionBankNotAssessed,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final pct = (m * 100).clamp(0, 100).toDouble();
    final color = scoreColor(pct);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: Radii.chip,
            child: LinearProgressIndicator(
              value: m.clamp(0, 1).toDouble(),
              minHeight: 6,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        Gap.w8,
        Text(
          Fmt.percent(pct, bangla: context.isBn),
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Coloured rounded square with the subject icon.
class SubjectBadge extends StatelessWidget {
  const SubjectBadge({required this.icon, required this.color, this.size = 46, super.key});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: Radii.button),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}
