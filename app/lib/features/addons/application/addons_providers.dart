import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/data/addons_repository.dart';

/// Add-ons and feature names (reference data, cached for hours).
final addonCatalogProvider = FutureProvider<AddonCatalog>((ref) {
  return ref.watch(addonsRepositoryProvider).catalog();
});

/// The signed-in user's running plans, one per add-on (trial/promo/purchase…).
final myPlansProvider = FutureProvider<List<ActivePlan>>((ref) async {
  ref.watch(currentUserIdProvider);
  final rows = await ref.watch(addonsRepositoryProvider).entitlements();
  return mergeEntitlements(rows, DateTime.now());
});

/// The plan to feature on the profile (Pro first), or null on the free plan.
final primaryPlanProvider = Provider<AsyncValue<ActivePlan?>>((ref) {
  return ref.watch(myPlansProvider).whenData(primaryPlan);
});

/// Forces a fresh catalog + plans (pull-to-refresh).
Future<void> refreshStore(WidgetRef ref) async {
  final repo = ref.read(addonsRepositoryProvider);
  await Future.wait([repo.catalog(force: true), repo.entitlements(force: true)]);
  ref
    ..invalidate(addonCatalogProvider)
    ..invalidate(myPlansProvider);
  await ref.read(myPlansProvider.future);
}

/// After a promo redemption or purchase: entitlements + every feature gate.
Future<void> refreshAfterPurchase(WidgetRef ref) async {
  await ref.read(addonsRepositoryProvider).invalidateEntitlements();
  await refreshFeatureAccess(ref);
  ref.invalidate(myPlansProvider);
}
