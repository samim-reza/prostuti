import 'package:flutter/material.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';

/// Visual state of an answer option.
enum OptionVisual {
  /// Not chosen, still answerable.
  idle,

  /// Chosen in an exam (correctness unknown).
  selected,

  /// The correct answer (after grading / review).
  correct,

  /// The user's wrong choice.
  wrong,

  /// Neither chosen nor correct, after grading.
  muted,
}

/// BCS-style answer row: a lettered bubble (ক খ গ ঘ / A B C D) + option text.
class OptionTile extends StatelessWidget {
  const OptionTile({
    required this.label,
    required this.text,
    this.visual = OptionVisual.idle,
    this.onTap,
    this.busy = false,
    super.key,
  });

  final String label;
  final String text;
  final OptionVisual visual;
  final VoidCallback? onTap;

  /// Shows a small spinner in the bubble (waiting for the server verdict).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color border, Color background, Color bubble, Color bubbleText, IconData? trailing) = switch (visual) {
      OptionVisual.idle => (
        scheme.outlineVariant,
        Colors.transparent,
        Colors.transparent,
        scheme.onSurfaceVariant,
        null,
      ),
      OptionVisual.selected => (
        scheme.primary,
        scheme.primary.withValues(alpha: 0.08),
        scheme.primary,
        scheme.onPrimary,
        null,
      ),
      OptionVisual.correct => (
        AppColors.success,
        AppColors.success.withValues(alpha: 0.12),
        AppColors.success,
        Colors.white,
        Icons.check_circle_rounded,
      ),
      OptionVisual.wrong => (
        scheme.error,
        scheme.error.withValues(alpha: 0.10),
        scheme.error,
        scheme.onError,
        Icons.cancel_rounded,
      ),
      OptionVisual.muted => (
        scheme.outlineVariant.withValues(alpha: 0.5),
        Colors.transparent,
        Colors.transparent,
        scheme.onSurfaceVariant.withValues(alpha: 0.7),
        null,
      ),
    };
    final emphasized =
        visual == OptionVisual.selected || visual == OptionVisual.correct || visual == OptionVisual.wrong;
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: visual == OptionVisual.muted ? scheme.onSurfaceVariant : scheme.onSurface,
      fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
    );

    return Semantics(
      button: onTap != null,
      selected: visual == OptionVisual.selected,
      label: '$label. $text',
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.button,
          side: BorderSide(color: border, width: emphasized ? 1.6 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bubble,
                      shape: BoxShape.circle,
                      border: Border.all(color: bubble == Colors.transparent ? border : bubble, width: 1.4),
                    ),
                    child: busy
                        ? SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: bubbleText),
                          )
                        : Text(
                            label,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: bubbleText, height: 1.2),
                          ),
                  ),
                  Gap.w12,
                  Expanded(child: Text(text, style: textStyle)),
                  if (trailing != null) ...[Gap.w8, Icon(trailing, color: border, size: 22)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
