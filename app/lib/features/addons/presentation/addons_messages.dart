import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';

/// Localized messages for `redeem_promo` business errors. Registered with
/// [registerFailureMessages] so `showErrorSnack` / `failureMessage` pick them up.
String? addonsFailureMessage(BuildContext context, String code) {
  final error = PromoError.fromCode(code);
  if (error == null) return null;
  final l = context.l10n;
  return switch (error) {
    PromoError.invalid => l.addonsPromoInvalid,
    PromoError.exhausted => l.addonsPromoExhausted,
    PromoError.alreadyUsed => l.addonsPromoAlreadyUsed,
  };
}

/// Idempotent: the resolver is a top-level tear-off, so it's added only once.
void registerAddonsMessages() => registerFailureMessages(addonsFailureMessage);

String entitlementSourceLabel(AppLocalizations l, EntitlementSource source) => switch (source) {
  EntitlementSource.trial => l.addonsSourceTrial,
  EntitlementSource.promo => l.addonsSourcePromo,
  EntitlementSource.admin => l.addonsSourceAdmin,
  EntitlementSource.purchase => l.addonsSourcePurchase,
};

/// "৫ দিন বাকি" / "৩ ঘণ্টা বাকি" / "আজই শেষ".
String planCountdownLabel(BuildContext context, DateTime expiresAt, {DateTime? now}) {
  final l = context.l10n;
  final at = now ?? DateTime.now();
  final left = timeLeft(expiresAt, at);
  if (left.inHours >= 24) {
    final days = daysLeft(expiresAt, at);
    return l.addonsDaysLeft(days, context.n(days));
  }
  if (left.inHours >= 1) return l.addonsHoursLeft(left.inHours, context.n(left.inHours));
  return l.addonsEndsSoon;
}

/// "৳২৪৯/৩০ দিন"
String addonPriceLabel(BuildContext context, Addon addon) =>
    context.l10n.addonsPricePerPeriod(Fmt.currency(addon.priceBdt, bangla: context.isBn), context.n(addon.periodDays));

/// Brand colour of an add-on, lifted in dark mode so it stays readable on
/// dark surfaces.
Color addonAccent(Addon? addon, ColorScheme scheme) {
  final base = AppColors.fromHex(addon?.colorHex, fallback: scheme.primary);
  if (scheme.brightness == Brightness.dark) return Color.lerp(base, Colors.white, 0.3) ?? base;
  return base;
}
