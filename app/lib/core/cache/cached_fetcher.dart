import 'dart:async';

import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/offline/connectivity.dart';

/// How long a cached value is considered fresh, and how long "no data"
/// answers are remembered.
class CachePolicy {
  const CachePolicy({required this.ttl, this.negativeTtl = const Duration(minutes: 2), this.persist = true});

  /// Fresh for a short while (user-specific, fast-changing data).
  static const short = CachePolicy(ttl: Duration(minutes: 2));
  static const medium = CachePolicy(ttl: Duration(minutes: 15));
  static const long = CachePolicy(ttl: Duration(hours: 6));

  /// Reference data (subjects, topics, add-ons…).
  static const catalog = CachePolicy(ttl: Duration(hours: 24), negativeTtl: Duration(minutes: 30));

  final Duration ttl;
  final Duration negativeTtl;

  /// Persist to disk (L2) or keep only in memory.
  final bool persist;
}

/// Read-through cache with:
///  * **single-flight**: concurrent requests for the same key share one
///    network call (prevents a cache stampede when many widgets ask at once);
///  * **stale-while-revalidate**: [watch] emits the cached value instantly,
///    then the fresh one;
///  * **negative caching**: an empty answer (`isEmpty` → true) is remembered
///    for `negativeTtl`, so missing data doesn't hammer the backend
///    (cache-penetration protection);
///  * **offline-first**: while offline, any cached value (fresh or stale) is
///    returned immediately instead of waiting for a request that can't succeed.
class CachedFetcher {
  CachedFetcher(this._store);

  final CacheStore _store;
  final _inFlight = <String, Future<Object?>>{};

  CacheStore get store => _store;

  /// Returns fresh cache if available, otherwise fetches (deduplicated).
  /// On network failure, falls back to stale data when present.
  Future<T> get<T>(
    String key, {
    required Future<T> Function() fetch,
    required Object? Function(T value) encode,
    required T Function(Object? json) decode,
    CachePolicy policy = CachePolicy.medium,
    bool Function(T value)? isEmpty,
    bool forceRefresh = false,
  }) async {
    final cached = _store.read(key);
    if (!forceRefresh && cached != null && cached.isFresh) {
      return decode(cached.data);
    }
    final connectivity = ConnectivityService.instance;
    if (cached != null && !connectivity.isOnline) {
      // Serve saved data instantly; if a network interface exists, quietly
      // try to refresh (a success flips the app back online).
      if (connectivity.hasInterface) {
        unawaited(_singleFlight<T>(key, fetch, encode, policy, isEmpty).then<void>((_) {}, onError: (Object _) {}));
      }
      return decode(cached.data);
    }
    try {
      return await _singleFlight<T>(key, fetch, encode, policy, isEmpty);
    } on Object {
      if (cached != null) return decode(cached.data);
      rethrow;
    }
  }

  /// Emits cached data first (even if stale), then the network result if the
  /// cache was missing or stale.
  Stream<T> watch<T>(
    String key, {
    required Future<T> Function() fetch,
    required Object? Function(T value) encode,
    required T Function(Object? json) decode,
    CachePolicy policy = CachePolicy.medium,
    bool Function(T value)? isEmpty,
  }) async* {
    final cached = _store.read(key);
    if (cached != null) {
      yield decode(cached.data);
      if (cached.isFresh || !ConnectivityService.instance.isOnline) return;
    }
    try {
      yield await _singleFlight<T>(key, fetch, encode, policy, isEmpty);
    } on Object {
      if (cached == null) rethrow;
    }
  }

  Future<T> _singleFlight<T>(
    String key,
    Future<T> Function() fetch,
    Object? Function(T value) encode,
    CachePolicy policy,
    bool Function(T value)? isEmpty,
  ) {
    final existing = _inFlight[key];
    if (existing != null) return existing.then((v) => v as T);

    final future = () async {
      final T value;
      try {
        value = await fetch();
        ConnectivityService.instance.reportSuccess();
      } on Object catch (e) {
        if (AppFailure.from(e) is NetworkFailure) ConnectivityService.instance.reportFailure();
        rethrow;
      }
      if (isEmpty != null && isEmpty(value)) {
        await _store.write(key, encode(value), policy.negativeTtl, persist: policy.persist);
      } else {
        await _store.write(key, encode(value), policy.ttl, persist: policy.persist);
      }
      return value;
    }();

    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<void> invalidate(String key) => _store.invalidate(key);
  Future<void> invalidatePrefix(String prefix) => _store.invalidatePrefix(prefix);
}
