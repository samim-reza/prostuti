import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/presentation/addons_messages.dart';

/// Celebrates a successful promo redemption (bouncy check + sparkle ring).
Future<void> showPromoSuccessDialog(BuildContext context, {required PromoRedemption redemption, Addon? addon}) {
  return showDialog<void>(
    context: context,
    builder: (_) => PromoSuccessDialog(redemption: redemption, addon: addon),
  );
}

class PromoSuccessDialog extends StatelessWidget {
  const PromoSuccessDialog({required this.redemption, this.addon, super.key});

  final PromoRedemption redemption;
  final Addon? addon;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = addonAccent(addon, scheme);
    final name = addon?.name(bangla: context.isBn) ?? redemption.addonCode;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.elasticOut,
              builder: (context, t, child) => Transform.scale(scale: 0.4 + 0.6 * t, child: child),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.6, end: 1),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => Container(
                      width: 104 * t,
                      height: 104 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.12 * (1.6 - t)),
                      ),
                    ),
                  ),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: Icon(
                      Icons.check_rounded,
                      size: 44,
                      color: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Gap.h16,
            Text(l.addonsPromoSuccessTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            Gap.h8,
            Text(
              l.addonsPromoSuccessBody(name, context.n(redemption.days)),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap.h4,
            Text(
              l.addonsPromoSuccessExpiry(Fmt.date(redemption.expiresAt, bangla: context.isBn)),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            Gap.h24,
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.addonsPromoSuccessCta)),
          ],
        ),
      ),
    );
  }
}
