import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/addons/application/addons_providers.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/presentation/addons_messages.dart';
import 'package:prostuti/features/addons/presentation/widgets/active_plans_card.dart';
import 'package:prostuti/features/addons/presentation/widgets/addon_card.dart';
import 'package:prostuti/features/addons/presentation/widgets/promo_code_card.dart';
import 'package:prostuti/features/addons/presentation/widgets/purchase_sheet.dart';

/// The add-on store: every premium feature is sold separately. Purchases go
/// through a pluggable `PaymentProvider`; until a gateway ships, free trials
/// and promo codes unlock features.
class AddonsScreen extends ConsumerStatefulWidget {
  const AddonsScreen({super.key});

  @override
  ConsumerState<AddonsScreen> createState() => _AddonsScreenState();
}

class _AddonsScreenState extends ConsumerState<AddonsScreen> {
  final _promoKey = GlobalKey();
  final _promoFocus = FocusNode();
  String? _buying;

  @override
  void initState() {
    super.initState();
    registerAddonsMessages();
  }

  @override
  void dispose() {
    _promoFocus.dispose();
    super.dispose();
  }

  Future<void> _buy(Addon addon) async {
    if (_buying != null) return;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, context.l10n.offlineUnavailable);
      return;
    }
    setState(() => _buying = addon.code);
    final outcome = await showPurchaseSheet(context, addon);
    if (!mounted) return;
    setState(() => _buying = null);
    if (outcome == PurchaseSheetOutcome.usePromo) _focusPromo();
  }

  void _focusPromo() {
    final target = _promoKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    }
    _promoFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = ref.watch(addonCatalogProvider);
    final plans = ref.watch(myPlansProvider).value ?? const <ActivePlan>[];
    final planByCode = {for (final p in plans) p.addonCode: p};

    return Scaffold(
      appBar: AppBar(title: Text(l.addonsTitle)),
      body: RefreshIndicator(
        onRefresh: () => refreshStore(ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
              sliver: SliverToBoxAdapter(child: _HeroHeader()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, 0),
              sliver: SliverToBoxAdapter(child: ActivePlansCard()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 0),
              sliver: SliverToBoxAdapter(
                child: PromoCodeCard(key: _promoKey, focusNode: _promoFocus),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.sm),
              sliver: SliverToBoxAdapter(child: Text(l.addonsAllAddons, style: theme.textTheme.titleMedium)),
            ),
            ...catalog.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const [SliverToBoxAdapter(child: SkeletonCards(height: 220))],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: ErrorView(error: e, onRetry: () => ref.invalidate(addonCatalogProvider)),
                ),
              ],
              data: (c) => [
                if (c.addons.isEmpty)
                  SliverToBoxAdapter(
                    child: EmptyView(icon: Icons.extension_off_rounded, title: l.addonsEmpty, compact: true),
                  )
                else
                  SliverPadding(
                    padding: Gap.screen,
                    sliver: SliverList.separated(
                      itemCount: c.addons.length,
                      separatorBuilder: (_, _) => Gap.h16,
                      itemBuilder: (context, i) {
                        final addon = c.addons[i];
                        return AddonCard(
                          addon: addon,
                          featureNames: c.featureNames(addon, bangla: context.isBn),
                          plan: planByCode[addon.code],
                          busy: _buying == addon.code,
                          onBuy: () => unawaited(_buy(addon)),
                        );
                      },
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, 0),
                  sliver: SliverToBoxAdapter(child: _FreeFeatures(catalog: c)),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.xxl),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    Gap.w8,
                    Expanded(
                      child: Text(
                        l.addonsFooterNote,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        borderRadius: Radii.card,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.28) ?? scheme.primary],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.addonsHeroTitle, style: theme.textTheme.titleLarge?.copyWith(color: scheme.onPrimary)),
                Gap.h8,
                Text(
                  l.addonsHeroBody,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.92)),
                ),
              ],
            ),
          ),
          Gap.w12,
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(color: scheme.onPrimary.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: const Icon(Icons.workspace_premium_rounded, size: 36, color: AppColors.gold),
          ),
        ],
      ),
    );
  }
}

class _FreeFeatures extends StatelessWidget {
  const _FreeFeatures({required this.catalog});
  final AddonCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final free = catalog.features.values.where((f) => f.isFree).toList()..sort((a, b) => a.sort.compareTo(b.sort));
    if (free.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.addonsFreeFeaturesTitle, style: theme.textTheme.titleMedium),
        Gap.h8,
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final f in free)
              Chip(
                avatar: Icon(Icons.check_rounded, size: 18, color: scheme.primary),
                label: Text(f.name(bangla: context.isBn)),
              ),
          ],
        ),
      ],
    );
  }
}
