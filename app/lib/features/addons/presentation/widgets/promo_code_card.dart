import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/addons/application/addons_providers.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/data/addons_repository.dart';
import 'package:prostuti/features/addons/presentation/widgets/promo_success_dialog.dart';

/// Promo-code entry → `redeem_promo` → success animation → every feature gate
/// and the plan list refresh immediately.
class PromoCodeCard extends ConsumerStatefulWidget {
  const PromoCodeCard({this.focusNode, super.key});

  final FocusNode? focusNode;

  @override
  ConsumerState<PromoCodeCard> createState() => _PromoCodeCardState();
}

class _PromoCodeCardState extends ConsumerState<PromoCodeCard> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_busy) return;
    final l = context.l10n;
    final code = normalizePromoCode(_controller.text);
    if (code.isEmpty) {
      showInfoSnack(context, l.addonsPromoEmpty);
      return;
    }
    FocusScope.of(context).unfocus();
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(addonsRepositoryProvider).redeemPromo(code);
      await refreshAfterPurchase(ref);
      if (!mounted) return;
      _controller.clear();
      final catalog = ref.read(addonCatalogProvider).value;
      await showPromoSuccessDialog(context, redemption: result, addon: catalog?.byCode(result.addonCode));
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.redeem_rounded, color: scheme.secondary),
                Gap.w8,
                Expanded(child: Text(l.addonsPromoTitle, style: theme.textTheme.titleMedium)),
              ],
            ),
            Gap.h4,
            Text(l.addonsPromoSubtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            Gap.h12,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: widget.focusNode,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 40,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => unawaited(_redeem()),
                    decoration: InputDecoration(
                      hintText: l.addonsPromoHint,
                      counterText: '',
                      prefixIcon: const Icon(Icons.confirmation_number_outlined),
                    ),
                  ),
                ),
                Gap.w8,
                FilledButton.tonal(
                  onPressed: _busy ? null : () => unawaited(_redeem()),
                  style: FilledButton.styleFrom(minimumSize: const Size(96, 52)),
                  child: _busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                      : Text(l.addonsPromoRedeem),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
