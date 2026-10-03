import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddonsRepository {
  AddonsRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  static const _catalogKey = 'addons:catalog';
  static String _entitlementsKey(String uid) => 'entitlements:$uid';

  String? get _uid => _client.auth.currentUser?.id;

  /// Add-ons + feature names. Reference data → long cache; both tables are
  /// fetched in parallel in one cache entry so the store paints at once.
  Future<AddonCatalog> catalog({bool force = false}) {
    return _cache.get<AddonCatalog>(
      _catalogKey,
      forceRefresh: force,
      fetch: () async {
        final results = await Future.wait([
          guard(() => _client.from('addons').select(Addon.columns).eq('is_active', true).order('sort')),
          guard(() => _client.from('features').select(FeatureInfo.columns).order('sort')),
        ]);
        return AddonCatalog(
          addons: results[0].map(Addon.fromJson).toList(growable: false),
          features: {for (final f in results[1].map(FeatureInfo.fromJson)) f.code: f},
        );
      },
      encode: (c) => c.toJson(),
      decode: (j) => AddonCatalog.fromJson(Map<String, dynamic>.from(j! as Map)),
      policy: CachePolicy.long,
      isEmpty: (c) => c.addons.isEmpty,
    );
  }

  /// Entitlements that have not expired yet (running or stacked for later).
  Future<List<Entitlement>> entitlements({bool force = false}) async {
    final uid = _uid;
    if (uid == null) return const [];
    return _cache.get<List<Entitlement>>(
      _entitlementsKey(uid),
      forceRefresh: force,
      fetch: () async {
        final rows = await guard(
          () => _client
              .from('user_entitlements')
              .select(Entitlement.columns)
              .eq('user_id', uid)
              .gt('expires_at', DateTime.now().toUtc().toIso8601String())
              .order('expires_at', ascending: false)
              .limit(50),
        );
        return rows.map(Entitlement.fromJson).toList(growable: false);
      },
      encode: (v) => v.map((e) => e.toJson()).toList(),
      decode: (j) => (j! as List).map((e) => Entitlement.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      policy: const CachePolicy(ttl: Duration(minutes: 5)),
      isEmpty: (v) => v.isEmpty,
    );
  }

  /// Redeems a promo code. Throws `ServerFailure('promo_invalid' | 'promo_exhausted'
  /// | 'promo_already_used')` or `RateLimitFailure`.
  Future<PromoRedemption> redeemPromo(String code) async {
    final result = await _client.rpcMap('redeem_promo', params: {'p_code': normalizePromoCode(code)});
    final uid = _uid;
    if (uid != null) await _cache.invalidate(_entitlementsKey(uid));
    return PromoRedemption.fromJson(result);
  }

  Future<void> invalidateEntitlements() async {
    final uid = _uid;
    if (uid != null) await _cache.invalidate(_entitlementsKey(uid));
  }
}

final addonsRepositoryProvider = Provider<AddonsRepository>(
  (ref) => AddonsRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider)),
);
