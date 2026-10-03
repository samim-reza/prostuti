import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/addons/application/addons_providers.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/data/payment_provider.dart';
import 'package:prostuti/features/addons/presentation/addons_messages.dart';

/// What the store should do after the purchase sheet closes.
enum PurchaseSheetOutcome { purchased, usePromo }

/// Runs [PaymentProvider.purchase] for [addon] and shows the outcome.
Future<PurchaseSheetOutcome?> showPurchaseSheet(BuildContext context, Addon addon) {
  return showModalBottomSheet<PurchaseSheetOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => PurchaseSheet(addon: addon),
  );
}

class PurchaseSheet extends ConsumerStatefulWidget {
  const PurchaseSheet({required this.addon, super.key});
  final Addon addon;

  @override
  ConsumerState<PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends ConsumerState<PurchaseSheet> {
  PaymentResult? _result;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    PaymentResult result;
    try {
      result = await ref.read(paymentProviderProvider).purchase(widget.addon);
    } on Object catch (e) {
      result = PaymentResult.failed(e);
    }
    if (result is PaymentSuccess) await refreshAfterPurchase(ref);
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final addon = widget.addon;
    final accent = addonAccent(addon, scheme);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: Radii.button),
                child: Icon(addon.iconData, color: accent),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(addon.name(bangla: context.isBn), style: theme.textTheme.titleMedium),
                    Text(addonPriceLabel(context, addon), style: theme.textTheme.bodyMedium?.copyWith(color: accent)),
                  ],
                ),
              ),
            ],
          ),
          Gap.h16,
          const Divider(),
          Gap.h16,
          AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;
    if (result == null) {
      return Column(
        key: const ValueKey('loading'),
        children: [
          const LinearProgressIndicator(),
          Gap.h12,
          Text(l.addonsPaymentProcessing, style: theme.textTheme.bodyMedium),
        ],
      );
    }
    return switch (result) {
      PaymentUnavailable() => Column(
        key: const ValueKey('unavailable'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.schedule_rounded, size: 40, color: scheme.primary),
          Gap.h12,
          Text(l.addonsPaymentComingSoon, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          Gap.h8,
          Text(
            l.addonsPaymentComingSoonBody,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          Gap.h16,
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              _MethodChip(icon: Icons.phone_android_rounded, label: l.addonsMethodBkash),
              _MethodChip(icon: Icons.phone_iphone_rounded, label: l.addonsMethodNagad),
              _MethodChip(icon: Icons.credit_card_rounded, label: l.addonsMethodCard),
            ],
          ),
          Gap.h24,
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(PurchaseSheetOutcome.usePromo),
            icon: const Icon(Icons.redeem_rounded),
            label: Text(l.addonsUsePromo),
          ),
          Gap.h8,
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.close)),
        ],
      ),
      PaymentSuccess() => _Outcome(
        key: const ValueKey('success'),
        icon: Icons.check_circle_rounded,
        color: scheme.primary,
        message: l.addonsPaymentSuccess,
        action: l.done,
        onAction: () => Navigator.of(context).pop(PurchaseSheetOutcome.purchased),
      ),
      PaymentPending() => _Outcome(
        key: const ValueKey('pending'),
        icon: Icons.hourglass_top_rounded,
        color: scheme.tertiary,
        message: l.addonsPaymentPending,
        action: l.ok,
        onAction: () => Navigator.of(context).pop(),
      ),
      PaymentCancelled() => _Outcome(
        key: const ValueKey('cancelled'),
        icon: Icons.close_rounded,
        color: scheme.onSurfaceVariant,
        message: l.addonsPaymentCancelled,
        action: l.close,
        onAction: () => Navigator.of(context).pop(),
      ),
      PaymentFailed(:final error) => _Outcome(
        key: const ValueKey('failed'),
        icon: Icons.error_outline_rounded,
        color: scheme.error,
        message: '${l.addonsPaymentFailed}\n${failureMessage(context, error)}',
        action: l.close,
        onAction: () => Navigator.of(context).pop(),
      ),
    };
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
      label: Text('$label · ${l.addonsSoon}'),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.color,
    required this.message,
    required this.action,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, size: 44, color: color),
        Gap.h12,
        Text(message, style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
        Gap.h24,
        FilledButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }
}
