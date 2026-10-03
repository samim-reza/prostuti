import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';

/// Feature codes (mirror `public.features`). Paid vs. free is decided by the
/// backend, so packaging can change without an app release.
abstract final class Features {
  static const dailyNotes = 'daily_notes';
  static const dailyExam = 'daily_exam';
  static const modelTest = 'model_test';
  static const aiExplain = 'ai_explain';
  static const aiStudyPlan = 'ai_study_plan';
  static const smartPractice = 'smart_practice';
  static const adFree = 'ad_free';
  static const questionBank = 'question_bank';
  static const previousYear = 'previous_year';
}

/// `{feature_code: hasAccess}` for the signed-in user, cached for 10 minutes
/// and shared by every gate in the app (one request, not one per widget).
final featureAccessProvider = FutureProvider<Map<String, bool>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const {};
  final fetcher = ref.watch(cachedFetcherProvider);
  final client = ref.watch(supabaseProvider);
  return fetcher.get<Map<String, bool>>(
    'features:$userId',
    fetch: () async {
      final raw = await client.rpcMap('get_feature_access');
      return raw.map((k, v) => MapEntry(k, v == true));
    },
    encode: (v) => v,
    decode: (j) => Map<String, dynamic>.from(j! as Map).map((k, v) => MapEntry(k, v == true)),
    policy: const CachePolicy(ttl: Duration(minutes: 10)),
  );
});

/// Synchronous check for a single feature (false while loading).
final hasFeatureProvider = Provider.family<bool, String>((ref, feature) {
  return ref.watch(featureAccessProvider).value?[feature] ?? false;
});

/// Call after purchases/promo redemptions so gates re-evaluate immediately.
Future<void> refreshFeatureAccess(WidgetRef ref) async {
  final userId = ref.read(currentUserIdProvider);
  await ref.read(cachedFetcherProvider).invalidate('features:$userId');
  ref.invalidate(featureAccessProvider);
}

/// Shows [child] when the user has [feature]; otherwise a friendly upsell.
class EntitlementGate extends ConsumerWidget {
  const EntitlementGate({required this.feature, required this.child, this.lockedTitle, this.lockedMessage, super.key});

  final String feature;
  final Widget child;
  final String? lockedTitle;
  final String? lockedMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(featureAccessProvider);
    return access.when(
      skipLoadingOnRefresh: true,
      data: (map) => (map[feature] ?? false) ? child : LockedFeatureCard(title: lockedTitle, message: lockedMessage),
      loading: () => const Center(child: CircularProgressIndicator()),
      // Fail open to the server: RPCs still enforce access with HTTP 402.
      error: (_, _) => child,
    );
  }
}

class LockedFeatureCard extends StatelessWidget {
  const LockedFeatureCard({this.title, this.message, super.key});
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Gap.lg),
              decoration: BoxDecoration(color: scheme.secondary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(Icons.workspace_premium_rounded, size: 44, color: scheme.secondary),
            ),
            Gap.h16,
            Text(title ?? l.lockedTitle, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            Gap.h8,
            Text(
              message ?? l.lockedBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Gap.h24,
            FilledButton.icon(
              onPressed: () => context.push(Routes.addons),
              icon: const Icon(Icons.lock_open_rounded),
              label: Text(l.lockedCta),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the add-on store when a backend call fails with `feature_locked`.
void showLockedSheet(BuildContext context) {
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const Padding(
        padding: EdgeInsets.only(bottom: Gap.xl),
        child: LockedFeatureCard(),
      ),
    ),
  );
}
