import 'dart:collection';

/// Fixed-capacity least-recently-used map. O(1) get/put/evict, backed by a
/// [LinkedHashMap] whose insertion order is refreshed on every access.
class LruCache<K, V> {
  LruCache(this.capacity) : assert(capacity > 0, 'capacity must be positive');

  final int capacity;
  final _map = <K, V>{};

  int get length => _map.length;

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) _map[key] = value; // move to most-recent
    return value;
  }

  void put(K key, V value) {
    _map
      ..remove(key)
      ..[key] = value;
    if (_map.length > capacity) _map.remove(_map.keys.first); // evict LRU
  }

  void remove(K key) => _map.remove(key);

  void removeWhere(bool Function(K key) test) => _map.removeWhere((k, _) => test(k));

  void clear() => _map.clear();
}
