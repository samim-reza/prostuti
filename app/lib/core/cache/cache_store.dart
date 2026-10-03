import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:prostuti/core/cache/lru_cache.dart';

/// A cached value with its freshness metadata.
class CacheEntry {
  const CacheEntry({required this.data, required this.storedAt, required this.expiresAt, this.negative = false});

  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
    data: json['d'],
    storedAt: DateTime.fromMillisecondsSinceEpoch(json['s'] as int),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(json['e'] as int),
    negative: json['n'] as bool? ?? false,
  );

  /// JSON-compatible payload (`null` for negative entries).
  final Object? data;
  final DateTime storedAt;
  final DateTime expiresAt;

  /// A "known empty" result (cache-penetration protection).
  final bool negative;

  bool get isFresh => DateTime.now().isBefore(expiresAt);

  Map<String, dynamic> toJson() => {
    'd': data,
    's': storedAt.millisecondsSinceEpoch,
    'e': expiresAt.millisecondsSinceEpoch,
    'n': negative,
  };
}

/// Two-level cache: an in-memory LRU (L1, microseconds) in front of a Hive
/// box on disk (L2, survives restarts → instant cold start).
///
/// Values must be JSON-encodable. Expired entries are still returned by
/// [read] (callers decide whether stale data is acceptable — that's what
/// enables stale-while-revalidate); [purgeExpired] trims the disk.
class CacheStore {
  CacheStore._(this._box);

  static const _boxName = 'prostuti_cache_v1';

  final Box<String> _box;
  final _memory = LruCache<String, CacheEntry>(256);

  static Future<CacheStore> open() async {
    final box = await Hive.openBox<String>(_boxName);
    final store = CacheStore._(box);
    unawaited(store.purgeExpired(grace: const Duration(days: 7)));
    return store;
  }

  /// In-memory only store (tests). Passing `bytes` makes Hive keep the box
  /// in RAM without touching the file system.
  static Future<CacheStore> inMemory() async {
    final box = await Hive.openBox<String>(
      '${_boxName}_mem_${DateTime.now().microsecondsSinceEpoch}',
      bytes: Uint8List(0),
    );
    return CacheStore._(box);
  }

  CacheEntry? read(String key) {
    final hot = _memory.get(key);
    if (hot != null) return hot;
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final entry = CacheEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _memory.put(key, entry);
      return entry;
    } on Object {
      unawaited(_box.delete(key)); // corrupt entry
      return null;
    }
  }

  Future<void> write(String key, Object? data, Duration ttl, {bool persist = true}) {
    final now = DateTime.now();
    final entry = CacheEntry(data: data, storedAt: now, expiresAt: now.add(ttl));
    _memory.put(key, entry);
    return persist ? _box.put(key, jsonEncode(entry.toJson())) : Future.value();
  }

  /// Remembers that [key] has no data, so repeated lookups don't hit the
  /// network until [ttl] passes (negative caching).
  Future<void> writeNegative(String key, Duration ttl) {
    final now = DateTime.now();
    final entry = CacheEntry(data: null, storedAt: now, expiresAt: now.add(ttl), negative: true);
    _memory.put(key, entry);
    return _box.put(key, jsonEncode(entry.toJson()));
  }

  Future<void> invalidate(String key) {
    _memory.remove(key);
    return _box.delete(key);
  }

  /// Removes every key starting with [prefix] (e.g. `feed:`).
  Future<void> invalidatePrefix(String prefix) {
    _memory.removeWhere((k) => k.startsWith(prefix));
    return _box.deleteAll(_box.keys.where((k) => k.toString().startsWith(prefix)));
  }

  Future<void> clear() {
    _memory.clear();
    return _box.clear();
  }

  Future<void> purgeExpired({Duration grace = Duration.zero}) async {
    final cutoff = DateTime.now().subtract(grace).millisecondsSinceEpoch;
    final stale = <dynamic>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw == null) continue;
      final match = RegExp(r'"e":(\d+)').firstMatch(raw);
      final expires = int.tryParse(match?.group(1) ?? '');
      if (expires == null || expires < cutoff) stale.add(key);
    }
    if (stale.isNotEmpty) await _box.deleteAll(stale);
  }
}
